from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable


@dataclass
class ToolResult:
    success: bool
    message: str
    data: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class Tool(Protocol):
    name: str
    description: str

    def execute(self, arguments: dict[str, Any]) -> ToolResult:
        ...


def ok(message: str, **data: Any) -> ToolResult:
    return ToolResult(success=True, message=message, data=data)


def fail(message: str, **data: Any) -> ToolResult:
    return ToolResult(success=False, message=message, data=data)
