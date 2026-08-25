"""Install LocalAssistant as a user-scoped background application.

The installer writes either a systemd user service or an XDG autostart desktop
entry. It never needs root privileges and supports ``--dry-run`` for inspection.
"""
from __future__ import annotations

import argparse
import shlex
import sys
from pathlib import Path

SYSTEMD_NAME = "local-assistant.service"
DESKTOP_NAME = "local-assistant.desktop"


def _command_args(
    python: Path,
    app: Path,
    tray: bool,
    speech_config: Path | None = None,
) -> list[str]:
    args = [str(python), str(app), "--play-chime", "--tray" if tray else "--mic"]
    if speech_config is not None:
        args.extend(["--config", str(speech_config)])
    return args


def _systemd_command(
    python: Path,
    app: Path,
    tray: bool,
    speech_config: Path | None = None,
) -> str:
    args = _command_args(python, app, tray, speech_config)
    return " ".join(shlex.quote(arg) for arg in args)


def _desktop_quote(arg: str) -> str:
    """Quote one argument according to the Desktop Entry Exec grammar."""
    if not any(char.isspace() or char in '"\\`$' for char in arg):
        return arg
    escaped = arg.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`")
    escaped = escaped.replace("$", "\\$")
    return f'"{escaped}"'


def _desktop_command(
    python: Path,
    app: Path,
    tray: bool,
    speech_config: Path | None = None,
) -> str:
    args = _command_args(python, app, tray, speech_config)
    return " ".join(_desktop_quote(arg) for arg in args)


def systemd_unit(
    python: Path,
    app: Path,
    speech_config: Path | None = None,
) -> str:
    """Return a systemd user unit for a headless microphone service."""
    command = _systemd_command(python, app, tray=False, speech_config=speech_config)
    return f"""[Unit]
Description=LocalAssistant voice assistant
After=graphical-session.target sound.target

[Service]
Type=simple
WorkingDirectory={shlex.quote(str(app.parent))}
ExecStart={command}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
"""


def desktop_entry(
    python: Path,
    app: Path,
    speech_config: Path | None = None,
) -> str:
    """Return an XDG autostart entry including the graphical tray."""
    command = _desktop_command(python, app, tray=True, speech_config=speech_config)
    return f"""[Desktop Entry]
Type=Application
Name=LocalAssistant
Comment=Always-on local voice assistant
Exec={command}
Terminal=false
X-GNOME-Autostart-enabled=true
"""


def target_path(mode: str, config_home: Path) -> Path:
    if mode == "systemd":
        return config_home / "systemd" / "user" / SYSTEMD_NAME
    return config_home / "autostart" / DESKTOP_NAME


def install(
    mode: str,
    *,
    config_home: Path,
    python: Path,
    app: Path,
    speech_config: Path | None = None,
    remove: bool = False,
    dry_run: bool = False,
) -> Path:
    """Install or remove one autostart definition and return its path."""
    target = target_path(mode, config_home)
    if remove:
        if not dry_run:
            target.unlink(missing_ok=True)
        return target

    content = (
        systemd_unit(python, app, speech_config)
        if mode == "systemd"
        else desktop_entry(python, app, speech_config)
    )
    if not dry_run:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Install LocalAssistant user autostart configuration"
    )
    parser.add_argument(
        "--mode",
        choices=("systemd", "desktop"),
        default="systemd",
        help="headless systemd service or graphical XDG tray autostart",
    )
    parser.add_argument("--remove", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--speech-config",
        type=Path,
        help="absolute-path model config to pass to the installed assistant",
    )
    parser.add_argument(
        "--config-home",
        type=Path,
        default=Path.home() / ".config",
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args(argv)

    app = Path(__file__).resolve().parents[1] / "app.py"
    speech_config = None
    if args.speech_config is not None:
        speech_config = args.speech_config.expanduser().resolve()
        if not speech_config.is_file():
            parser.error(f"speech config is not a file: {speech_config}")
    target = target_path(args.mode, args.config_home)
    if args.dry_run and not args.remove:
        content = (
            systemd_unit(Path(sys.executable), app, speech_config)
            if args.mode == "systemd"
            else desktop_entry(Path(sys.executable), app, speech_config)
        )
        print(content, end="")
        print(f"# target: {target}", file=sys.stderr)
        return 0

    install(
        args.mode,
        config_home=args.config_home,
        python=Path(sys.executable),
        app=app,
        speech_config=speech_config,
        remove=args.remove,
        dry_run=args.dry_run,
    )
    action = "would remove" if args.remove and args.dry_run else (
        "removed" if args.remove else "installed"
    )
    print(f"{action}: {target}")
    if args.mode == "systemd" and not args.remove:
        print("Enable with: systemctl --user enable --now local-assistant.service")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
