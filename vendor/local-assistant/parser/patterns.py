from __future__ import annotations
import re
from .numbers import words_to_number
from .result import ParseResult
from .aliases import apply_asr_aliases
from tools.applications import canonicalize

OPEN_RE = re.compile(r"^(?:open|opened|launch|launched|start|run|show)\s+(?P<app>.+)$", re.IGNORECASE)
VOL_RE = re.compile(
    r"^(?:set|turn)?\s+(?:the\s+)?(?:sound\s+)?volume\s+(?:to|at|up\s+to|down\s+to)?\s*"
    r"(?P<val>\d{1,3}|[a-z\s]+?)(?:\s*percent)?$", re.IGNORECASE)
TIME_RE = re.compile(r"^(?:what\s+is\s+)?(?:the\s+)?(?:current\s+)?times?$", re.IGNORECASE)
NOTE_RE = re.compile(r"^(?:create|make|add|take|note)\s+(?:that\s+)?(?:i\s+should\s+)?(?:a\s+)?note(?:\s+saying|\s+:)?\s*(?P<text>.+)$", re.IGNORECASE)
SEARCH_RE = re.compile(r"^(?:search|find|look\s+for)\s+(?:files?\s+)?(?:for\s+)?(?P<q>.+)$", re.IGNORECASE)
MEDIA_RE = re.compile(
    r"^(?:media|music|playback)\s+(?P<a1>play|pause|toggle|next|previous|stop)\b"
    r"|^(?P<a2>play|pause|resume)\s+(?:the\s+)?(?:music|media|song|track)\b"
    r"|^(?P<a3>skip|next)\s+(?:track|song)\b"
    r"|^(?P<a4>previous|last)\s+(?:track|song)\b",
    re.IGNORECASE,
)
LOCK_RE = re.compile(r"^(?:lock|secure)\s+(?:the\s+)?(?:screen|session|computer)\b", re.IGNORECASE)


def _canonical_app(app: str) -> str | None:
    # returns canonical registry id (e.g. 'vscode') or None if unknown
    return canonicalize(app)


def parse_open(t: str, norm: str) -> ParseResult | None:
    m = OPEN_RE.match(norm)
    if not m:
        return None
    app = m.group("app").strip()
    app = re.sub(r"^(?:the|a|an)\s+", "", app, flags=re.IGNORECASE).strip()
    app, n = apply_asr_aliases(app)
    canon = _canonical_app(app)
    if canon is None:
        return None
    conf = 0.95 if n == 0 else 0.85
    return ParseResult(matched=True, tool_name="open_application",
                       arguments={"application": canon}, confidence=conf,
                       original_text=t, normalized_text=norm)


def parse_volume(t: str, norm: str) -> ParseResult | None:
    m = VOL_RE.match(norm)
    if not m:
        return None
    raw = m.group("val").strip()
    # ASR may append "per cent"/"percent" mid-value ("thirty per cent") or the
    # word "per"; drop those fillers before number conversion. A clipped tail
    # like "thirty per c" (cent cut off) leaves a stray trailing "c" — strip a
    # lone trailing "c" after the number word too.
    raw = re.sub(r"\b(per\s*cent|percent|per)\b", " ", raw, flags=re.IGNORECASE)
    raw = re.sub(r"\s+", " ", raw).strip()
    raw = re.sub(r"\bc\b\s*$", "", raw, flags=re.IGNORECASE).strip()
    val = words_to_number(raw) if not raw.isdigit() else int(raw)
    if val is None:
        return ParseResult(matched=False, tool_name="set_volume",
                           reason="invalid_number", original_text=t, normalized_text=norm)
    from tools.schemas import SetVolumeArgs
    try:
        SetVolumeArgs(percent=val)
    except Exception:
        return ParseResult(matched=False, tool_name="set_volume",
                           reason="invalid_number", original_text=t, normalized_text=norm)
    return ParseResult(matched=True, tool_name="set_volume",
                       arguments={"percent": val}, confidence=0.95,
                       original_text=t, normalized_text=norm)


def parse_time(t: str, norm: str) -> ParseResult | None:
    if TIME_RE.match(norm):
        return ParseResult(matched=True, tool_name="get_time", arguments={},
                           confidence=1.0, original_text=t, normalized_text=norm)
    return None


def parse_note(t: str, norm: str) -> ParseResult | None:
    m = NOTE_RE.match(norm)
    if not m:
        return None
    return ParseResult(matched=True, tool_name="create_note",
                       arguments={"text": m.group("text").strip()},
                       confidence=0.95, original_text=t, normalized_text=norm)


def parse_search(t: str, norm: str) -> ParseResult | None:
    m = SEARCH_RE.match(norm)
    if not m:
        return None
    return ParseResult(matched=True, tool_name="search_files",
                       arguments={"query": m.group("q").strip()},
                       confidence=0.95, original_text=t, normalized_text=norm)


def parse_lock(t: str, norm: str) -> ParseResult | None:
    if not LOCK_RE.match(norm):
        return None
    return ParseResult(matched=True, tool_name="lock_screen", arguments={},
                       confidence=0.95, original_text=t, normalized_text=norm)


def parse_media(t: str, norm: str) -> ParseResult | None:
    m = MEDIA_RE.match(norm)
    if not m:
        return None
    action = (m.group("a1") or m.group("a2") or m.group("a3")
              or m.group("a4") or "").lower()
    if action in {"skip", "next"}:
        action = "next"
    elif action in {"previous", "last"}:
        action = "previous"
    elif action == "resume":
        action = "play"
    return ParseResult(matched=True, tool_name="play_pause_media",
                       arguments={"action": action}, confidence=0.95,
                       original_text=t, normalized_text=norm)
