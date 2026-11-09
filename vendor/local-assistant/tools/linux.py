from __future__ import annotations
import subprocess
from pathlib import Path
from .base import ToolResult, ok, fail
from .applications import resolve
from .schemas import (
    OpenApplicationArgs, SetVolumeArgs, GetTimeArgs,
    CreateNoteArgs, SearchFilesArgs, PlayPauseMediaArgs, LockScreenArgs,
)

NOTES_DIR = Path.home() / "Notes"
ALLOWED_SEARCH_ROOTS = [Path.home()]  # fail-safe: only search under $HOME


def open_application(arguments: dict) -> ToolResult:
    args = OpenApplicationArgs(**arguments)
    cmd = resolve(args.application, "linux")
    if cmd is None:
        return fail(f"Unknown application: {args.application}", application=args.application)
    try:
        subprocess.Popen(cmd, start_new_session=True)
        return ok(f"Opened {args.application}", application=args.application, command=cmd)
    except Exception as e:  # noqa: BLE001
        return fail(f"Failed to open {args.application}: {e}")


def set_volume(arguments: dict) -> ToolResult:
    args = SetVolumeArgs(**arguments)
    frac = max(0.0, min(1.0, args.percent / 100.0))
    try:
        subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{frac:.2f}"],
                       check=True, capture_output=True)
        return ok(f"Volume set to {args.percent} percent", percent=args.percent)
    except subprocess.CalledProcessError as e:
        return fail(f"wpctl failed: {e.stderr.decode().strip()}")
    except FileNotFoundError:
        return fail("wpctl not found")


def get_time(arguments: dict) -> ToolResult:
    GetTimeArgs(**arguments)
    from datetime import datetime
    now = datetime.now().strftime("%H:%M")
    return ok(f"The time is {now}", time=now)


def create_note(arguments: dict) -> ToolResult:
    args = CreateNoteArgs(**arguments)
    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    stamp = __import__("datetime").datetime.now().strftime("%Y%m%d-%H%M%S")
    name = (args.title or "note").strip().replace("/", "_")[:40]
    path = NOTES_DIR / f"{stamp}-{name}.md"
    path.write_text(f"# {args.title or 'Note'}\n\n{args.text}\n")
    return ok(f"Note saved to {path.name}", path=str(path))


def search_files(arguments: dict) -> ToolResult:
    args = SearchFilesArgs(**arguments)
    import os
    hits: list[str] = []
    q = args.query.lower()
    for root in ALLOWED_SEARCH_ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {
                ".git", "node_modules", ".cache", ".cargo", ".venv", ".npm"}]
            for fn in filenames:
                if q in fn.lower():
                    hits.append(str(Path(dirpath) / fn))
                    if len(hits) >= args.max_results:
                        return ok(f"Found {len(hits)} matching files", files=hits)
    if not hits:
        return ok("No matching files found", files=[])
    return ok(f"Found {len(hits)} matching files", files=hits)


_PLAYERCTL_CMD = {
    "play": "play",
    "pause": "pause",
    "toggle": "play-pause",
    "next": "next",
    "previous": "previous",
    "stop": "stop",
}


def play_pause_media(arguments: dict) -> ToolResult:
    args = PlayPauseMediaArgs(**arguments)
    action = args.action or "toggle"
    subcmd = _PLAYERCTL_CMD.get(action, "play-pause")
    try:
        subprocess.run(["playerctl", subcmd], check=True, capture_output=True)
        return ok(f"Media {action}", action=action)
    except subprocess.CalledProcessError as e:
        return fail(f"playerctl failed: {e.stderr.decode().strip()}")
    except FileNotFoundError:
        return fail("playerctl not found")


_LOCK_CMD = ["loginctl", "lock-session"]


def lock_screen(arguments: dict) -> ToolResult:
    LockScreenArgs(**arguments)
    try:
        subprocess.run(_LOCK_CMD, check=True, capture_output=True)
        return ok("Screen locked")
    except subprocess.CalledProcessError as e:
        return fail(f"loginctl failed: {e.stderr.decode().strip()}")
    except FileNotFoundError:
        return fail("loginctl not found")
