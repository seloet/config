"""Thread-safe audio buffers for the streaming pipeline.

Provides:
  * ``RingBuffer`` — a fixed-capacity (by time) ring of float samples used for
    pre-roll capture (plan: 200–500 ms; default configured to 300 ms elsewhere).
  * ``ChunkQueue`` — a thin wrapper around ``queue.Queue`` for streaming raw
    microphone frames between the capture callback and the consumer.

Pure Python + stdlib (``queue``, ``threading``). ``numpy`` is not required.
"""
from __future__ import annotations

import queue
import threading
from typing import Any


class RingBuffer:
    """A thread-safe, time-bounded ring buffer of float samples.

    Samples are appended in arrival order. Once more than ``capacity_seconds``
    worth of samples have been stored, the oldest samples are dropped so that
    :meth:`get_recent` always returns at most ``capacity_seconds`` of audio.
    """

    def __init__(self, capacity_seconds: float, sample_rate: int = 16000) -> None:
        if capacity_seconds <= 0:
            raise ValueError("capacity_seconds must be positive")
        if sample_rate <= 0:
            raise ValueError("sample_rate must be positive")
        self.capacity_seconds = capacity_seconds
        self.sample_rate = sample_rate
        self._capacity = int(round(capacity_seconds * sample_rate))
        self._buf: list[float] = []
        self._lock = threading.Lock()

    @property
    def capacity(self) -> int:
        """Maximum number of samples retained."""
        return self._capacity

    def push(self, samples: list[float]) -> None:
        """Append ``samples`` and trim to capacity (keep the most recent)."""
        if not samples:
            return
        with self._lock:
            self._buf.extend(samples)
            overflow = len(self._buf) - self._capacity
            if overflow > 0:
                del self._buf[:overflow]

    def get_recent(self) -> list[float]:
        """Return a copy of the most recent samples (<= capacity)."""
        with self._lock:
            return list(self._buf)

    def clear(self) -> None:
        """Discard all buffered samples."""
        with self._lock:
            self._buf.clear()


class ChunkQueue:
    """Wrapper around ``queue.Queue`` for streaming microphone frames.

    Each item is a chunk of audio frames (e.g. a ``list[float]`` or numpy
    array) produced by the capture callback and consumed by the ASR/VAD loop.
    """

    def __init__(self, maxsize: int = 0) -> None:
        self._queue: queue.Queue[Any] = queue.Queue(maxsize=maxsize)

    def put(self, chunk: Any, block: bool = True, timeout: float | None = None) -> None:
        self._queue.put(chunk, block=block, timeout=timeout)

    def get(self, block: bool = True, timeout: float | None = None) -> Any:
        return self._queue.get(block=block, timeout=timeout)

    def qsize(self) -> int:
        return self._queue.qsize()

    def empty(self) -> bool:
        return self._queue.empty()
