"""Voice Activity Detection for the streaming pipeline.

Two layers:

  * ``EndpointDetector`` / ``UtteranceBuilder`` — pure, model-free state
    machines that turn a stream of per-chunk *is_speech* booleans into
    ``speech_start`` / ``speech_end`` events and collect utterance audio
    (including a pre-roll). Fully unit-testable with no models or mic.

  * ``VAD`` — a thin wrapper over ``sherpa_onnx.VoiceActivityDetector``.
    ``sherpa_onnx`` is imported lazily inside :meth:`VAD.__init__`, so this
    module imports cleanly under pytest without the native lib or model files.
    Constructing a ``VAD`` requires the real Silero model (Phase 0.4).

Plan semantics (Phase 4): after wake, wait <= 3 s for speech; on VAD
speech-start, stream to ASR; on VAD silence (600-1000 ms) finalize; cap a
command at 10-15 s. ``EndpointDetector`` enforces the silence/length cutoffs.
"""
from __future__ import annotations

from typing import Any

from audio.audio_buffer import RingBuffer


class EndpointDetector:
    """Model-free speech/endpoint state machine, counted in frames.

    Args:
        min_silence_frames: consecutive non-speech frames that close an utterance.
        min_speech_frames: debounce — a speech run shorter than this is ignored.
        max_utterance_frames: hard cap on utterance length (forces ``speech_end``).
    """

    def __init__(
        self,
        min_silence_frames: int,
        min_speech_frames: int | None = None,
        max_utterance_frames: int | None = None,
    ) -> None:
        self.min_silence_frames = min_silence_frames
        self.min_speech_frames = min_speech_frames
        self.max_utterance_frames = max_utterance_frames
        self._in_speech = False
        self._pending = 0
        self._speech = 0
        self._silence = 0

    def update(self, is_speech: bool) -> list[str]:
        """Feed one frame; return emitted events (subset of the two strings)."""
        events: list[str] = []
        if is_speech:
            self._silence = 0
            if not self._in_speech:
                self._pending += 1
                if self.min_speech_frames and self._pending < self.min_speech_frames:
                    return events  # still debouncing
                self._in_speech = True
                self._speech = self._pending
                events.append("speech_start")
            else:
                self._speech += 1
            if self.max_utterance_frames and self._speech >= self.max_utterance_frames:
                self._in_speech = False
                self._pending = 0
                events.append("speech_end")
        else:
            if self._in_speech:
                self._silence += 1
                if self._silence >= self.min_silence_frames:
                    self._in_speech = False
                    self._pending = 0
                    events.append("speech_end")
            else:
                self._pending = 0
        return events

    def reset(self) -> None:
        self._in_speech = False
        self._pending = 0
        self._speech = 0
        self._silence = 0


class UtteranceBuilder:
    """Collect utterance audio from a speech/non-speech stream with pre-roll.

    On ``speech_start`` it snapshots the pre-roll ring buffer (capturing onset),
    then accumulates subsequent frames until ``speech_end``, at which point it
    returns the full utterance (pre-roll + body).
    """

    def __init__(
        self,
        preroll_seconds: float = 0.3,
        sample_rate: int = 16000,
        min_silence_frames: int = 8,
        min_speech_frames: int = 2,
        max_utterance_frames: int = 1200,
    ) -> None:
        self._preroll = RingBuffer(preroll_seconds, sample_rate)
        self._ep = EndpointDetector(
            min_silence_frames=min_silence_frames,
            min_speech_frames=min_speech_frames,
            max_utterance_frames=max_utterance_frames,
        )
        self._current: list[float] = []
        self._in_speech = False

    def feed(self, is_speech: bool, samples: list[float]) -> list[float] | None:
        """Feed one chunk; return the completed utterance on endpoint, else None."""
        events = self._ep.update(is_speech)
        self._preroll.push(samples)
        result: list[float] | None = None
        if "speech_start" in events:
            # pre-roll already contains the onset frames (push() ran above), so
            # the snapshot captures them — no separate addition needed.
            self._in_speech = True
            self._current = list(self._preroll.get_recent())
        elif "speech_end" in events:
            self._current.extend(samples)
            result = self._current
            self._current = []
            self._in_speech = False
        elif self._in_speech:
            self._current.extend(samples)
        return result

    def reset(self) -> None:
        self._ep.reset()
        self._preroll.clear()
        self._current = []
        self._in_speech = False


class VAD:
    """Wrapper over ``sherpa_onnx.VoiceActivityDetector`` (lazy import)."""

    def __init__(
        self,
        vad_cfg: dict[str, Any],
        sample_rate: int = 16000,
        preroll_seconds: float = 0.3,
    ) -> None:
        import sherpa_onnx  # native lib + model required at construction time

        self._sr = sample_rate
        vc = sherpa_onnx.VadModelConfig()
        vc.silero_vad.model = vad_cfg["model"]
        vc.silero_vad.threshold = float(vad_cfg.get("threshold", 0.5))
        vc.silero_vad.min_silence_duration = float(
            vad_cfg.get("min_silence_duration", 0.5)
        )
        vc.silero_vad.min_speech_duration = float(
            vad_cfg.get("min_speech_duration", 0.25)
        )
        self._det = sherpa_onnx.VoiceActivityDetector(vc, buffer_size_in_seconds=10.0)
        self._sample_rate = sample_rate
        self._vad_cfg = vad_cfg
    @classmethod
    def from_config(cls, cfg: dict[str, Any], **kw: Any) -> "VAD":
        return cls(
            cfg["vad"],
            sample_rate=cfg["asr"].get("sample_rate", 16000),
            **kw,
        )

    def accept(self, samples: list[float]) -> None:
        """Push a chunk of float32 samples (16 kHz) into the detector."""
        self._det.accept_waveform(samples)

    def reset(self) -> None:
        """Drop all buffered audio and restart the detector.

        Used between independent utterances (e.g. per fixture sample) so
        speech segments from one clip never leak into the next.
        """
        import sherpa_onnx  # native lib + model required at construction time

        vc = sherpa_onnx.VadModelConfig()
        vc.silero_vad.model = self._vad_cfg["model"]
        vc.silero_vad.threshold = float(self._vad_cfg.get("threshold", 0.5))
        vc.silero_vad.min_silence_duration = float(
            self._vad_cfg.get("min_silence_duration", 0.5)
        )
        vc.silero_vad.min_speech_duration = float(
            self._vad_cfg.get("min_speech_duration", 0.25)
        )
        self._det = sherpa_onnx.VoiceActivityDetector(vc, buffer_size_in_seconds=10.0)


    def empty(self) -> bool:
        return self._det.empty()

    def is_speech_detected(self) -> bool:
        """Return whether the native detector is currently inside speech."""
        return bool(self._det.is_speech_detected())

    def pop_segment(self) -> list[float] | None:
        """Return the next detected speech segment (list of samples), or None."""
        if self._det.empty():
            return None
        seg = self._det.front  # property (sherpa-onnx 1.13.4)
        # ``front`` is a borrowed native reference, valid only until the next
        # detector operation. Copy before pop() invalidates it.
        samples = list(seg.samples)
        self._det.pop()
        return samples

    def process(self, *, flush: bool = False) -> list[float] | None:
        """Return the next completed native speech segment, if any.

        ``VoiceActivityDetector`` already performs speech-start/end tracking and
        only exposes completed segments through ``front``. Feeding those segments
        into a second endpoint state machine loses the native speech-end event and
        can therefore never complete an utterance.

        ``flush`` is reserved for finite clips or a hard capture deadline. The
        live loop must leave it false while audio is still arriving; flushing on
        every microphone chunk would split an utterance into tiny fragments.
        """
        if flush:
            self._det.flush()
        return self.pop_segment()
