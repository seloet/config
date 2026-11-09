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
    subcommands: list["ParseResult"] | None = None

    def __post_init__(self):
        if self.arguments is None:
            self.arguments = {}
