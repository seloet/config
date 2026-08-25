from __future__ import annotations
import json
from datetime import datetime
from pathlib import Path

LOG = Path(__file__).resolve().parent.parent / "logs" / "command_failures.jsonl"

def log_failure(text: str, norm: str, reason: str, model: str = "n/a",
                candidates: list | None = None) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    rec = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "transcript": text, "normalized_text": norm,
        "matched": False, "reason": reason,
        "candidates": candidates, "asr_model": model,
    }
    with LOG.open("a") as f:
        f.write(json.dumps(rec) + "\n")
