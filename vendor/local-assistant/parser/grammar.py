"""Phase 8 — Grammar-based command parser (pyparsing).

The regex layer (:mod:`parser.patterns`) is fast and precise for the fixed
word-order phrasings it was written for, but it cannot (cleanly) express:

  * **multi-clause commands** — ``"open firefox and play music"``,
    ``"set volume to forty then tell me the time"``;
  * **flexible word order** — ``"volume to fifty set"``,
    ``"the volume turn up to thirty"``.

This module introduces a small pyparsing grammar that handles exactly those
cases. It is wired in as a *fallback* behind the regex parser (see
:func:`parser.command_parser.parse`): regex matches keep their higher
confidence (0.95/0.85); the grammar only runs on a phrase the regex layer
rejected, and it emits a slightly lower confidence (0.85) because it applies
more structural transforms.

The grammar produces one :class:`~parser.result.ParseResult` per *intent*. A
single intent is returned directly; several intents (a multi-clause command)
are returned as one ``ParseResult`` whose ``subcommands`` field lists the
individual per-intent results — the orchestrator dispatches each in order.

Grammar coverage (kept intentionally in lock-step with the regex layer):
``open_application``, ``set_volume``, ``get_time``, ``create_note``,
``search_files``, ``play_pause_media``, ``lock_screen``.
"""
from __future__ import annotations

import re

from pyparsing import (
    CaselessKeyword,
    Group,
    ParseResults,
    SkipTo,
    StringEnd,
    Suppress,
    Word,
    alphanums,
    delimited_list,  # noqa: F401  (kept available for future grammar tweaks)
    one_of,
)
from pyparsing.core import ParserElement

from .aliases import apply_asr_aliases
from .numbers import words_to_number
from .patterns import _canonical_app
from .result import ParseResult

# Grammar parses are structural transforms -> sit at the 0.85 confidence tier
# (per the plan's confidence scale: 0.85 = one alias / transform applied).
GRAMMAR_CONFIDENCE = 0.85


# --------------------------------------------------------------------------- #
# Grammar building blocks
# --------------------------------------------------------------------------- #
_KW_VERB_OPEN = one_of("open opened launch launched start run show", caseless=True)
_KW_VERB_VOL = one_of("set turn", caseless=True)
_KW_VERB_NOTE = one_of("create make add take note", caseless=True)
_KW_VERB_SEARCH = one_of("search find", caseless=True)
_KW_VERB_LOCK = one_of("lock secure", caseless=True)
_KW_VERB_MEDIA = one_of("play pause resume skip next previous toggle stop", caseless=True)

_CONJ = (
    Suppress(",")
    | CaselessKeyword("and")
    | CaselessKeyword("then")
    | CaselessKeyword("also")
    | CaselessKeyword("after that")
    | CaselessKeyword("afterwards")
)
# Anything that terminates a clause: a conjunction or end-of-input.
_CLAUSE_STOP = _CONJ | StringEnd()

# A bare word (app names, search terms, note bodies, etc.).
_WORD = Word(alphanums + "'-_.")


def _skip_clause() -> SkipTo:
    """Capture the remainder of the current clause up to the next conjunction."""
    return SkipTo(_CLAUSE_STOP, greedy=False)


# --------------------------------------------------------------------------- #
# Intent grammars
# --------------------------------------------------------------------------- #
def _build_open() -> ParserElement:
    kw = _KW_VERB_OPEN.copy()
    expr = kw + _skip_clause()("app")
    expr.set_parse_action(_act_open)
    return Group(expr)


def _act_open(toks: ParseResults) -> dict:
    app_raw = toks["app"].strip()
    # strip a leading article the regex layer also drops
    app_raw = re.sub(r"^(the|a|an)\s+", "", app_raw, flags=re.IGNORECASE).strip()
    app, n = apply_asr_aliases(app_raw)
    canon = _canonical_app(app)
    if canon is None:
        return {"_reject": True}
    return {
        "tool_name": "open_application",
        "arguments": {"application": canon},
        "confidence": GRAMMAR_CONFIDENCE - (0.0 if n == 0 else 0.05),
    }


def _build_volume() -> ParserElement:
    # A volume command always contains the keyword ``volume``; everything after
    # it (the value) is captured and the filler words (leading/trailing verb,
    # prepositions, "percent") are stripped by :func:`_volume_value`. This makes
    # word order irrelevant: "set volume to forty", "volume to fifty set", and
    # "turn volume up to thirty" all match.
    value = SkipTo(StringEnd())("val")
    expr = (
        _KW_VERB_VOL.copy()[0, 1]
        + Suppress(CaselessKeyword("the"))[0, 1]
        + Suppress(CaselessKeyword("sound"))[0, 1]
        + CaselessKeyword("volume")
        + value
    )
    expr.set_parse_action(_act_volume)
    return Group(expr)


def _act_volume(toks: ParseResults) -> dict:
    raw = toks["val"].strip()
    val = _volume_value(raw)
    if val is None:
        return {"_reject": True}
    return {
        "tool_name": "set_volume",
        "arguments": {"percent": val},
        "confidence": GRAMMAR_CONFIDENCE,
    }


def _volume_value(raw: str) -> int | None:
    # strip leading verb / prepositions iteratively ("turn volume up to thirty"
    # -> "thirty"; "volume to fifty set" -> "fifty"); an iteration loop handles
    # stacked fillers like "up to" after a leading verb was removed.
    prev = None
    while prev != raw:
        prev = raw
        raw = re.sub(r"^(set|turn|to|at|up to|down to)\s+", "", raw, flags=re.IGNORECASE)
    # strip a trailing verb ("volume to fifty set" -> "volume to fifty")
    raw = re.sub(r"\s+(set|turn)$", "", raw, flags=re.IGNORECASE)
    raw = re.sub(r"\b(per\s*cent|percent|per)\b", " ", raw, flags=re.IGNORECASE)
    raw = re.sub(r"\s+", " ", raw).strip()
    raw = re.sub(r"\bc\b\s*$", "", raw, flags=re.IGNORECASE).strip()
    val = words_to_number(raw) if not raw.isdigit() else int(raw)
    if val is None:
        return None
    from tools.schemas import SetVolumeArgs

    try:
        SetVolumeArgs(percent=val)
    except Exception:
        return None
    return val


def _build_time() -> ParserElement:
    expr = (
        Suppress(CaselessKeyword("what") + CaselessKeyword("is"))[0, 1]
        + Suppress(CaselessKeyword("the"))[0, 1]
        + Suppress(CaselessKeyword("current"))[0, 1]
        + CaselessKeyword("time")
    )
    expr.set_parse_action(
        lambda _: {
            "tool_name": "get_time",
            "arguments": {},
            "confidence": 1.0,
        }
    )
    return Group(expr)


def _build_note() -> ParserElement:
    # "make a note saying ..." / "create a note ..." / "add a note ..." /
    # "note that i should ..." / bare "note ...".
    verb_form = _KW_VERB_NOTE.copy() + Suppress(CaselessKeyword("a"))[0, 1] + CaselessKeyword("note")
    note_form = CaselessKeyword("note")
    expr = (
        (verb_form | note_form)
        + Suppress(CaselessKeyword("that") + CaselessKeyword("i") + CaselessKeyword("should"))[0, 1]
        + Suppress(one_of("saying :", caseless=True))[0, 1]
        + _skip_clause()("text")
    )
    expr.set_parse_action(lambda t: {
        "tool_name": "create_note",
        "arguments": {"text": t["text"].strip()},
        "confidence": GRAMMAR_CONFIDENCE,
    })
    return Group(expr)


def _build_search() -> ParserElement:
    expr = (
        _KW_VERB_SEARCH.copy()
        + Suppress(CaselessKeyword("files"))[0, 1]
        + Suppress(CaselessKeyword("for"))[0, 1]
        + _skip_clause()("query")
    )
    expr.set_parse_action(lambda t: {
        "tool_name": "search_files",
        "arguments": {"query": t["query"].strip()},
        "confidence": GRAMMAR_CONFIDENCE,
    })
    return Group(expr)


def _build_lock() -> ParserElement:
    expr = (
        _KW_VERB_LOCK.copy()
        + Suppress(CaselessKeyword("the"))[0, 1]
        + one_of("screen session computer", caseless=True)
    )
    expr.set_parse_action(lambda _: {
        "tool_name": "lock_screen",
        "arguments": {},
        "confidence": GRAMMAR_CONFIDENCE,
    })
    return Group(expr)


def _build_media() -> ParserElement:
    # Forms:
    #   "<action> (the) (music|media|song|track)"  e.g. "play the music"
    #   "(media|music|playback) <action>"          e.g. "media pause"
    obj = one_of("music media song track", caseless=True)
    action_kw = _KW_VERB_MEDIA.copy()
    form1 = action_kw("action") + Suppress(CaselessKeyword("the"))[0, 1] + obj[0, 1]
    form2 = obj + action_kw("action")
    expr = form1 | form2
    expr.set_parse_action(_act_media)
    return Group(expr)


def _act_media(toks: ParseResults) -> dict:
    action = toks.get("action", "").lower()
    if action in {"skip", "next"}:
        action = "next"
    elif action in {"previous", "last"}:
        action = "previous"
    elif action == "resume":
        action = "play"
    elif action == "playback":
        action = "play"
    return {
        "tool_name": "play_pause_media",
        "arguments": {"action": action},
        "confidence": GRAMMAR_CONFIDENCE,
    }


# --------------------------------------------------------------------------- #
# Full grammar
# --------------------------------------------------------------------------- #
# A single intent (used to parse one clause). No conjunction handling here --
# multi-clause commands are split on conjunctions in :func:`parse_grammar`
# before each clause is parsed independently, which avoids a greedy intent
# (e.g. ``open``) swallowing the whole tail of a multi-clause command.
_SINGLE_INTENT = (
    _build_open()
    | _build_volume()
    | _build_time()
    | _build_note()
    | _build_search()
    | _build_lock()
    | _build_media()
)

# Conjunction splitter: separates coordinated clauses. Handles the multi-word
# conjunctions first so "after that" isn't split as "after" / "that". Word
# boundaries prevent mid-word false splits (e.g. "st**and** up").
_CONJ_RE = re.compile(
    r"\s*(?:\b(?:after\s+that|afterwards|then|also|and)\b|,)\s*",
    re.IGNORECASE,
)


def _split_clauses(norm: str) -> list[str]:
    """Split a normalized command into coordinated clauses on conjunctions."""
    parts = _CONJ_RE.split(norm)
    return [p.strip() for p in parts if p and p.strip()]


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #
def parse_grammar(text: str) -> ParseResult | None:
    """Parse ``text`` with the grammar.

    Returns ``None`` if the grammar cannot interpret the text (so the caller can
    fall through to an ``unsupported_command`` result). Returns a single
    :class:`ParseResult` for one intent, or a ``ParseResult`` with its
    ``subcommands`` field populated for a multi-clause command.

    The input is run through :func:`parser.normalizer.normalize` first; ASR-error
    aliases are applied inside the per-intent actions. Multi-clause commands are
    split on conjunctions and each clause is parsed independently, then the
    per-intent results are recombined.
    """
    from .normalizer import normalize

    norm = normalize(text)
    if not norm:
        return None

    clauses = _split_clauses(norm)
    results: list[ParseResult] = []
    for clause in clauses:
        try:
            parsed = _SINGLE_INTENT.parse_string(clause, parse_all=True)
        except Exception:
            # A clause the grammar can't interpret: skip it (the whole command
            # falls through to unsupported only if *every* clause fails).
            continue
        for intent in _collect_dicts(parsed):
            if intent.get("_reject"):
                continue
            results.append(
                ParseResult(
                    matched=True,
                    tool_name=intent["tool_name"],
                    arguments=intent["arguments"],
                    confidence=intent["confidence"],
                    original_text=text,
                    normalized_text=norm,
                )
            )

    if not results:
        return None
    if len(results) == 1:
        return results[0]
    return ParseResult(
        matched=True,
        tool_name=None,
        arguments={},
        confidence=min(r.confidence for r in results),
        original_text=text,
        normalized_text=norm,
        subcommands=results,
    )


def _collect_dicts(node) -> list[dict]:
    """Recursively pull the per-intent dicts out of a pyparsing result tree.

    Each intent is ``Group``-wrapped, so the dicts live one level down inside a
    ``ParseResults``; this walks the tree regardless of nesting so a single
    intent and a multi-clause command are both collected correctly.
    """
    out: list[dict] = []
    if isinstance(node, dict):
        out.append(node)
    elif isinstance(node, (list, tuple, ParseResults)):
        for child in node:
            out.extend(_collect_dicts(child))
    return out
