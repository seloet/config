"""Streaming ASR wrapper around sherpa-onnx OnlineRecognizer.

NOTE: ``sherpa_onnx`` is imported lazily inside :meth:`StreamingASR.__init__`
so this module can be imported (e.g. under pytest) without the native library
or the model files present. Constructing a ``StreamingASR`` instance requires
real model files (Phase 0.4) — do NOT instantiate it in unit tests.
"""
from __future__ import annotations

from typing import Any


class StreamingASR:
    """Thin wrapper over a sherpa-onnx streaming transducer recognizer.

    Args:
        asr_cfg: the ``asr`` sub-dictionary from the speech config, containing
            ``tokens``, ``encoder``, ``decoder``, ``joiner`` and optional
            ``num_threads`` / ``decoding_method``. May also carry a private
            ``_corrector`` (a :class:`speech.asr_corrector.ASRCorrector`) which
            is applied to the finalized transcript (Phase 9).
    """

    def __init__(self, asr_cfg: dict[str, Any]) -> None:
        import sherpa_onnx  # lazy import — requires native lib + model files

        kwargs = dict(
            tokens=asr_cfg["tokens"],
            encoder=asr_cfg["encoder"],
            decoder=asr_cfg["decoder"],
            joiner=asr_cfg["joiner"],
            num_threads=asr_cfg.get("num_threads", 4),
            decoding_method=asr_cfg.get("decoding_method", "greedy_search"),
        )
        # Phase 9: optional inference-time hotword biasing (CPU-only).
        # sherpa-onnx requires modified_beam_search (not greedy_search) when a
        # hotwords file is supplied, so the decoding method is upgraded
        # automatically in that case. Behaviour is unchanged when no hotwords
        # file is configured. (On this model's BPE vocab the biasing is inert —
        # see speech/asr_corrector.py for the active error-correction path.)
        decoding_method = asr_cfg.get("decoding_method", "greedy_search")
        hw_file = asr_cfg.get("hotwords_file")
        if hw_file:
            kwargs["hotwords_file"] = hw_file
            kwargs["hotwords_score"] = float(asr_cfg.get("hotwords_score", 1.5))
            decoding_method = "modified_beam_search"
        kwargs["decoding_method"] = decoding_method
        self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(**kwargs)
        self.stream = self.recognizer.create_stream()
        self._sample_rate = asr_cfg.get("sample_rate", 16000)
        self._corrector = asr_cfg.get("_corrector")

    def accept(self, samples: list[float]) -> None:
        """Feed a chunk of float32 samples into the stream."""
        self.stream.accept_waveform(self._sample_rate, samples)

    def partial(self) -> str:
        """Return the current (non-final) decoding result."""
        return self.recognizer.get_result(self.stream)

    def finalize(self) -> str:
        """Finalize the stream and return the decoded text, then reset.

        Mirrors the official sherpa-onnx streaming example: after all real
        samples are fed, a short tail of silence is accepted so the decoder
        flushes its trailing feature frames, then we loop ``decode_stream``
        while ``is_ready`` returns true. Calling this on a never-fed/empty
        stream raises, so that case is guarded — callers (e.g. run_capture)
        then always terminate with whatever partial text exists.
        """
        try:
            tail = [0.0] * int(0.3 * self._sample_rate)  # 300 ms silence flush
            self.stream.accept_waveform(self._sample_rate, tail)
            while self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
        except Exception:  # noqa: BLE001 — empty/underrun stream: nothing to decode
            pass
        txt = self.recognizer.get_result(self.stream)
        self.stream = self.recognizer.create_stream()
        return txt

    def transcribe(self) -> str:
        """Finalize and optionally apply the Phase 9 error corrector.

        Returns the (corrected) decoded text. Equivalent to :meth:`finalize`
        when no corrector is configured.
        """
        txt = self.finalize()
        if self._corrector is not None:
            txt, _ = self._corrector.correct(txt)
        return txt
