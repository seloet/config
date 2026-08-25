from __future__ import annotations
from dataclasses import dataclass
from typing import Any


@dataclass
class ParseResult:
    matched: bool
    tool_name: str | None = None
    arguments: dict[str, Any] = None
    confidence: float = 0.0
    original_text: str = ""
    normalized_text: str = ""
    reason: str | None = None
    candidates: list[str] | None = None
    # Phase 8: a multi-clause command (e.g. "open firefox and play music")
    # parses to several intents. The grammar returns one ParseResult whose
    # subcommands list carries each per-intent result; single-intent parses
    # leave this None. Backward compatible: existing callers ignore it.
    subcommands: list["ParseResult"] | None = None

    def __post_init__(self):
        if self.arguments is None:
            self.arguments = {}
