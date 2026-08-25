"""Output notifications for LocalAssistant (activation chime and outcomes).

The chime is generated in-process (a short two-tone sine burst) so there is no
external asset to ship. Playback goes through ``sounddevice`` which is imported
LAZILY inside :func:`play_chime` / :meth:`Notifier.activate`; importing this
module must not require the native PortAudio library (needed under pytest and
for headless unit tests).

For testing, the synth is a pure function :func:`synth_chime_samples` returning
a ``list[float]``; both :class:`Notifier.activate` and the event callback path
are exercised without touching the speaker by passing ``play=False``.
"""
from __future__ import annotations

import math
import os
import shutil
import subprocess
from typing import Callable

DEFAULT_SAMPLE_RATE = 16000


def synth_chime_samples(
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    duration: float = 0.18,
    freqs: tuple[float, float] = (660.0, 880.0),
) -> list[float]:
    """Synthesize a short two-tone activation chime as float32 samples [-1, 1].

    Pure and deterministic — used directly by unit tests and by the player.
    """
    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")
    if duration <= 0:
        raise ValueError("duration must be positive")
    n = int(duration * sample_rate)
    half = n // 2
    out: list[float] = []
    for i in range(n):
        seg = 0 if i < half else 1
        t = (i - (0 if seg == 0 else half)) / sample_rate
        f = freqs[seg]
        # gentle 10 ms fade-in/out to avoid clicks
        fade = min(t, duration / 2 - t, 0.01)
        fade = 0.0 if fade <= 0 else (fade / 0.01)
        amp = 0.25 * fade
        out.append(amp * math.sin(2 * math.pi * f * t))
    return out


class Notifier:
    """Emits user-facing notifications (sound, desktop UI, and callbacks)."""

    def __init__(
        self,
        sample_rate: int = DEFAULT_SAMPLE_RATE,
        play: bool = True,
        on_activate: Callable[[str], None] | None = None,
        on_notify: Callable[[str], None] | None = None,
        desktop: bool = False,
        desktop_sender: Callable[[str, str], bool] | None = None,
    ) -> None:
        self.sample_rate = sample_rate
        self.play = play
        self._on_activate = on_activate
        self._on_notify = on_notify
        self.desktop = desktop
        self._desktop_sender = desktop_sender or send_desktop_notification

    def activate(self, label: str = "wake") -> list[float]:
        """Play (or, if ``play=False``, only synthesize) the activation chime.

        Returns the synthesized samples so callers/tests can inspect them.
        ``on_activate`` (if set) is always invoked, regardless of ``play``,
        so event logging works headlessly.
        """
        samples = synth_chime_samples(self.sample_rate)
        if self._on_activate is not None:
            self._on_activate(label)
        if self.play:
            _play_samples(samples, self.sample_rate)
        return samples

    def notify(self, message: str, title: str = "LocalAssistant") -> bool:
        """Present a command outcome and report whether a channel received it."""
        delivered = False
        callback = self._on_notify or self._on_activate
        if callback is not None:
            callback(message)
            delivered = True
        if self.desktop:
            delivered = self._desktop_sender(title, message) or delivered
        return delivered


def send_desktop_notification(title: str, message: str) -> bool:
    """Send a local freedesktop notification, degrading safely when headless."""
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        return False
    command = shutil.which("notify-send")
    if command is None:
        return False
    try:
        completed = subprocess.run(
            [
                command,
                "--app-name=LocalAssistant",
                "--hint=boolean:suppress-sound:true",
                "--",
                title,
                message,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2.0,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def _play_samples(samples: list[float], sample_rate: int) -> None:
    """Play float32 samples via sounddevice (lazy import)."""
    import sounddevice as sd  # native lib required only at playback time

    sd.play(samples, samplerate=sample_rate, blocking=True)
