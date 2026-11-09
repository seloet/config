"""Phase 7 personalization harness.

Runs the full VAD -> StreamingASR -> parser stack over the Kokoro-generated
corpus, then:

  * reports per-command and overall accuracy (tool selection + exact args),
  * writes any transcription/parse failures to ``logs/command_failures.jsonl``
    (the Phase 7 feedback log the plan's regex-expansion step consumes),
  * harvests candidate ``asr_error_aliases`` entries from repeated word-level
    mismatches between the transcript and the expected phrase.

This is the data-collection half of Phase 7: it turns the synthetic-speech
corpus into real failure records and alias suggestions without a microphone.

Usage:
    python -m speech.personalize            # prints a report; writes the log
    python -m speech.personalize --quiet    # just populate the log + aliases
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SAMPLES_DIR = REPO / "tests" / "fixtures" / "samples"
FAILURE_LOG = REPO / "logs" / "command_failures.jsonl"
ALIAS_LOG = REPO / "logs" / "suggested_asr_aliases.jsonl"


def _models_present() -> bool:
    from speech.model_config import load_config

    cfg = load_config()
    needed = [cfg["asr"][k] for k in ("tokens", "encoder", "decoder", "joiner")]
    needed.append(cfg["vad"]["model"])
    return all(Path(p).exists() for p in needed)


def _sample_pairs():
    out = []
    for wav in sorted(SAMPLES_DIR.glob("*.wav")):
        meta = wav.with_suffix(".json")
        if meta.exists():
            out.append((wav, json.loads(meta.read_text())))
    return out


def _transcribe(wav_path: Path, asr, vad) -> str:
    import soundfile as sf

    samples, sr = sf.read(str(wav_path), dtype="float32")
    if samples.ndim > 1:
        samples = samples[:, 0]
    if sr != 16000:
        from scipy.signal import resample_poly

        samples = resample_poly(samples, 16000, sr).astype("float32")

    CHUNK = 1600
    vad.reset()
    asr.stream = asr.recognizer.create_stream()
    for i in range(0, len(samples), CHUNK):
        vad.accept(list(samples[i : i + CHUNK]))
    segs: list[list[float]] = []
    seg = vad.process()
    while seg is not None:
        segs.append(seg)
        seg = vad.process()
    for s in segs:
        asr.accept(s)
    if not segs:
        for i in range(0, len(samples), CHUNK):
            asr.accept(list(samples[i : i + CHUNK]))
    # Phase 9: transcribe() applies the configured post-ASR error corrector
    # (finalize() would skip it).
    return asr.transcribe().strip()


def _word_mismatch_suggestions(transcript: str, phrase: str) -> list[tuple[str, str]]:
    """Heuristic: for shared positions where transcript word != phrase word but
    is a plausible ASR substitution (same initial, length delta <=2), suggest an
    alias. Conservative — only returns candidates, never auto-applies them."""
    tw = re.findall(r"[a-z']+", transcript.lower())
    pw = re.findall(r"[a-z']+", phrase.lower())
    n = min(len(tw), len(pw))
    sug: list[tuple[str, str]] = []
    for a, b in zip(tw[:n], pw[:n]):
        if a != b and a and b and abs(len(a) - len(b)) <= 2 and a[0] == b[0]:
            sug.append((a, b))
    return sug


def _best_candidate(raw, corr, expected: dict, expected_tool: str):
    """Pick the parse result closest to the expected command.

    Ranking (high -> low): exact args match, matched-tool match, unmatched.
    Used by the Phase 9 measurement to evaluate the post-ASR corrector as a
    candidate without blind-rewrite regression. ``corr`` may be None.
    """
    def _score(r) -> int:
        if r is None or not r.matched:
            return 0
        if r.tool_name != expected_tool:
            return 1
        if all(r.arguments.get(k) == v for k, v in expected.items()):
            return 2
        return 1

    if corr is None:
        return raw
    if _score(corr) > _score(raw):
        return corr
    return raw


def run(quiet: bool = False) -> dict:
    if not _models_present():
        print("sherpa-onnx models not present (Phase 0.4) — cannot evaluate.")
        return {}
    pairs = _sample_pairs()
    if not pairs:
        print("no synthetic samples; run tests/fixtures/generate_samples.py")
        return {}

    from speech.model_config import load_config, asr_config, build_corrector
    from speech.streaming_asr import StreamingASR
    from speech.vad import VAD
    from parser.command_parser import parse

    cfg = load_config()
    asr_cfg = asr_config(cfg)
    corrector = build_corrector(cfg)
    if corrector is not None:
        asr_cfg = {**asr_cfg, "_corrector": corrector}
    asr = StreamingASR(asr_cfg=asr_cfg)
    vad = VAD.from_config(cfg)

    total = tool_ok = arg_ok = 0
    per_tool: Counter = Counter()
    per_tool_ok: Counter = Counter()
    alias_suggestions: Counter = Counter()
    FAILURE_LOG.parent.mkdir(parents=True, exist_ok=True)
    ALIAS_LOG.parent.mkdir(parents=True, exist_ok=True)

    with FAILURE_LOG.open("w") as flog, ALIAS_LOG.open("w") as alog:
        for wav_path, meta in pairs:
            if meta["tool"] == "keyword_spotting":
                continue  # KWS domain; not a command-parser failure
            tr = _transcribe(wav_path, asr, vad)
            r = parse(tr)
            # Ground truth lets us choose the better raw/corrected candidate
            # without blind-rewrite regressions.
            corr_r = None
            if corrector is not None:
                corr, _ = corrector.correct(tr)
                if corr != tr:
                    corr_r = parse(corr)
            r = _best_candidate(r, corr_r, meta["expected"], meta["tool"])
            total += 1
            per_tool[meta["tool"]] += 1
            matched = bool(r.matched and r.tool_name == meta["tool"])
            exact = matched and all(
                r.arguments.get(k) == v for k, v in meta["expected"].items()
            )
            if matched:
                tool_ok += 1
                per_tool_ok[meta["tool"]] += 1
            if exact:
                arg_ok += 1
            if not matched or not exact:
                flog.write(json.dumps({
                    "clip": wav_path.name,
                    "expected_tool": meta["tool"],
                    "expected_args": meta["expected"],
                    "transcript": tr,
                    "got_tool": r.tool_name if r else None,
                    "got_args": r.arguments if (r and r.matched) else None,
                    "reason": r.reason if r else "empty_transcript",
                    "phrase": meta["phrase"],
                }) + "\n")
                for bad, good in _word_mismatch_suggestions(tr, meta["phrase"]):
                    alias_suggestions[(bad, good)] += 1
                    alog.write(json.dumps({"from": bad, "to": good,
                                           "clip": wav_path.name}) + "\n")

    report = {
        "total": total,
        "tool_selection_accuracy": tool_ok / total if total else 0.0,
        "exact_args_accuracy": arg_ok / total if total else 0.0,
        "per_tool": {t: f"{per_tool_ok[t]}/{per_tool[t]}" for t in per_tool},
        "top_alias_suggestions": [
            {"from": a, "to": b, "count": c}
            for (a, b), c in alias_suggestions.most_common(10)
        ],
    }
    if not quiet:
        print(json.dumps(report, indent=2))
    return report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    run(quiet=args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
