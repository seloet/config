"""Speaker-disjoint evaluation for the learned intent fallback.

The checked-in noisy ASR corpus contains eight Kokoro voices. Each fold holds
one voice out, trains on the other voices, and reports candidate tool/argument
accuracy at the production adoption threshold. This is synthetic regression
evidence, not representative microphone or live-execution accuracy.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from parser.intent_classifier import (
    ADOPT_THRESHOLD,
    CORPUS_CACHE,
    CORPUS_DIR,
    TOOLS,
    IntentClassifier,
    extract_args,
)


def load_rows(
    cache_path: Path = CORPUS_CACHE,
    corpus_dir: Path = CORPUS_DIR,
) -> list[dict[str, Any]]:
    """Load command rows and recover voice/source metadata from sidecars."""
    rows = json.loads(cache_path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise ValueError("intent corpus must be a list")

    sidecars: list[dict[str, Any]] = []
    for path in sorted(corpus_dir.glob("*.json")):
        meta = json.loads(path.read_text(encoding="utf-8"))
        sidecars.append({**meta, "source": path.with_suffix(".wav").name})

    if rows and not all(row.get("voice") and row.get("source") for row in rows):
        command_sidecars = [row for row in sidecars if row.get("tool") in TOOLS]
        candidates = [sidecars, command_sidecars]
        matching = next((items for items in candidates if len(items) == len(rows)), None)
        if matching is None:
            raise ValueError("cannot align cached transcripts with corpus sidecars")
        enriched: list[dict[str, Any]] = []
        for row, meta in zip(rows, matching, strict=True):
            if row.get("tool") != meta.get("tool"):
                raise ValueError("cached transcript order disagrees with sidecars")
            enriched.append({
                **row,
                "voice": meta.get("voice"),
                "source": meta["source"],
            })
        rows = enriched

    command_rows = [row for row in rows if row.get("tool") in TOOLS]
    for row in command_rows:
        if not row.get("voice"):
            raise ValueError("every evaluation row needs a voice label")
    return command_rows


def evaluate(rows: list[dict[str, Any]], threshold: float = ADOPT_THRESHOLD) -> dict[str, Any]:
    """Run leave-one-voice-out evaluation and return a JSON-safe report."""
    voices = sorted({str(row["voice"]) for row in rows})
    if len(voices) < 2:
        raise ValueError("speaker-disjoint evaluation needs at least two voices")

    folds: list[dict[str, Any]] = []
    total = adopted = tool_correct = exact = 0
    for voice in voices:
        train_rows = [row for row in rows if row["voice"] != voice]
        test_rows = [row for row in rows if row["voice"] == voice]
        classifier = IntentClassifier(
            [str(row["text"]) for row in train_rows],
            [str(row["tool"]) for row in train_rows],
        )

        fold_adopted = fold_tool = fold_exact = 0
        for row in test_rows:
            predicted, score = classifier.predict(str(row["text"]))
            if predicted is None or score < threshold:
                continue
            fold_adopted += 1
            if predicted != row["tool"]:
                continue
            fold_tool += 1
            arguments = extract_args(predicted, str(row["text"]))
            expected = row.get("expected", {})
            if all(arguments.get(key) == value for key, value in expected.items()):
                fold_exact += 1

        count = len(test_rows)
        folds.append({
            "voice": voice,
            "rows": count,
            "adopted": fold_adopted,
            "tool_correct": fold_tool,
            "exact": fold_exact,
        })
        total += count
        adopted += fold_adopted
        tool_correct += fold_tool
        exact += fold_exact

    return {
        "evidence": "synthetic Kokoro speaker-disjoint candidate evaluation",
        "threshold": threshold,
        "voices": voices,
        "rows": total,
        "adopted": adopted,
        "tool_correct": tool_correct,
        "exact": exact,
        "coverage": adopted / total if total else 0.0,
        "tool_accuracy": tool_correct / total if total else 0.0,
        "exact_accuracy": exact / total if total else 0.0,
        "folds": folds,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=CORPUS_CACHE)
    parser.add_argument("--corpus-dir", type=Path, default=CORPUS_DIR)
    parser.add_argument("--threshold", type=float, default=ADOPT_THRESHOLD)
    args = parser.parse_args(argv)

    report = evaluate(load_rows(args.cache, args.corpus_dir), args.threshold)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
