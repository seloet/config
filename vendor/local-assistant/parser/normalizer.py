from __future__ import annotations
import re

from .aliases import apply_asr_aliases

FILLER = re.compile(
    r"\b(please|could you|would you|can you|can i|would you mind|for me|"
    r"kindly)\b",
    re.IGNORECASE,
)


def normalize(text: str) -> str:
    t = text.lower().strip()
    # Apply conservative ASR-error corrections globally (e.g. "said"->"set",
    # "launch's"->"launch") before filler stripping and parsing. These come
    # from observed real-speech transcripts, never speculative homophone maps.
    t, _ = apply_asr_aliases(t)
    t = FILLER.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t
