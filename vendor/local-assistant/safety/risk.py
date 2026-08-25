"""Risk tier classification for tools (plan: Safety & Validation Layers).

Risk tiers (this target, per the plan):
  * low  (auto)            : open_application, set_volume, get_time,
                             search_files, play_pause_media
  * medium (confirm if ambiguous): close_application, open_file,
                             create_note, lock_screen
  * high (explicit confirm): anything destructive — NOT in the initial tool
                             set; any unknown tool is treated as high.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

LOW = "low"
MEDIUM = "medium"
HIGH = "high"

DEFAULT_TIERS: dict[str, str] = {
    "open_application": LOW,
    "set_volume": LOW,
    "get_time": LOW,
    "search_files": LOW,
    "play_pause_media": LOW,
    "close_application": MEDIUM,
    "open_file": MEDIUM,
    "create_note": MEDIUM,
    "lock_screen": MEDIUM,
}

_PERMISSIONS_PATH = Path(__file__).resolve().parent.parent / "config" / "permissions.yaml"


def load_tiers(path: str | Path | None = None) -> dict[str, str]:
    """Load risk tiers from config/permissions.yaml, falling back to defaults.

    The file is optional; if absent the plan defaults are used.
    """
    p = Path(path) if path is not None else _PERMISSIONS_PATH
    if not p.exists():
        return dict(DEFAULT_TIERS)
    with open(p, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh) or {}
    tiers = dict(DEFAULT_TIERS)
    tiers.update(cfg.get("risk_tiers", {}) or {})
    return tiers


def tier_of(tool_name: str, tiers: dict[str, str] | None = None) -> str | None:
    """Return the risk tier for a tool, or None if it is not known.

    None (unknown tool) is treated as HIGH by the policy layer — fail closed.
    """
    if tiers is None:
        tiers = DEFAULT_TIERS
    return tiers.get(tool_name)
