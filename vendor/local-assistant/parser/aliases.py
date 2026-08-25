from __future__ import annotations
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent / "data"

def _load(name: str) -> dict:
    p = BASE / name
    return json.loads(p.read_text()) if p.exists() else {}

_ASR = _load("asr_error_aliases.json")

def apply_asr_aliases(text: str) -> tuple[str, int]:
    n = 0
    for bad, good in _ASR.items():
        if bad in text:
            text = text.replace(bad, good); n += 1
    return text, n
