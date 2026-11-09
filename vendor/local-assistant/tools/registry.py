from __future__ import annotations
from typing import Any
from .base import ToolResult, ok, fail
from .linux import (
    open_application, set_volume, get_time, create_note, search_files,
    play_pause_media, lock_screen,
)
from .schemas import (
    OpenApplicationArgs, SetVolumeArgs, GetTimeArgs,
    CreateNoteArgs, SearchFilesArgs, PlayPauseMediaArgs, LockScreenArgs,
)

TOOL_REGISTRY: dict[str, tuple[Any, type]] = {
    "open_application": (open_application, OpenApplicationArgs),
    "set_volume":       (set_volume, SetVolumeArgs),
    "get_time":         (get_time, GetTimeArgs),
    "create_note":      (create_note, CreateNoteArgs),
    "search_files":     (search_files, SearchFilesArgs),
    "play_pause_media": (play_pause_media, PlayPauseMediaArgs),
    "lock_screen":      (lock_screen, LockScreenArgs),
}


def call_tool(name: str, arguments: dict[str, Any]) -> ToolResult:
    if name not in TOOL_REGISTRY:
        return fail(f"Unknown tool: {name}", name=name)
    executor, schema = TOOL_REGISTRY[name]
    try:
        validated = schema(**arguments).model_dump()
    except Exception as e:  # noqa: BLE001  (Pydantic ValidationError caught here)
        return fail(f"Invalid arguments for {name}: {e}", name=name)
    return executor(validated)
