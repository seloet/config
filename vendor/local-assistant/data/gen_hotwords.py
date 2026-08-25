"""Phase 9 — ASR domain hotwords.

sherpa-onnx supports inference-time *hotword biasing* (a.k.a. contextual
boosting): a newline-delimited list of phrase strings passed to
``OnlineRecognizer.from_transducer(hotwords_file=..., hotwords_score=...)``.
Each phrase is boosted during decoding, which corrects command-domain
vocabulary the base int8 model mis-transcribes (e.g. ``vscode`` -> ``viscode``,
``ghostty`` -> ``ghost``, ``buy`` -> ``by``).

This is a feasible, CPU-only stand-in for the plan's literal "fine-tune via
icefall" step: there is no CUDA GPU on this box and the corpus is far too small
(448 synthetic clips) for transducer retraining. Hotword biasing attacks exactly
the residual *acoustic* word-error that Phase 8's grammar layer could not, with
zero training and no model export.

Generation is deterministic and derives the hotword set from:
  * every canonical app id + spoken alias in ``data/application_aliases.json``
    (so the model is biased toward the words users actually say),
  * a curated command-domain vocabulary (note-body/command words that the
    corpus exercises and the base model gets wrong).

The file is plain text, one phrase per line. Comments (``#``) and blank lines
are ignored by sherpa-onnx. Edit this list (or the generator) to add terms.
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP_ALIASES = REPO / "data" / "application_aliases.json"
HOTWORDS = REPO / "data" / "hotwords.txt"

# Command-domain words the corpus uses and the base model mis-transcribes.
# Curated from logs/command_failures.jsonl (e.g. "buy" -> "by").
COMMAND_VOCAB = [
    "buy", "milk", "stretch", "stand", "resume", "pause", "volume",
    "open", "close", "lock", "screen", "search", "files", "note", "time",
    "music", "media", "play", "next", "previous", "song", "track",
]


def _app_words() -> list[str]:
    reg = json.loads(APP_ALIASES.read_text())
    words: set[str] = set()
    for canon, entry in reg.items():
        words.add(canon)
        words.update(entry.get("aliases", []))
        # also keep the OS command token (e.g. "code", "ghostty", "firefox")
        for cmd in entry.get("linux", []):
            words.add(cmd)
    return sorted(words)


def build_hotwords() -> list[str]:
    words = _app_words() + COMMAND_VOCAB
    # de-dup, lowercase, drop empties
    seen: set[str] = set()
    out: list[str] = []
    for w in words:
        w = w.strip().lower()
        if w and w not in seen:
            seen.add(w)
            out.append(w)
    return out


def write_hotwords(path: Path = HOTWORDS) -> int:
    lines = build_hotwords()
    body = "\n".join(lines) + "\n"
    path.write_text(body)
    return len(lines)


if __name__ == "__main__":
    n = write_hotwords()
    print(f"wrote {n} hotwords to {HOTWORDS}")
