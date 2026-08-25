"""Phase 10 training harness — build the learned intent fallback model.

Runs the real ASR over the 416 corpus clips, caches the *noisy* transcripts
paired with their expected tools to data/intent_corpus.json, then trains and
serialises the kNN classifier to data/intent_model.json.

Training on the actual acoustic domain (not the clean canonical phrases) is
what makes the fallback robust to the sherpa-onnx word-errors that defeat the
rule layer — the same noise Phase 9 could not fix. Idempotent: re-running
re-uses the cached transcripts.
"""
from __future__ import annotations

import json
from pathlib import Path

from speech.model_config import asr_config, load_config
from speech.streaming_asr import StreamingASR
from parser.intent_classifier import CORPUS_DIR, TOOLS, IntentClassifier, save_model

REPO = Path(__file__).resolve().parent.parent
CORPUS_CACHE = REPO / "data" / "intent_corpus.json"
MODEL_PATH = REPO / "data" / "intent_model.json"
CHUNK = 1600


def _asr_transcript(wav: Path, asr: StreamingASR) -> str:
    import soundfile as sf

    samples, _ = sf.read(str(wav), dtype="float32")
    if samples.ndim > 1:
        samples = samples[:, 0]
    asr.stream = asr.recognizer.create_stream()
    for i in range(0, len(samples), CHUNK):
        asr.accept(list(samples[i:i + CHUNK]))
    return asr.transcribe()


def build_noisy_corpus(asr: StreamingASR) -> list[dict]:
    pairs = []
    for jf in sorted(CORPUS_DIR.glob("*.json")):
        try:
            meta = json.loads(jf.read_text())
        except Exception:
            continue
        wav = jf.with_suffix(".wav")
        if not wav.exists():
            continue
        tr = _asr_transcript(wav, asr)
        if not tr:
            continue
        if meta.get("tool") not in TOOLS:
            continue
        pairs.append({
            "text": tr,
            "tool": meta["tool"],
            "expected": meta.get("expected", {}),
            "voice": meta.get("voice"),
            "source": wav.name,
        })
    return pairs


def main() -> None:
    if CORPUS_CACHE.exists():
        pairs = json.loads(CORPUS_CACHE.read_text())
        print(f"[train_intent] reusing cached noisy corpus ({len(pairs)} clips)")
    else:
        cfg = load_config()
        # Build ASR WITHOUT the Phase 9 corrector so cached transcripts are raw.
        asr_cfg = {**asr_config(cfg), "hotwords_file": ""}
        asr = StreamingASR(asr_cfg=asr_cfg)
        pairs = build_noisy_corpus(asr)
        CORPUS_CACHE.write_text(json.dumps(pairs, indent=1))
        print(f"[train_intent] generated noisy corpus ({len(pairs)} clips) -> {CORPUS_CACHE}")

    pairs = [p for p in pairs if p.get("tool") in TOOLS]

    phrases = [p["text"] for p in pairs]
    tools = [p["tool"] for p in pairs]
    clf = IntentClassifier(phrases, tools)
    save_model(clf, MODEL_PATH)
    print(f"[train_intent] trained kNN ({clf.matrix.shape[0]} clips) -> {MODEL_PATH}")


if __name__ == "__main__":
    main()
