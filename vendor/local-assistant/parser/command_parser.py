from __future__ import annotations
from .normalizer import normalize
from .result import ParseResult
from .patterns import (parse_open, parse_volume, parse_time,
                        parse_note, parse_search, parse_media, parse_lock)
from .grammar import parse_grammar
from .intent_classifier import predict_intent


PARSERS = [parse_open, parse_volume, parse_time, parse_note, parse_search, parse_media, parse_lock]


def parse(text: str) -> ParseResult:
    norm = normalize(text)
    results = []
    for p in PARSERS:
        r = p(text, norm)
        if r is not None:
            results.append(r)
    if not results:
        # Phase 8: grammar fallback. The regex layer is precise and higher
        # confidence for the phrasings it knows; the grammar only runs when the
        # regex layer rejects the text, and it handles the cases regex can't
        # (multi-clause conjunctions, flexible word order). Single-intent
        # grammar matches are returned directly; multi-clause commands come back
        # as one ParseResult whose ``subcommands`` carry each intent.
        gram = parse_grammar(text)
        if gram is not None:
            return gram
        # Phase 10: learned intent fallback. Only reached when both the regex
        # layer and the grammar reject the text. A CPU-only kNN classifier
        # predicts the most likely tool; if its score clears the adoption
        # threshold we return a *low-confidence* parse so the safety gate still
        # validates it. This can only help the unmatched fraction — it never
        # overrides a rule/grammar match, so it cannot regress accuracy.
        tool, score, args = predict_intent(text)
        if tool is not None:
            return ParseResult(
                matched=True, tool_name=tool, arguments=args,
                confidence=0.5, original_text=text, normalized_text=norm,
                reason="learned_fallback",
            )
        return ParseResult(matched=False, reason="unsupported_command",
                           original_text=text, normalized_text=norm)
    if len(results) > 1:
        return ParseResult(matched=False, reason="ambiguous_command",
                           candidates=[r.tool_name for r in results],
                           original_text=text, normalized_text=norm)
    return results[0]
