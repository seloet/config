"""Fail-closed preflight for the opt-in model/audio CI job."""
from __future__ import annotations

from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent
REQUIRED_MODEL_FIELDS = {
    "asr": ("tokens", "encoder", "decoder", "joiner"),
    "vad": ("model",),
    "keyword_spotting": ("model", "decoder", "joiner", "tokens", "keywords"),
}
REQUIRED_FIXTURES = (
    "open_application__firefox__af_heart_n0.03.wav",
    "keyword_spotting__wake__af_heart_n0.03.wav",
)


def missing_resources(
    cfg: dict[str, Any], samples_dir: Path = REPO / "tests" / "fixtures" / "samples"
) -> list[str]:
    """Return missing/empty configured model files and required WAV classes."""
    missing: list[str] = []
    for section, fields in REQUIRED_MODEL_FIELDS.items():
        values = cfg.get(section, {})
        for field in fields:
            value = values.get(field)
            path = Path(value) if value else None
            if path is None or not path.is_file() or path.stat().st_size == 0:
                missing.append(f"{section}.{field}: {value!r}")
    for name in REQUIRED_FIXTURES:
        path = samples_dir / name
        if not path.is_file() or path.stat().st_size == 0:
            missing.append(f"fixture: {path}")
    return missing


def input_devices(sounddevice: Any) -> list[str]:
    """Return devices that support the pipeline's mono 16 kHz input format."""
    usable: list[str] = []
    for index, device in enumerate(sounddevice.query_devices()):
        if int(device.get("max_input_channels", 0)) <= 0:
            continue
        try:
            sounddevice.check_input_settings(
                device=index,
                channels=1,
                dtype="float32",
                samplerate=16000,
            )
        except Exception:  # noqa: BLE001 - any PortAudio rejection is unusable
            continue
        usable.append(str(device.get("name", "<unnamed>")))
    return usable


def main() -> int:
    from speech.model_config import load_config

    missing = missing_resources(load_config())
    if missing:
        raise SystemExit("model/audio preflight failed:\n- " + "\n- ".join(missing))

    import sounddevice as sd  # type: ignore[import-not-found]

    devices = input_devices(sd)
    if not devices:
        raise SystemExit("model/audio preflight failed: no input-capable audio device")
    print(f"model/audio preflight passed; input devices: {', '.join(devices)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
