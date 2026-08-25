"""Keyword spotting / wake-word detection for the streaming pipeline.

Two layers (mirroring ``speech/vad.py``):

  * ``WakeController`` — a pure, model-free state machine that owns the
    wake-word set, the post-activation cooldown, and the false-activation /
    miss counters. Fully unit-testable with no models or microphone.
  * ``KWS`` — a thin wrapper over ``sherpa_onnx.KeywordSpotter``.
    ``sherpa_onnx`` is imported lazily inside :meth:`KWS.__init__`, so this
    module imports cleanly under pytest without the native lib or model files.
    Constructing a ``KWS`` requires the real zipformer KWS model (Phase 0.4).

Plan semantics (Phase 5): run KWS continuously on the mic queue; on
``computer`` / ``hey computer`` -> activation sound -> switch to
command-capture mode with a cooldown (1500 ms). Track false-activation and
miss rate. Prevent self-hearing (plan §29): the orchestrator pauses KWS/ASR
during TTS / chime playback.
"""
from __future__ import annotations

import time
from typing import Any

from speech.model_config import load_config


# Normalized wake phrases the model is expected to emit (upper-cased by the
# recognizer). "COMPUTER" and "HEY COMPUTER" were added to keywords.txt; the
# BPE vocabulary can spell them from the existing tokens.
DEFAULT_WAKE_WORDS = ("COMPUTER", "HEY COMPUTER")


class WakeController:
    """Pure wake-word arbitration: cooldown + activation counters.

    Args:
        wake_words: normalized keywords that should trigger capture mode.
        cooldown_seconds: after an accepted wake, further detections are
            ignored for this long (plan: 1500 ms).
    """

    def __init__(
        self,
        wake_words: tuple[str, ...] = DEFAULT_WAKE_WORDS,
        cooldown_seconds: float = 1.5,
    ) -> None:
        self.wake_words = {w.upper() for w in wake_words}
        self.cooldown_seconds = cooldown_seconds
        self._last_wake: float = -1e9
        self.wakes = 0
        self.false_activations = 0

    def in_cooldown(self, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        return (now - self._last_wake) < self.cooldown_seconds

    def is_wake(self, keyword: str) -> bool:
        return keyword.strip().upper() in self.wake_words

    def notify(self, keyword: str | None, now: float | None = None) -> bool:
        """Record a detection. Returns True iff it is an *accepted* wake.

        A non-wake keyword is tallied as a false activation. An accepted wake
        (in the wake set and outside cooldown) resets the cooldown clock and
        increments ``wakes``.
        """
        if not keyword:
            return False
        now = time.monotonic() if now is None else now
        if self.is_wake(keyword):
            if self.in_cooldown(now):
                return False
            self._last_wake = now
            self.wakes += 1
            return True
        self.false_activations += 1
        return False


class KWS:
    """Wrapper over ``sherpa_onnx.KeywordSpotter`` (lazy import).

    The detection loop mirrors the library's reference usage::

        stream.accept_waveform(sr, chunk)
        while spotter.is_ready(stream):
            spotter.decode_stream(stream)
            r = spotter.get_result(stream)
            if r:
                spotter.reset_stream(stream)
                # keyword r detected

    Args:
        kws_cfg: the ``keyword_spotting`` sub-dict from the speech config.
        sample_rate: audio sample rate (must match the model's training rate).
        wake_words: normalized wake phrases that trigger capture mode.
        cooldown_seconds: suppression window after a wake (plan: 1500 ms).
        keywords_file: optional override of the keywords file path.
    """

    def __init__(
        self,
        kws_cfg: dict[str, Any],
        sample_rate: int = 16000,
        wake_words: tuple[str, ...] = DEFAULT_WAKE_WORDS,
        cooldown_seconds: float = 1.5,
        keywords_file: str | None = None,
    ) -> None:
        import sherpa_onnx  # native lib + model required at construction time

        self._sr = sample_rate
        # The speech.yaml KWS block stores the encoder under ``model`` (see
        # config/speech.yaml); support either ``encoder`` or ``model``.
        encoder_path = kws_cfg.get("encoder") or kws_cfg["model"]
        # sherpa-onnx's FeatureExtractorConfig wants int sampling_rate/feature_dim
        # (passing floats raises TypeError), so coerce here.
        sr_int = int(sample_rate)
        self._spotter = sherpa_onnx.KeywordSpotter(
            tokens=kws_cfg["tokens"],
            encoder=encoder_path,
            decoder=kws_cfg["decoder"],
            joiner=kws_cfg["joiner"],
            keywords_file=keywords_file or kws_cfg["keywords"],
            num_threads=int(kws_cfg.get("num_threads", 2)),
            sample_rate=sr_int,
            feature_dim=int(kws_cfg.get("feature_dim", 80)),
            keywords_threshold=float(kws_cfg.get("keywords_threshold", 0.25)),
        )
        self._stream = self._spotter.create_stream()
        self.controller = WakeController(wake_words, cooldown_seconds)
        self._sample_rate = sample_rate

    @classmethod
    def from_config(cls, cfg: dict[str, Any], **kw: Any) -> "KWS":
        sr = cfg["asr"].get("sample_rate", 16000)
        kws_cfg = cfg["keyword_spotting"]
        if "wake_words" not in kw and "wake_words" in kws_cfg:
            kw["wake_words"] = tuple(kws_cfg["wake_words"])
        return cls(kws_cfg, sample_rate=sr, **kw)

    def accept(self, samples: list[float]) -> None:
        """Push a chunk of float32 samples (16 kHz) into the spotter."""
        self._stream.accept_waveform(self._sample_rate, samples)

    def process(self) -> str | None:
        """Run the decode loop; return a detected wake word or None.

        On a detected keyword the underlying stream is reset so the spotter
        can re-arm for the next utterance. Detections that fall inside the
        cooldown window (or are not wake words) are internally tallied by the
        controller and never returned here.
        """
        if not self._spotter.is_ready(self._stream):
            return None
        while self._spotter.is_ready(self._stream):
            self._spotter.decode_stream(self._stream)
            result = self._spotter.get_result(self._stream)
            if result:
                self._spotter.reset_stream(self._stream)
                if self.controller.notify(result):
                    return result.strip().upper()
        return None

    def reset(self) -> None:
        """Reset the underlying stream (e.g. after capture mode ends)."""
        self._spotter.reset_stream(self._stream)


def build_kws(config_path: str | None = None, **kw: Any) -> KWS:
    """Convenience: load ``config/speech.yaml`` and construct a ``KWS``."""
    cfg = load_config(config_path)
    return KWS.from_config(cfg, **kw)
