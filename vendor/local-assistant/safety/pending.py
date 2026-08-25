"""Short-lived, in-memory state for safety-gated commands.

Pending commands deliberately do not survive a process restart.  Persisting a
destructive command to disk and replaying it in a later session would make a
confirmation reply ambiguous and unsafe.
"""
from __future__ import annotations

import copy
import re
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable


CONFIRM_RESPONSES = frozenset(
    {"yes", "yes confirm", "confirm", "confirmed", "proceed", "do it"}
)
CANCEL_RESPONSES = frozenset(
    {"no", "no cancel", "cancel", "cancel it", "never mind", "nevermind"}
)


def classify_response(text: str) -> str | None:
    """Return ``confirm`` or ``cancel`` for an explicit control reply."""
    normalized = re.sub(r"[^a-z0-9']+", " ", text.lower()).strip()
    if normalized in CONFIRM_RESPONSES:
        return "confirm"
    if normalized in CANCEL_RESPONSES:
        return "cancel"
    return None


@dataclass(frozen=True)
class PendingAction:
    """An exact tool invocation awaiting a short-lived user decision."""

    original_text: str
    tool_name: str
    arguments: dict[str, Any]
    requested_action: str
    confidence: float
    tier: str | None
    reason: str
    created_at: float
    expires_at: float


class PendingActionStore:
    """Thread-safe single-slot pending action store with fail-closed expiry."""

    def __init__(
        self,
        ttl_seconds: float = 30.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if ttl_seconds <= 0:
            raise ValueError("pending action timeout must be positive")
        self.ttl_seconds = float(ttl_seconds)
        self._clock = clock
        self._lock = threading.Lock()
        self._action: PendingAction | None = None

    def set(
        self,
        *,
        original_text: str,
        tool_name: str,
        arguments: dict[str, Any],
        requested_action: str,
        confidence: float,
        tier: str | None,
        reason: str,
    ) -> PendingAction:
        """Replace the slot with a defensive copy of one exact invocation."""
        now = self._clock()
        action = PendingAction(
            original_text=original_text,
            tool_name=tool_name,
            arguments=copy.deepcopy(arguments),
            requested_action=requested_action,
            confidence=confidence,
            tier=tier,
            reason=reason,
            created_at=now,
            expires_at=now + self.ttl_seconds,
        )
        with self._lock:
            self._action = action
        return action

    def inspect(self) -> tuple[PendingAction | None, bool]:
        """Return ``(action, expired)`` and erase expired state atomically."""
        with self._lock:
            if self._action is None:
                return None, False
            if self._clock() >= self._action.expires_at:
                self._action = None
                return None, True
            return self._action, False

    def pop(self) -> tuple[PendingAction | None, bool]:
        """Remove and return the live action, failing closed after expiry."""
        with self._lock:
            if self._action is None:
                return None, False
            action = self._action
            self._action = None
            if self._clock() >= action.expires_at:
                return None, True
            return action, False

    def remaining_seconds(self, action: PendingAction) -> int:
        """Return a display-safe whole-second countdown for a live action."""
        return max(0, round(action.expires_at - self._clock()))

    def clear(self) -> PendingAction | None:
        """Cancel and return the current action without executing it."""
        with self._lock:
            action = self._action
            self._action = None
            return action
