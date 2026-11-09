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
        gram = parse_grammar(text)
        if gram is not None:
            return gram
        # Learned fallbacks stay low-confidence so the safety gate validates them.
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
