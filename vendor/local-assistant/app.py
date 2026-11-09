"""LocalAssistant Phase 6 — always-on voice orchestrator.

Wires the streaming pipeline end-to-end:

    microphone -> KWS (wake) -> VAD (endpoint) -> ASR (transcribe)
               -> parser -> safety validator -> tool registry

The heavy native components (sherpa-onnx: KWS / VAD / ASR, and the
``sounddevice`` microphone) are constructed LAZILY inside :meth:`Assistant.start`
and helper methods, never at module import time. That keeps this module (and the
whole package) importable under a plain ``pytest`` run without the native libs or
model files present.

The orchestrator is also usable without a microphone:

  * :meth:`Assistant.process_command` takes already-transcribed text, runs the
    parser -> safety gate -> dispatch, and returns a result dict. This is the
    headless path exercised by the unit tests.
  * :meth:`Assistant.run_capture` feeds a list of float samples through the real
    VAD + ASR pipeline and returns the transcript. Used by tests with synthetic
    audio (model-gated: skips if model files are absent).

CLI entry point (backwards compatible with Phase 1):

    python app.py --tool get_time --args '{}'      # run a single tool, print JSON
    python app.py --self-test                      # exercise process_command on samples
    python app.py --mic                            # run the live always-on loop
    python app.py --no-mic                         # build models but stay headless
    python app.py --list-recent                    # tail command_failure logs
"""
from __future__ import annotations

import argparse
import json
import queue
import signal
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable

# Pure-Python imports only — nothing here pulls in sherpa-onnx / sounddevice at
# import time, so `import app` is safe under plain pytest.
from parser.command_parser import parse
from parser.result import ParseResult
from safety.pending import PendingAction, PendingActionStore, classify_response
from safety.validator import validate
from tools.base import ToolResult, ok
from tools.registry import call_tool

REPO = Path(__file__).resolve().parent


def _drain_audio_queue(audio_queue: Any) -> int:
    """Discard audio already queued while the assistant was speaking/chiming."""
    discarded = 0
    while True:
        try:
            audio_queue.get(block=False)
        except queue.Empty:
            return discarded
        discarded += 1


class Assistant:
    """Always-on voice assistant orchestrator.

    Construction is cheap and model-free. The native models (KWS/VAD/ASR) and
    the microphone are only built when :meth:`start` (or a capture method) is
    called, so a test can drive :meth:`process_command` / :meth:`run_capture`
    without ever loading sherpa-onnx.

    Args:
        config_path: optional explicit path to ``config/speech.yaml``.
        mock_dispatch: optional callable ``(name, arguments) -> ToolResult`` used
            in place of :func:`tools.registry.call_tool` (tests inject a recorder
            here). Defaults to the real registry dispatcher.
        play_chime: whether the activation chime should actually play through the
            speakers. Set ``False`` for headless / test runs.
        notifier: optional pre-built :class:`output.notifications.Notifier`; one
            is created lazily when needed.
        notify_desktop: enable local freedesktop notifications on live outcomes.
        pending_timeout_seconds: seconds before an unconfirmed action is erased.
        clock: monotonic clock override used by deterministic expiry tests.
    """

    def __init__(
        self,
        config_path: str | Path | None = None,
        mock_dispatch: Callable[[str, dict[str, Any]], ToolResult] | None = None,
        play_chime: bool = False,
        notifier: Any = None,
        notify_desktop: bool = False,
        pending_timeout_seconds: float = 30.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.config_path = Path(config_path) if config_path is not None else None
        self._dispatch: Callable[[str, dict[str, Any]], ToolResult] = (
            mock_dispatch if mock_dispatch is not None else call_tool
        )
        self.play_chime = play_chime
        self.notify_desktop = notify_desktop
        self._config: dict[str, Any] | None = None

        self._kws: Any = None
        self._vad: Any = None
        self._asr: Any = None
        self._mic: Any = None
        self._notifier = notifier
        self._tray: Any = None
        self._listening = True
        self._stop_event = threading.Event()

        # Self-hearing guard (plan §29): while the chime / TTS plays we pause
        # KWS/ASR so the assistant does not trigger on its own output.
        self._self_hearing = False

        self._corrector: Any = None

        self._tiers: dict[str, str] | None = None

        # Pending commands are intentionally session-only.  A single exact
        # invocation may await confirmation; it expires fail-closed.
        self._pending = PendingActionStore(
            ttl_seconds=pending_timeout_seconds,
            clock=clock,
        )

    def _load_config(self) -> dict[str, Any]:
        if self._config is None:
            from speech.model_config import load_config

            self._config = load_config(self.config_path)
        return self._config

    def _load_tiers(self) -> dict[str, str]:
        if self._tiers is None:
            from safety.risk import load_tiers

            self._tiers = load_tiers()
        return self._tiers

    @property
    def notifier(self) -> Any:
        """Lazily construct the Notifier (headless when ``play_chime`` is False)."""
        if self._notifier is None:
            from output.notifications import Notifier

            self._notifier = Notifier(
                play=self.play_chime,
                desktop=self.notify_desktop,
            )
        return self._notifier

    @property
    def tray(self) -> Any:
        """Lazily construct the system-tray control surface (headless-safe)."""
        if self._tray is None:
            from output.tray import TrayApp

            def _pause():
                self._listening = False

            def _resume():
                self._listening = True

            def _lock():
                call_tool("lock_screen", {})

            self._tray = TrayApp(
                on_pause=_pause, on_resume=_resume,
                on_lock=_lock,
                on_quit=self.stop,
                get_listening=lambda: self._listening,
            )
        return self._tray

    def is_listening(self) -> bool:
        return self._listening

    def pause_listening(self) -> None:
        self._listening = False
        if self._tray is not None:
            self._tray.pause()

    def resume_listening(self) -> None:
        self._listening = True
        if self._tray is not None:
            self._tray.resume()

    def stop(self) -> None:
        """Request a running listening loop to exit.

        Safe to call from the tray's GUI thread. The microphone is closed by
        :meth:`listen`'s ``finally`` block on the listening thread.
        """
        self._stop_event.set()

    def _build_pipeline(self) -> None:
        """Construct KWS / VAD / ASR once (requires the native lib + models)."""
        if self._asr is not None and self._vad is not None:
            return
        cfg = self._load_config()
        from speech.keyword_spotter import KWS
        from speech.model_config import asr_config, build_corrector
        from speech.streaming_asr import StreamingASR
        from speech.vad import VAD

        self._kws = KWS.from_config(cfg)
        self._vad = VAD.from_config(cfg)
        asr_cfg = asr_config(cfg)
        # Keep ASR output raw. Correction is only considered by process_command
        # after the raw parser fails, so it can never rewrite a working parse.
        corrector = build_corrector(cfg)
        self._corrector = corrector
        self._asr = StreamingASR(asr_cfg=asr_cfg)

    @staticmethod
    def _pending_outcome(
        pending: PendingAction,
        *,
        action: str,
        message: str,
        executed: bool = False,
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return {
            "original_text": pending.original_text,
            "matched": True,
            "tool_name": pending.tool_name,
            "action": action,
            "executed": executed,
            "confidence": pending.confidence,
            "tier": pending.tier,
            "ambiguous": pending.requested_action == "confirm_if_ambiguous",
            "reason": pending.reason,
            "message": message,
            "data": data or {},
            "pending": False,
        }

    @staticmethod
    def _empty_control_outcome(message: str, reason: str) -> dict[str, Any]:
        return {
            "original_text": "",
            "matched": False,
            "tool_name": None,
            "action": "reject",
            "executed": False,
            "confidence": 0.0,
            "tier": None,
            "ambiguous": False,
            "reason": reason,
            "message": message,
            "data": {},
            "pending": False,
        }

    def _resolve_pending(self, text: str) -> dict[str, Any] | None:
        """Handle an utterance while an exact action is awaiting a reply."""
        response = classify_response(text)
        pending, expired = self._pending.inspect()

        if pending is None:
            if response is None:
                return None
            if expired:
                return self._empty_control_outcome(
                    "The pending command expired and was not run.",
                    "pending_action_expired",
                )
            return self._empty_control_outcome(
                "There is no command awaiting confirmation.",
                "no_pending_action",
            )

        if response == "cancel":
            self._pending.clear()
            return self._pending_outcome(
                pending,
                action="cancel",
                message=f"Cancelled: {pending.original_text}",
            )

        if response == "confirm":
            confirmed, expired = self._pending.pop()
            if confirmed is None:
                return self._empty_control_outcome(
                    "The pending command expired and was not run.",
                    "pending_action_expired" if expired else "no_pending_action",
                )
            result = self._dispatch(confirmed.tool_name, confirmed.arguments)
            return self._pending_outcome(
                confirmed,
                action="execute",
                message=result.message,
                executed=result.success,
                data=result.data,
            )

        remaining = self._pending.remaining_seconds(pending)
        return self._pending_outcome(
            pending,
            action=pending.requested_action,
            message=(
                "A command is awaiting confirmation. Wake me, then say "
                f"“confirm” or “cancel” within {remaining} seconds."
            ),
        ) | {"pending": True, "expires_in_seconds": remaining}

    def process_command(
        self,
        text: str,
        parsed: ParseResult | None = None,
    ) -> dict[str, Any]:
        """Route a (transcribed) command through the safety gate.

        Args:
            text: the spoken/transcribed command text.
            parsed: optional pre-parsed :class:`ParseResult`. When supplied it is
                used instead of calling :func:`parse` — this lets tests inject
                synthetic confidence / tool-name scenarios (clarify, confirm).

        Returns a result dict with the decision and, if executed, the tool
        outcome::

            {
              "original_text": str,
              "matched": bool,
              "tool_name": str | None,
              "action": str,
              "executed": bool,
              "confidence": float,
              "tier": str | None,
              "ambiguous": bool,
              "reason": str,
              "message": str,
              "data": dict,
            }
        """
        pending_outcome = self._resolve_pending(text)
        if pending_outcome is not None:
            if not pending_outcome["original_text"]:
                pending_outcome["original_text"] = text
            return pending_outcome

        result = parsed if parsed is not None else parse(text)
        # Phase 9: if the raw parse did not match a valid command, try the
        # post-ASR error-corrected form as a fallback candidate. By only
        # adopting the corrected parse when the raw one failed, correction can
        # never regress a working command.
        if not result.matched and self._corrector is not None:
            corr, _ = self._corrector.correct(text)
            if corr != text:
                r2 = parse(corr)
                if r2.matched:
                    result = r2
        tiers = self._load_tiers()

        if getattr(result, "subcommands", None):
            sub_out: list[dict[str, Any]] = []
            any_executed = False
            for sub in result.subcommands:
                sub_decision = validate(sub, tiers=tiers)
                entry = {
                    "tool_name": sub_decision.tool_name,
                    "action": sub_decision.action,
                    "executed": False,
                    "confidence": sub_decision.confidence,
                    "tier": sub_decision.tier,
                    "reason": sub_decision.reason,
                    "message": "",
                    "data": {},
                }
                if sub_decision.execute_now:
                    res = self._dispatch(sub_decision.tool_name, sub.arguments)
                    entry["executed"] = res.success
                    entry["message"] = res.message
                    entry["data"] = res.data
                    any_executed = any_executed or res.success
                elif sub_decision.needs_confirmation:
                    entry["message"] = "confirmation required"
                elif sub_decision.should_clarify:
                    entry["message"] = "clarification needed"
                elif sub_decision.should_reject:
                    entry["message"] = sub_decision.reason or "rejected"
                sub_out.append(entry)
            return {
                "original_text": text,
                "matched": True,
                "tool_name": None,
                "action": "multi",
                "executed": any_executed,
                "confidence": min(s.confidence for s in result.subcommands),
                "tier": None,
                "ambiguous": False,
                "reason": None,
                "message": f"dispatched {len(sub_out)} subcommands",
                "data": {"subcommands": sub_out},
            }

        decision = validate(result, tiers=tiers)

        out: dict[str, Any] = {
            "original_text": text,
            "matched": result.matched,
            "tool_name": decision.tool_name,
            "action": decision.action,
            "executed": False,
            "confidence": decision.confidence,
            "tier": decision.tier,
            "ambiguous": decision.ambiguous,
            "reason": decision.reason,
            "message": "",
            "data": {},
            "pending": False,
        }

        if decision.execute_now:
            res = self._dispatch(decision.tool_name, result.arguments)
            out["executed"] = res.success
            out["message"] = res.message
            out["data"] = res.data
        elif decision.needs_confirmation:
            pending = self._pending.set(
                original_text=text,
                tool_name=decision.tool_name or "",
                arguments=result.arguments,
                requested_action=decision.action,
                confidence=decision.confidence,
                tier=decision.tier,
                reason=decision.reason,
            )
            out["message"] = (
                f"To run “{text}”, wake me and say confirm, or wake me and say "
                f"cancel, within "
                f"{round(self._pending.ttl_seconds)} seconds."
            )
            out["pending"] = True
            out["expires_in_seconds"] = round(
                pending.expires_at - pending.created_at
            )
        elif decision.should_clarify:
            pending = self._pending.set(
                original_text=text,
                tool_name=decision.tool_name or "",
                arguments=result.arguments,
                requested_action=decision.action,
                confidence=decision.confidence,
                tier=decision.tier,
                reason=decision.reason,
            )
            out["message"] = (
                f"I heard “{text}”. Wake me and say confirm to run it, or wake "
                f"me and say cancel, within "
                f"{round(self._pending.ttl_seconds)} seconds."
            )
            out["pending"] = True
            out["expires_in_seconds"] = round(
                pending.expires_at - pending.created_at
            )
        elif decision.should_reject:
            out["message"] = decision.reason or "rejected"

        return out

    def _present_outcome(self, outcome: dict[str, Any]) -> bool:
        """Route a live command outcome to the configured user-facing channel."""
        if outcome.get("pending"):
            title = "LocalAssistant — confirmation needed"
        elif outcome.get("executed"):
            title = "LocalAssistant — command complete"
        elif outcome.get("action") == "cancel":
            title = "LocalAssistant — command cancelled"
        else:
            title = "LocalAssistant — command not run"
        self._self_hearing = True
        try:
            return bool(self.notifier.notify(outcome["message"], title=title))
        finally:
            self._self_hearing = False

    def run_capture(self, utterance_samples: list[float]) -> str:
        """Feed samples through VAD + ASR and return the transcript.

        The VAD segments the utterance; each detected segment is streamed to the
        ASR. The method finalizes and returns the decoded text (with the Phase 9
        error corrector applied, if configured). Builds the native models on
        demand (so it is model-gated in tests). Guaranteed to return a ``str``
        and to terminate (it never blocks on a microphone).
        """
        if self._vad is None or self._asr is None:
            cfg = self._load_config()
            from speech.model_config import asr_config, build_corrector
            from speech.streaming_asr import StreamingASR
            from speech.vad import VAD

            self._vad = VAD.from_config(cfg)
            asr_cfg = asr_config(cfg)
            corrector = build_corrector(cfg)
            self._corrector = corrector
            self._asr = StreamingASR(asr_cfg=asr_cfg)

        chunk = 1600  # 100 ms @ 16 kHz
        for i in range(0, len(utterance_samples), chunk):
            self._vad.accept(utterance_samples[i : i + chunk])

        fed = False
        utt = self._vad.process(flush=True)
        while utt is not None:
            self._asr.accept(utt)
            fed = True
            utt = self._vad.process()

        # Fallback: if VAD segmented nothing (e.g. synthetic/non-speech audio
        # that Silero does not flag), feed the raw clip directly so finalize()
        # always has a non-empty stream to decode (finalizing an empty stream
        # hangs sherpa-onnx). This mirrors the e2e audio-path pattern.
        if not fed:
            for i in range(0, len(utterance_samples), chunk):
                self._asr.accept(utterance_samples[i : i + chunk])

        return self._asr.finalize().strip()

    def start(self) -> None:
        """Build models and (if mic mode) open the microphone. Idempotent."""
        self._build_pipeline()
        if self._mic is not None:
            return
        from audio.microphone import Microphone

        self._mic = Microphone(sample_rate=self._load_config()["asr"].get("sample_rate", 16000))

    def _on_wake(self, label: str = "wake") -> None:
        """Play the activation chime and set the self-hearing guard."""
        self._self_hearing = True
        self.notifier.activate(label)
        self._self_hearing = False

    def listen(self, chunk: int = 1024, poll_timeout: float = 0.1) -> None:
        """Run the always-on mic -> KWS -> VAD -> ASR -> dispatch loop.

        Pulls chunks from the microphone queue, feeds KWS; on a detected wake it
        plays the chime, then enters capture mode (VAD + ASR) until the next
        endpoint, after which it routes the transcript through the safety gate.
        """
        self.start()
        self._mic.start()
        audio_queue = self._mic.get_queue()

        try:
            while not self._stop_event.is_set():
                try:
                    samples = audio_queue.get(block=True, timeout=poll_timeout)
                except queue.Empty:
                    continue

                if not self._listening or self._self_hearing:
                    continue

                self._kws.accept(samples)
                wake = self._kws.process()
                if wake is None:
                    continue

                self._on_wake("wake")
                # The microphone callback remains active during the synchronous
                # chime. Drop those frames so the assistant cannot hear itself.
                _drain_audio_queue(audio_queue)
                self._kws.reset()
                self._capture_until_endpoint()
        finally:
            self._mic.stop()

    def _capture_until_endpoint(
        self,
        *,
        no_speech_timeout: float | None = None,
        max_capture_seconds: float | None = None,
        poll_timeout: float = 0.1,
        clock: Callable[[], float] = time.monotonic,
    ) -> dict[str, Any] | None:
        """Capture one post-wake utterance and route it, with hard deadlines.

        A wake with no following speech returns within three seconds so KWS can
        re-arm. Active speech is capped by ``vad.max_utterance_seconds``; at that
        deadline the native VAD is flushed once so a partial final segment can be
        decoded. Empty ASR streams are never finalized.
        """
        cfg: dict[str, Any] = {}
        if no_speech_timeout is None or max_capture_seconds is None:
            cfg = self._load_config().get("vad", {})
        if no_speech_timeout is None:
            no_speech_timeout = float(cfg.get("no_speech_timeout_seconds", 3.0))
        if max_capture_seconds is None:
            max_capture_seconds = float(cfg.get("max_utterance_seconds", 12.0))
        no_speech_timeout = max(0.0, min(float(no_speech_timeout), 3.0))
        max_capture_seconds = max(0.1, float(max_capture_seconds))

        audio_queue = self._mic.get_queue()
        self._vad.reset()
        captured: list[float] = []
        speech_started = False
        started_at = clock()
        while not self._stop_event.is_set() and self._listening:
            elapsed = clock() - started_at
            if not speech_started and elapsed >= no_speech_timeout:
                break
            if elapsed >= max_capture_seconds:
                if speech_started:
                    captured = self._vad.process(flush=True) or []
                break

            deadline = max_capture_seconds
            if not speech_started:
                deadline = min(deadline, no_speech_timeout)
            wait = max(0.0, min(poll_timeout, deadline - elapsed))
            try:
                samples = audio_queue.get(block=True, timeout=wait)
            except queue.Empty:
                continue
            self._vad.accept(samples)
            speech_started = speech_started or self._vad.is_speech_detected()
            seg = self._vad.process()
            if seg is not None:
                captured = seg
                break
        if captured:
            self._asr.accept(captured)
            text = self._asr.finalize().strip()
            if text:
                outcome = self.process_command(text)
                self._present_outcome(outcome)
                return outcome
        # ASR's finalize() already re-creates its stream; VAD re-arms on the
        # next segment automatically, so no explicit reset() is needed here.
        return None


def _do_single_tool(tool: str, args_json: str) -> int:
    """Phase-1 behaviour: run one tool, print JSON, exit 0/1."""
    res = call_tool(tool, json.loads(args_json))
    print(json.dumps(res.__dict__, indent=2))
    return 0 if res.success else 1


def _self_test(assistant: Assistant) -> int:
    """Exercise process_command on a handful of representative inputs."""
    samples = [
        "open firefox",
        "what is the time",
        "start a timer for ten minutes",
        "create a note saying stand up",
    ]
    for s in samples:
        print(json.dumps(assistant.process_command(s), indent=2))
    return 0


def _list_recent(n: int = 10) -> int:
    log = REPO / "logs" / "command_failures.jsonl"
    if not log.exists():
        print(f"no failure log at {log}")
        return 0
    lines = log.read_text(encoding="utf-8").splitlines()
    for line in lines[-n:]:
        print(line)
    return 0


def _install_signal_handlers(assistant: Assistant) -> None:
    """Route terminal/systemd stop signals through microphone cleanup."""
    def _request_stop(_signum: int, _frame: Any) -> None:
        assistant.stop()

    signal.signal(signal.SIGINT, _request_stop)
    signal.signal(signal.SIGTERM, _request_stop)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="LocalAssistant always-on orchestrator")
    p.add_argument("--tool", help="run a single tool and exit (Phase-1 mode)")
    p.add_argument("--args", default="{}", help="JSON object of arguments")
    p.add_argument("--config", default=None, help="path to config/speech.yaml")
    p.add_argument("--mic", dest="mic", action="store_true", default=None,
                   help="run the live always-on microphone loop")
    p.add_argument("--no-mic", dest="mic", action="store_false",
                   help="build models but stay headless")
    p.add_argument("--self-test", action="store_true",
                   help="exercise process_command on sample commands")
    p.add_argument("--list-recent", action="store_true",
                   help="tail the command_failure log")
    p.add_argument("--play-chime", action="store_true", default=False,
                   help="actually play the activation chime (off by default)")
    p.add_argument("--no-notifications", action="store_true",
                   help="disable desktop notifications in microphone/tray mode")
    p.add_argument("--tray", action="store_true",
                   help="show the system tray and run the always-on loop (GUI)")
    p.add_argument("--pause", action="store_true",
                   help="pause listening (headless control hook)")
    p.add_argument("--resume", action="store_true",
                   help="resume listening (headless control hook)")
    p.add_argument("--recent-n", type=int, default=10)
    a = p.parse_args(argv)

    if a.tool:
        return _do_single_tool(a.tool, a.args)

    if a.list_recent:
        return _list_recent(a.recent_n)

    assistant = Assistant(
        config_path=a.config,
        play_chime=a.play_chime,
        notify_desktop=bool(a.mic or a.tray) and not a.no_notifications,
    )

    if a.self_test:
        return _self_test(assistant)

    if a.pause:
        assistant.pause_listening()
        print("listening paused")
        return 0
    if a.resume:
        assistant.resume_listening()
        print("listening resumed")
        return 0

    if a.mic or a.tray:
        _install_signal_handlers(assistant)
        if a.tray:
            tray = assistant.tray
            tray.run_detached()
            if not tray.available:
                print("system tray unavailable; continuing in microphone mode",
                      file=sys.stderr)
        assistant.listen()
        return 0

    print("LocalAssistant ready (headless). Use --mic to listen, --self-test to probe, "
          "--tool to run a single tool.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
