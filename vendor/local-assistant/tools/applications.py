from __future__ import annotations
import json
from functools import lru_cache
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "application_aliases.json"


@lru_cache(maxsize=1)
def _load() -> dict:
    return json.loads(DATA.read_text())


@lru_cache(maxsize=1)
def _alias_index() -> dict[str, str]:
    """Map canonical names and aliases to a canonical application name."""
    return {
        name.strip().lower(): canonical
        for canonical, entry in _load().items()
        for name in (canonical, *entry.get("aliases", []))
    }


def canonicalize(application: str) -> str | None:
    """Return the registry name for an application name or alias."""
    return _alias_index().get(application.strip().lower())


def resolve(application: str, os_name: str = "linux") -> list[str] | None:
    reg = _load()
    canonical = canonicalize(application)
    if canonical is None:
        return None
    entry = reg[canonical]
    return entry.get(os_name) or entry.get("linux")
