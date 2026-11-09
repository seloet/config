"""Confirmation / execution policy (plan §26, §27).

Policy gates, evaluated in order, BEFORE a tool runs:

  schema_invalid      -> reject (the registry raises; we surface a rejection)
  confidence < 0.8    -> clarify (ask back, do not execute)
  low                 -> execute
  medium              -> confirm_if_ambiguous (require confirmation when the
                         parse was ambiguous or low-confidence)
  high / unknown      -> require_explicit_confirmation (never auto-run)

Confidence levels (§27): 1.00 exact canonical · 0.95 direct regex + valid args
· 0.85 one alias · 0.70 several transforms · 0.50 ambiguous · 0.00 unsupported.
"""
from __future__ import annotations

from typing import Any

from .risk import HIGH, MEDIUM, LOW, tier_of

CLARIFY_THRESHOLD = 0.8


def decide(
    tool_name: str,
    confidence: float,
    ambiguous: bool = False,
    tiers: dict[str, str] | None = None,
) -> str:
    """Return one of: reject | clarify | execute | confirm_if_ambiguous
    | require_explicit_confirmation.

    Args:
        tool_name: the resolved tool name.
        confidence: parse confidence (0..1); use 0.0 for unsupported parses.
        ambiguous: True when the parse was ambiguous (multiple parsers matched).
        tiers: optional risk-tier mapping; defaults to the plan's tiers.
    """
    if confidence <= 0.0:
        return "reject"
    if confidence < CLARIFY_THRESHOLD:
        return "clarify"
    tier = tier_of(tool_name, tiers)
    if tier is None:
        return "require_explicit_confirmation"
    if tier == LOW:
        return "execute"
    if tier == MEDIUM:
        return "confirm_if_ambiguous" if ambiguous else "execute"
    return "require_explicit_confirmation"
