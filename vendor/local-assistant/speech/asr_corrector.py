"""Phase 9 — post-ASR domain error corrector (fine-tune surrogate).

Why this exists
---------------
The plan's Phase 9 calls for reducing the residual *acoustic* word-error of the
ASR model (the ``by``->``buy``, ``viscode``->``vscode``, ``stret``->``stretch``
class of errors the Phase 8 grammar cannot fix) via fine-tuning (icefall).
That is **not feasible on this box**: there is no CUDA GPU and the corpus is
448 synthetic clips. sherpa-onnx *hotword biasing* was prototyped first but is
also a dead end here — the streaming zipformer uses a 500-token BPE
SentencePiece vocab with **no whole-word tokens** (not even ``open`` or
``volume``), so sherpa-onnx rejects 100% of hotwords
(``InitHotwords ... Failed to encode some hotwords, skip them``).

This corrector is the feasible CPU-only surrogate: a lightweight, learned
confusion-pair model applied to the *raw transcript* before parsing. It is
trained (offline, trivially) from ``logs/command_failures.jsonl`` by aligning
each failed transcript to its expected phrase word-by-word and recording the
substitutions the ASR made. At inference it applies only the high-confidence
pairs (observed >= ``min_count`` times) as whole-word substitutions, which is
conservative and cannot invent tool names.

This is the same idea as ``data/asr_error_aliases.json`` but *data-driven* and
scoped to the measured confusion distribution rather than hand-curated.
"""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FAILURE_LOG = REPO / "logs" / "command_failures.jsonl"

# Minimum number of observed (wrong -> right) substitutions before a pair is
# trusted. Keeps the corrector from fitting single-sample noise.
DEFAULT_MIN_COUNT = 2


def _words(text: str) -> list[str]:
    return re.findall(r"[a-z']+", text.lower())


def learn_pairs(failure_log: Path = FAILURE_LOG, min_count: int = DEFAULT_MIN_COUNT) -> dict[str, str]:
    """Learn (wrong_word -> right_word) substitutions from the failure log.

    For every failed clip we align the transcript to its expected *phrase*
    (the canonical spoken form) by position and record words the ASR swapped.
    Multi-word collapses (e.g. ``currentine`` -> ``current time``) are skipped —
    only 1:1 single-word substitutions are learned, which keeps application
    safe and reversible.
    """
    pairs: Counter = Counter()
    if not failure_log.exists():
        return {}
    for line in failure_log.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        tr = _words(rec.get("transcript", ""))
        phrase = _words(rec.get("phrase", ""))
        # For note commands the expected body lives in expected_args.text; the
        # phrase already carries the canonical wording, so aligning to phrase
        # is sufficient and uniform across tools.
        n = min(len(tr), len(phrase))
        for a, b in zip(tr[:n], phrase[:n]):
            if a != b and a.isalpha() and b.isalpha() and a != b:
                pairs[(a, b)] += 1
    # Safety filters (keep only plausible, low-risk substitutions):
    #  * drop single-character wrong words (they are almost always clipped-word
    #    artifacts like "p"->"pdf" / "s"->"code" and would over-correct).
    #  * drop extreme length skew (catches alignment artifacts like
    #    "upstretch"->"up"); a real truncation/typo stays within 2x length.
    learned = {}
    for (wrong, right), c in pairs.items():
        if len(wrong) <= 1:
            continue
        if len(wrong) > 2 * len(right) + 1 or len(right) > 2 * len(wrong) + 1:
            continue
        if c >= min_count:
            learned[wrong] = right
    return learned


def apply_pairs(text: str, pairs: dict[str, str]) -> tuple[str, int]:
    """Apply learned confusion pairs to a transcript as whole-word fixes.

    Returns (corrected_text, num_applied). Only whole-word matches are
    substituted (regex word boundaries), so e.g. ``by`` won't fire inside
    ``bypass``. Unknown/empty input is returned unchanged.
    """
    if not text or not pairs:
        return text, 0
    out = text
    applied = 0
    # Apply repeatedly-safe single pass: rebuild token by token so we never
    # re-correct an already-corrected word in the same call.
    tokens = re.findall(r"\S+|\s+", out)
    for i, tok in enumerate(tokens):
        bare = tok.strip().lower().strip("'")
        if bare in pairs and re.fullmatch(r"[a-z']+", tok.lower()):
            tokens[i] = pairs[bare]
            applied += 1
    corrected = "".join(tokens)
    return corrected, applied


# --------------------------------------------------------------------------- #
# Trainable artifact: persist learned pairs so the pipeline can load them
# without re-reading the (potentially large) failure log on every startup.
# --------------------------------------------------------------------------- #
def write_pairs(path: Path, pairs: dict[str, str]) -> None:
    path.write_text(json.dumps(pairs, indent=2, sort_keys=True) + "\n")


def load_pairs(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


class ASRCorrector:
    """Applies learned confusion pairs to an ASR transcript.

    Args:
        pairs: mapping of wrong_word -> right_word. Build with
            :func:`learn_pairs` / :func:`load_pairs`.
    """

    def __init__(self, pairs: dict[str, str] | None = None) -> None:
        self.pairs = pairs or {}

    def correct(self, text: str) -> tuple[str, int]:
        return apply_pairs(text, self.pairs)

    @classmethod
    def from_failures(cls, failure_log: Path = FAILURE_LOG,
                      min_count: int = DEFAULT_MIN_COUNT) -> "ASRCorrector":
        return cls(learn_pairs(failure_log, min_count=min_count))


if __name__ == "__main__":
    p = learn_pairs()
    print(json.dumps(p, indent=2, sort_keys=True))
    print(f"\nlearned {len(p)} confusion pairs (min_count={DEFAULT_MIN_COUNT})")
