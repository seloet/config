"""Safety validation layer: gate a parsed command before execution.

Combines the risk tiers (risk.py) and confirmation policy (confirmation.py)
with the parser's ParseResult to produce a single decision and a
human-readable reason. This is the cross-cutting gate the orchestrator calls
after parsing and before dispatching to the tool registry.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from parser.result import ParseResult

from .confirmation import decide
from .risk import tier_of

# Decision vocabulary (mirrors safety.confirmation.decide + unsupported).
REJECT = "reject"
CLARIFY = "clarify"
EXECUTE = "execute"
CONFIRM_IF_AMBIGUOUS = "confirm_if_ambiguous"
REQUIRE_EXPLICIT_CONFIRMATION = "require_explicit_confirmation"


@dataclass
class SafetyDecision:
    action: str  # one of the constants above
    tool_name: str | None
    confidence: float
    tier: str | None
    ambiguous: bool
    reason: str

    @property
    def execute_now(self) -> bool:
        return self.action == EXECUTE

    @property
    def needs_confirmation(self) -> bool:
        return self.action in (CONFIRM_IF_AMBIGUOUS, REQUIRE_EXPLICIT_CONFIRMATION)

    @property
    def should_reject(self) -> bool:
        return self.action == REJECT

    @property
    def should_clarify(self) -> bool:
        return self.action == CLARIFY


def validate(
    result: ParseResult,
    tiers: dict[str, str] | None = None,
) -> SafetyDecision:
    """Decide what to do with a parsed command.

    An unmatched / unsupported parse (``matched is False``) is rejected rather
    than dispatched. A matched parse is routed through the risk + confidence
    policy. The returned :class:`SafetyDecision` is the single source of truth
    the orchestrator acts on.
    """
    if not result.matched:
        tool_name: str | None = result.tool_name
        return SafetyDecision(
            action=REJECT,
            tool_name=tool_name,
            confidence=result.confidence,
            tier=tier_of(tool_name, tiers) if tool_name else None,
            ambiguous=False,
            reason=result.reason or "unsupported_command",
        )

    tool_name = result.tool_name or ""
    action = decide(
        tool_name,
        result.confidence,
        ambiguous=result.reason == "ambiguous_command"
        or (result.candidates is not None and len(result.candidates) > 1),
        tiers=tiers,
    )
    return SafetyDecision(
        action=action,
        tool_name=tool_name,
        confidence=result.confidence,
        tier=tier_of(tool_name, tiers),
        ambiguous=action == CONFIRM_IF_AMBIGUOUS and bool(result.candidates),
        reason=f"risk={tier_of(tool_name, tiers)};confidence={result.confidence:.2f}",
    )
