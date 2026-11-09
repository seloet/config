"""Phase 9 measurement harness — clean A/B for the post-ASR corrector.

The normal `speech.personalize` run rewrites logs/command_failures.jsonl with
the *current* pipeline output, which would let the corrector train on its own
prior corrections (a feedback loop that shrinks the pair set). This script does
a clean, reproducible two-step measurement:

  STEP 1 (pristine baseline): run the pipeline with hotwords OFF and the
    corrector DISABLED (pure greedy_search, no error correction). Persist the
    raw failure log to logs/baseline_failures.jsonl — this is the fixed
    reference the corrector is trained on.

  STEP 2 (corrector): train the corrector from the pristine log, persist the
    learned pairs to data/asr_corrector_pairs.json, re-run the pipeline with
    the corrector ENABLED (hotwords still off, so decoding is unchanged
    greedy_search — isolating the corrector's effect), and print both
    accuracies side by side.

Usage:
    python tools/measure_phase9.py
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

from speech.model_config import load_config
from speech.asr_corrector import learn_pairs, write_pairs
from speech.personalize import run as personalize_run

REPO = Path(__file__).resolve().parent.parent
LOG = REPO / "logs"
PRISTINE = LOG / "baseline_failures.jsonl"
PAIRS = REPO / "data" / "asr_corrector_pairs.json"


def _config(no_hotwords: bool, corrector_enabled: bool) -> dict:
    cfg = load_config()
    if no_hotwords:
        cfg["asr"] = {**cfg["asr"], "hotwords_file": ""}
    cfg["corrector"] = {
        "enabled": corrector_enabled,
        "min_count": 2,
        "pairs_file": str(PAIRS),
    }
    return cfg


def _patch_config_in_personalize(cfg: dict) -> None:
    import speech.model_config as MC

    MC.load_config = lambda *a, **k: cfg  # type: ignore[assignment]


def step1_pristine() -> None:
    cfg = _config(no_hotwords=True, corrector_enabled=False)
    _patch_config_in_personalize(cfg)
    personalize_run(quiet=True)
    src = LOG / "command_failures.jsonl"
    PRISTINE.write_text(src.read_text())
    pairs = learn_pairs(PRISTINE, min_count=2)
    write_pairs(PAIRS, pairs)
    print(f"[step1] pristine failures -> {PRISTINE} ({len(src.read_text().splitlines())} lines)")
    print(f"[step1] learned {len(pairs)} confusion pairs -> {PAIRS}")


def step2_corrector() -> None:
    cfg = _config(no_hotwords=True, corrector_enabled=True)
    _patch_config_in_personalize(cfg)
    rep = personalize_run(quiet=True)
    print(f"[step2] WITH corrector: tool={rep['tool_selection_accuracy']:.3f} "
          f"exact={rep['exact_args_accuracy']:.3f} (total={rep['total']})")


if __name__ == "__main__":
    step1_pristine()
    # re-load real config so step2 reflects the persisted pairs file path logic
    step2_corrector()
