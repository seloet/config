"""Microphone capture and WAV replay for the streaming pipeline.

IMPORTANT: ``sounddevice`` is imported LAZILY inside :meth:`Microphone.start`
so that simply importing this module (e.g. under pytest, where the native
``libportaudio`` may be absent) does not fail. ``sounddevice`` is NOT imported
at module top level.

For mic-free testing and Phase-4 benchmark replay, :func:`read_wav` and the
:meth:`Microphone.from_wav` classmethod load a WAV file (16 kHz mono) using
only the stdlib ``wave`` and ``array`` modules.
"""
from __future__ import annotations

import array
import queue
import wave
from typing import Any

from .audio_buffer import ChunkQueue

DEFAULT_SAMPLE_RATE = 16000


class Microphone:
    """Capture 16 kHz mono float32 audio via sounddevice into a queue.

    The capture callback enqueues each block of frames onto a ``ChunkQueue``;
    the consumer (ASR/VAD loop) drains it with :meth:`get_queue`.
    """

    def __init__(self, sample_rate: int = DEFAULT_SAMPLE_RATE, blocksize: int = 1024) -> None:
        self.sample_rate = sample_rate
        self.blocksize = blocksize
        self._queue = ChunkQueue()
        self._stream: Any = None  # sounddevice InputStream, created in start()

    def start(self) -> None:
        """Open the input stream and begin capturing.

        ``sounddevice`` is imported here (not at module level) so the module
        can be imported without the native PortAudio library present.
        """
        import sounddevice as sd  # lazy import — requires libportaudio at runtime

        def _callback(indata, frames, time_info, status):  # noqa: ANN001
            # indata is a (frames, channels) float32 ndarray; take mono channel 0.
            chunk = [float(x) for x in indata[:, 0]]
            self._queue.put(chunk)

        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype="float32",
            blocksize=self.blocksize,
            callback=_callback,
        )
        self._stream.start()

    def stop(self) -> None:
        """Stop and close the input stream if open."""
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            finally:
                self._stream = None

    def get_queue(self) -> ChunkQueue:
        """Return the queue that receives captured frames."""
        return self._queue

    @classmethod
    def from_wav(cls, path: str, sample_rate: int = DEFAULT_SAMPLE_RATE) -> list[float]:
        """Load a WAV file and return its samples as a 16 kHz mono float32 list.

        Used for mic-free testing and benchmark replay. If the WAV is not
        16 kHz mono, it is resampled naively (linear) to ``sample_rate`` from
        its declared rate, and downmixed to mono.
        """
        return read_wav(path, sample_rate=sample_rate)


def read_wav(path: str, sample_rate: int = DEFAULT_SAMPLE_RATE) -> list[float]:
    """Read a WAV file into a float32 sample list in [-1, 1], mono, at ``sample_rate``.

    Uses only the stdlib ``wave`` and ``array`` modules (no numpy). 8/16/24/32-bit
    PCM and 32-bit float WAV are supported. Non-16k / multi-channel input is
    converted with a simple linear resample and channel-average downmix.
    """
    with wave.open(path, "rb") as wf:
        wf_channels = wf.getnchannels()
        wf_sampwidth = wf.getsampwidth()
        wf_framerate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    # Decode PCM/float frames into a mono float list at the file's own rate.
    if wf_sampwidth == 1:
        # 8-bit PCM is unsigned, centered at 128.
        a = array.array("B")
        a.frombytes(raw)
        samples = [(x - 128) / 128.0 for x in a]
    elif wf_sampwidth == 2:
        a = array.array("h")
        a.frombytes(raw)
        samples = [x / 32768.0 for x in a]
    elif wf_sampwidth == 3:
        # 24-bit PCM, little-endian, signed.
        samples = []
        for i in range(0, len(raw) - 2, 3):
            val = raw[i] | (raw[i + 1] << 8) | (raw[i + 2] << 16)
            if val & 0x800000:
                val -= 0x1000000
            samples.append(val / 8388608.0)
    elif wf_sampwidth == 4:
        # Could be 32-bit float or 32-bit PCM; sniff the first value's range.
        a = array.array("f")
        a.frombytes(raw)
        # If the magnitude exceeds 1.0 it is likely 32-bit int PCM.
        if any(abs(x) > 1.5 for x in a[: min(8, len(a))]):
            a32 = array.array("i")
            a32.frombytes(raw)
            samples = [x / 2147483648.0 for x in a32]
        else:
            samples = [float(x) for x in a]
    else:
        raise ValueError(f"Unsupported sample width: {wf_sampwidth} bytes")

    # Downmix to mono if needed.
    if wf_channels > 1:
        mono: list[float] = []
        for i in range(0, len(samples) - wf_channels + 1, wf_channels):
            mono.append(sum(samples[i : i + wf_channels]) / wf_channels)
        samples = mono

    # Resample to the requested rate if the file's rate differs.
    if wf_framerate != sample_rate and len(samples) > 1:
        ratio = wf_framerate / sample_rate
        out_len = int(len(samples) / ratio)
        resampled: list[float] = []
        for j in range(out_len):
            pos = j * ratio
            i0 = int(pos)
            frac = pos - i0
            i1 = min(i0 + 1, len(samples) - 1)
            resampled.append(samples[i0] * (1 - frac) + samples[i1] * frac)
        samples = resampled

    return [float(s) for s in samples]
