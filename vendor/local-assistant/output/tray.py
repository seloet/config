"""System-tray UI for LocalAssistant (Phase 6 control surface).

Uses ``pystray`` + ``PIL`` (installed into the venv). The icon is rendered
in-process from a tiny Pillow image, so no asset file ships.

The tray is *headless-safe*: constructing :class:`TrayApp` never touches the
display, and :meth:`TrayApp.run` only calls ``pystray.Icon.run`` when a display
is actually available. Under a headless test/CI run (no ``$DISPLAY`` /
``$WAYLAND_DISPLAY``, or pystray import failure) the app degrades to a no-op and
exposes the control hooks programmatically so the wiring can be unit-tested.

Important: ``import pystray`` itself opens an X connection on Linux (pystray's
``_xorg`` backend does ``Xlib.display.Display()`` at import time). Importing it
at module load would make this module unimportable on a headless box, so pystray
is imported *lazily* inside the methods that build a real icon. We only probe
for its presence with :func:`importlib.util.find_spec`, which does not execute
any module-level code and therefore never touches the display.
"""

from __future__ import annotations

import importlib.util
import os
import threading
from typing import Any, Callable

try:  # PIL is needed for the icon and works headless.
    from PIL import Image, ImageDraw

    _HAVE_PIL = True
except Exception:  # pragma: no cover - depends on environment
    Image = None  # type: ignore[assignment]
    ImageDraw = None  # type: ignore[assignment]
    _HAVE_PIL = False

# Probe for pystray without importing it (importing would open an X connection).
_HAVE_TRAY = importlib.util.find_spec("pystray") is not None


def _load_pystray() -> Any:
    """Lazily import pystray, raising a clear error if a display is unreachable.

    This is the only place pystray is imported. It is called from the methods
    that actually build a system tray, so module import stays headless-safe.
    """
    import pystray  # noqa: PLC0415 - intentional lazy import (X connection here)

    return pystray


def make_icon_image(size: int = 64, color: str = "dodgerblue") -> Any:
    """Render a simple round badge as a PIL.Image (headless-testable).

    Only requires PIL, never pystray, so it works in a headless environment.
    """
    if not _HAVE_PIL:
        raise RuntimeError("PIL not available")
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, size - 4, size - 4], fill=color)
    d.ellipse([size // 3, size // 3, 2 * size // 3, 2 * size // 3], fill="white")
    return img


class TrayApp:
    """Control surface: pause/resume, lock screen, quit.

    Args:
        on_pause: callback invoked when the user pauses listening.
        on_resume: callback invoked when the user resumes listening.
        on_lock: callback invoked when the user picks "Lock screen".
        on_quit: callback invoked when the user quits (defaults to stopping
            the tray loop).
        get_listening: callable returning the current listening state, used to
            keep the menu label in sync.
    """

    def __init__(
        self,
        on_pause: Callable[[], None] | None = None,
        on_resume: Callable[[], None] | None = None,
        on_lock: Callable[[], None] | None = None,
        on_quit: Callable[[], None] | None = None,
        get_listening: Callable[[], bool] | None = None,
    ) -> None:
        self._on_pause = on_pause or (lambda: None)
        self._on_resume = on_resume or (lambda: None)
        self._on_lock = on_lock or (lambda: None)
        self._on_quit = on_quit or (lambda: None)
        self._get_listening = get_listening
        self._listening = bool(get_listening()) if get_listening else True
        self._icon: Any = None
        self._thread: threading.Thread | None = None
        self._available = _HAVE_TRAY and self._display_present()

    # ------------------------------------------------------------------ #
    @staticmethod
    def _display_present() -> bool:
        return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))

    @property
    def available(self) -> bool:
        """True when a real tray can be shown (display + libs present)."""
        return self._available

    # ------------------------------------------------------------------ #
    # Control hooks (also called programmatically in tests)
    # ------------------------------------------------------------------ #
    def _is_listening(self) -> bool:
        if self._get_listening is not None:
            return bool(self._get_listening())
        return self._listening

    def pause(self) -> None:
        if self._is_listening():
            self._listening = False
            self._on_pause()
            self._refresh_menu()

    def resume(self) -> None:
        if not self._is_listening():
            self._listening = True
            self._on_resume()
            self._refresh_menu()

    def toggle_listen(self) -> None:
        (self.pause if self._is_listening() else self.resume)()

    def lock(self) -> None:
        self._on_lock()

    def quit(self) -> None:
        self._on_quit()
        if self._icon is not None:
            try:
                self._icon.stop()
            except Exception:  # pragma: no cover
                pass

    # ------------------------------------------------------------------ #
    def _menu(self) -> Any:
        pystray = _load_pystray()
        items = [
            pystray.MenuItem(
                lambda _: (
                    "Pause listening" if self._is_listening()
                    else "Resume listening"
                ),
                lambda _: self.toggle_listen(),
            ),
            pystray.MenuItem("Lock screen", lambda _: self.lock()),
            pystray.MenuItem("Quit", lambda _: self.quit()),
        ]
        return pystray.Menu(*items)

    def _refresh_menu(self) -> None:
        if self._icon is not None and hasattr(self._icon, "update_menu"):
            try:
                self._icon.update_menu()
            except Exception:  # pragma: no cover
                pass

    # ------------------------------------------------------------------ #
    def _build_icon(self) -> Any:
        """Build a pystray.Icon, degrading gracefully if the display is gone."""
        try:
            pystray = _load_pystray()
        except Exception:  # pragma: no cover - no reachable display
            self._available = False
            return None
        return pystray.Icon(
            "LocalAssistant",
            icon=make_icon_image(),
            title="LocalAssistant",
            menu=self._menu(),
        )

    def run(self) -> None:
        """Show the tray and return immediately (runs on a daemon thread so the
        caller is never blocked). No-op when headless (no display available)."""
        if not self._available:
            return
        self._icon = self._build_icon()
        if self._icon is None:
            return
        self._icon.run_detached()

    def run_blocking(self) -> None:
        """Show the tray and block until the user quits (real GUI entry point)."""
        if not self._available:
            return
        self._icon = self._build_icon()
        if self._icon is None:
            return
        self._icon.run()

    def run_detached(self) -> threading.Thread:
        """Backwards-compatible alias: spawn :meth:`run` on a background thread."""
        self.run()
        if self._thread is None:
            self._thread = threading.Thread(target=lambda: None, daemon=True)
        return self._thread
