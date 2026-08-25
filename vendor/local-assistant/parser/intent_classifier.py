"""Phase 10 — learned intent classifier (CPU-only fallback).

A tiny kNN intent model trained on the command corpus, used as a *last-resort*
fallback behind the rule parser (regex -> grammar) for utterances the rules
cannot match. It is deliberately small and dependency-free (numpy only, no
torch/sklearn): the plan calls for "a small intent model only as a fallback
behind the rule parser for frequently failing natural-language requests".

Design
------
* Features: character 3-gram TF vectors (hashing into a fixed-width bag),
  compared by cosine similarity. Character n-grams survive the acoustic
  word-errors that defeat exact-token matching (the same noise that Phase 9
  could not fix).
* Prediction: 3-NN with cosine; the score is the mean cosine of the k nearest
  neighbours that agree on the predicted tool, clamped to [0, 1]. A fixed
  threshold gates adoption so the fallback never fires on out-of-domain noise.
* The classifier only *ranks tools*; argument extraction for the predicted tool
  is delegated to the rule layer's own keyword logic (see ``extract_args``), so
  tool semantics stay in one place.

It is trained from tests/fixtures/samples/*.json (idempotent, ~448 clips) and
serialised to data/intent_model.json. ``load_model`` auto-trains if absent.
"""
from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
CORPUS_DIR = REPO / "tests" / "fixtures" / "samples"
CORPUS_CACHE = REPO / "data" / "intent_corpus.json"  # noisy ASR transcripts (Phase 10 train)
MODEL_PATH = REPO / "data" / "intent_model.json"

NGRAM_N = 3
VECTOR_DIM = 1024
K = 3
ADOPT_THRESHOLD = 0.45  # cosine score below this -> stay unmatched

# Canonical tools present in the corpus / registry.
TOOLS = [
    "open_application", "set_volume", "get_time", "create_note",
    "search_files", "play_pause_media", "lock_screen",
]

# Keyword sets used to extract arguments for a predicted tool. Order matters
# only for stripping the utterance down to the residual argument text.
_CMD_KEYWORDS = {
    "open_application": [r"\b(?:open|opened|launch|launched|start|run|show)\b"],
    "set_volume": [r"\b(?:set|turn|the|sound|volume|to|at|up|down|percent|per cent)\b"],
    "get_time": [r"\b(?:what|is|the|current|time|times)\b"],
    "create_note": [r"\b(?:create|make|add|take|note|that|i|should|a|saying|say)\b"],
    "search_files": [r"\b(?:search|find|look|for|files|file)\b"],
    "play_pause_media": [r"\b(?:media|music|playback|play|pause|resume|toggle|next|previous|stop|skip|track|song|the|last)\b"],
    "lock_screen": [r"\b(?:lock|secure|the|screen|session|computer)\b"],
}


def _char_ngrams(text: str, n: int = NGRAM_N) -> list[str]:
    text = " " + text.lower().strip() + " "
    return [text[i:i + n] for i in range(len(text) - n + 1)]


def _hash(token: str, dim: int = VECTOR_DIM) -> int:
    h = 2166136261
    for ch in token.encode("utf-8", "ignore"):
        h ^= ch
        h = (h * 16777619) & 0xFFFFFFFF
    return h % dim


def _vectorize(text: str) -> np.ndarray:
    vec = np.zeros(VECTOR_DIM, dtype=np.float32)
    for g in _char_ngrams(text):
        vec[_hash(g)] += 1.0
    n = np.linalg.norm(vec)
    if n > 0:
        vec /= n
    return vec


def _strip_keywords(text: str, tool: str) -> str:
    residual = text.lower()
    for pat in _CMD_KEYWORDS.get(tool, []):
        residual = re.sub(pat, " ", residual, flags=re.IGNORECASE)
    # also strip leading filler verbs already handled; collapse whitespace
    residual = re.sub(r"\s+", " ", residual).strip()
    # drop a lone trailing 'c' from a clipped "per cent"
    residual = re.sub(r"\bc\b\s*$", "", residual).strip()
    return residual


def extract_args(tool: str, text: str) -> dict:
    """Extract arguments for ``tool`` from ``text`` using the rule layer's
    keyword logic. Returns {} when there is nothing to extract."""
    from .numbers import words_to_number
    from .patterns import _canonical_app
    residual = _strip_keywords(text, tool)
    if tool == "open_application":
        canon = _canonical_app(residual)
        return {"application": canon} if canon else {}
    if tool == "set_volume":
        val = words_to_number(residual) if not residual.isdigit() else int(residual)
        from tools.schemas import SetVolumeArgs
        try:
            SetVolumeArgs(percent=int(val))
        except Exception:
            return {}
        return {"percent": int(val)}
    if tool in ("get_time", "lock_screen"):
        return {}
    if tool == "create_note":
        return {"text": residual} if residual else {}
    if tool == "search_files":
        return {"query": residual} if residual else {}
    if tool == "play_pause_media":
        action = re.search(r"\b(play|pause|resume|toggle|next|previous|stop|skip|last)\b",
                           text.lower())
        a = action.group(1) if action else "play"
        if a in {"skip", "next"}:
            a = "next"
        elif a in {"previous", "last"}:
            a = "previous"
        elif a == "resume":
            a = "play"
        return {"action": a}
    return {}


class IntentClassifier:
    def __init__(self, phrases: list[str], tools: list[str], dim: int = VECTOR_DIM):
        if dim != VECTOR_DIM:
            raise ValueError(f"intent vector dimension must be {VECTOR_DIM}")
        if len(phrases) != len(tools):
            raise ValueError("phrases and tools must have the same row count")
        unknown = sorted(set(tools) - set(TOOLS))
        if unknown:
            raise ValueError(f"unsupported intent tools: {unknown}")
        self.phrases = list(phrases)
        self.tools = list(dict.fromkeys(tools))
        self.tool_index = {t: i for i, t in enumerate(self.tools)}
        self.matrix = np.zeros((len(phrases), dim), dtype=np.float32)
        self.labels = np.array(
            [self.tool_index[t] for t in tools], dtype=np.int64
        )
        for i, ph in enumerate(phrases):
            self.matrix[i] = _vectorize(ph)

    def predict(self, text: str) -> tuple[str | None, float]:
        if self.matrix.shape[0] == 0:
            return None, 0.0
        q = _vectorize(text)
        sims = self.matrix @ q  # cosine (both unit-normalised)
        k = min(K, len(self.labels))
        top = np.argpartition(-sims, k - 1)[:k]
        top = top[np.argsort(-sims[top])]
        pred_idx = int(self.labels[top[0]])
        # score = mean cosine over the k-NN that share the predicted tool
        agree = [i for i in top if self.labels[i] == pred_idx]
        score = float(np.mean(sims[agree]))
        return self.tools[pred_idx], score

    def to_dict(self) -> dict:
        return {
            "tools": self.tools,
            "dim": VECTOR_DIM,
            "phrases": self.phrases,
            "matrix": self.matrix.tolist(),
            "labels": self.labels.tolist(),
        }


def _corpus_pairs() -> tuple[list[str], list[str]]:
    """Source phrases for training.

    Prefers the cached *noisy* ASR transcripts (data/intent_corpus.json) when
    present — training on the real acoustic domain is what makes the fallback
    robust to sherpa-onnx word-errors. Falls back to the clean canonical
    phrases from the sample sidecars (used to bootstrap before the first
    train_intent run and in tests without models).
    """
    if CORPUS_CACHE.exists():
        try:
            cached = json.loads(CORPUS_CACHE.read_text())
            ph = [c["text"] for c in cached if c.get("tool") in TOOLS]
            tl = [c["tool"] for c in cached if c.get("tool") in TOOLS]
            if ph:
                return ph, tl
        except Exception:
            pass
    phrases, tools = [], []
    if not CORPUS_DIR.exists():
        return phrases, tools
    for jf in CORPUS_DIR.glob("*.json"):
        try:
            meta = json.loads(jf.read_text())
        except Exception:
            continue
        if meta.get("tool") in TOOLS:
            phrases.append(meta["phrase"])
            tools.append(meta["tool"])
    return phrases, tools


def train() -> IntentClassifier:
    phrases, tools = _corpus_pairs()
    if not phrases:
        raise RuntimeError("no corpus clips found under tests/fixtures/samples")
    return IntentClassifier(phrases, tools)


def save_model(classifier: IntentClassifier, path: Path = MODEL_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(classifier.to_dict()))


def load_model(path: Path = MODEL_PATH) -> IntentClassifier:
    if not path.exists():
        clf = train()
        save_model(clf, path)
        return clf
    payload = json.loads(path.read_text())
    tools = payload.get("tools")
    phrases = payload.get("phrases")
    raw_matrix = payload.get("matrix")
    raw_labels = payload.get("labels")
    declared_dim = payload.get("dim")
    if (
        not isinstance(tools, list)
        or not tools
        or not all(isinstance(tool, str) for tool in tools)
        or len(set(tools)) != len(tools)
    ):
        raise ValueError("intent model tools must be a non-empty unique list")
    if set(tools) - set(TOOLS):
        raise ValueError("intent model contains an unsupported tool")
    if (
        not isinstance(phrases, list)
        or not phrases
        or not all(isinstance(phrase, str) and phrase for phrase in phrases)
    ):
        raise ValueError("intent model phrases must be a non-empty string list")
    if type(declared_dim) is not int or declared_dim != VECTOR_DIM:
        raise ValueError(f"intent model dimension must be {VECTOR_DIM}")
    if not isinstance(raw_matrix, list) or not isinstance(raw_labels, list):
        raise ValueError("intent model matrix/labels must be lists")
    if not all(type(label) is int for label in raw_labels):
        raise ValueError("intent model labels must be integers")
    matrix = np.asarray(raw_matrix, dtype=np.float32)
    labels = np.asarray(raw_labels, dtype=np.int64)
    if matrix.ndim != 2 or labels.ndim != 1:
        raise ValueError("intent model matrix/labels have invalid dimensions")
    if matrix.shape[1] != VECTOR_DIM:
        raise ValueError(f"intent model matrix must have {VECTOR_DIM} columns")
    if not (matrix.shape[0] == labels.shape[0] == len(phrases)):
        raise ValueError("intent model matrix, labels, and phrases disagree")
    if not np.isfinite(matrix).all():
        raise ValueError("intent model matrix must contain only finite values")
    norms = np.linalg.norm(matrix, axis=1)
    if not np.allclose(norms, 1.0, rtol=1e-4, atol=1e-5):
        raise ValueError("intent model matrix rows must be unit-normalized")
    if labels.size and (int(labels.min()) < 0 or int(labels.max()) >= len(tools)):
        raise ValueError("intent model label is outside the tool table")
    clf = IntentClassifier.__new__(IntentClassifier)
    clf.phrases = list(phrases)
    clf.tools = list(tools)
    clf.tool_index = {t: i for i, t in enumerate(clf.tools)}
    clf.matrix = matrix
    clf.labels = labels
    return clf


# Module-level singleton (trained/lazy). Tests may monkeypatch it.
_model: IntentClassifier | None = None


def predict_intent(text: str, threshold: float = ADOPT_THRESHOLD
                   ) -> tuple[str | None, float, dict]:
    """Predict (tool, score, arguments) for ``text`` via the learned fallback.

    Returns (None, 0.0, {}) when the model is unavailable or the score is below
    ``threshold`` — the caller then keeps the utterance unmatched.
    """
    global _model
    if _model is None:
        try:
            _model = load_model()
        except Exception:
            return None, 0.0, {}
    if _model.matrix.shape[0] == 0:
        return None, 0.0, {}
    tool, score = _model.predict(text)
    if tool is None or not math.isfinite(score) or score < threshold:
        return None, 0.0, {}
    return tool, score, extract_args(tool, text)
