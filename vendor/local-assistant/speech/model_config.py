"""Load and expose the LocalAssistant speech pipeline configuration.

Pure-Python / PyYAML only. No sherpa-onnx import at module level, so this
module can be imported under a plain pytest run without native deps present.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

# Default location: <repo>/config/speech.yaml
_DEFAULT_PATH = Path(__file__).resolve().parent.parent / "config" / "speech.yaml"

_PATH_FIELDS = {
    "asr": ("tokens", "encoder", "decoder", "joiner", "hotwords_file"),
    "vad": ("model",),
    "keyword_spotting": ("model", "encoder", "decoder", "joiner", "tokens", "keywords"),
    "corrector": ("pairs_file",),
}


def _resolve_paths(cfg: dict[str, Any], cfg_path: Path) -> dict[str, Any]:
    """Resolve configured resource files without consulting the process CWD."""
    resolved_path = cfg_path.expanduser().resolve()
    base = resolved_path.parent
    for section, keys in _PATH_FIELDS.items():
        block = cfg.get(section)
        if not isinstance(block, dict):
            continue
        for key in keys:
            value = block.get(key)
            if not value:
                continue
            resource = Path(value).expanduser()
            if not resource.is_absolute():
                resource = base / resource
            block[key] = str(resource.resolve())
    return cfg


def load_config(path: str | Path | None = None) -> dict[str, Any]:
    """Parse and return the speech.yaml configuration as a dict.

    Args:
        path: Optional explicit path to the YAML file. Defaults to
            ``<repo>/config/speech.yaml``.

    Raises:
        FileNotFoundError: if the config file does not exist.
        yaml.YAMLError: if the file is not valid YAML.
    """
    cfg_path = Path(path) if path is not None else _DEFAULT_PATH
    with open(cfg_path, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    if not isinstance(cfg, dict):
        raise ValueError(f"Expected a mapping at top level of {cfg_path}, got {type(cfg).__name__}")
    return _resolve_paths(cfg, cfg_path)


def asr_config(cfg: dict[str, Any]) -> dict[str, Any]:
    """Return the ``asr`` sub-dictionary from a loaded config.

    ``load_config`` has already made resource paths absolute. A missing/empty
    hotwords file is returned as ``None`` (biasing disabled).
    """
    asr = cfg["asr"]
    hw = asr.get("hotwords_file")
    if hw:
        p = Path(hw)
        asr = {**asr, "hotwords_file": str(p) if p.exists() else None}
    else:
        asr = {**asr, "hotwords_file": None}
    return asr


def build_corrector(cfg: dict[str, Any]):
    """Build a Phase 9 :class:`speech.asr_corrector.ASRCorrector` from config.

    Returns ``None`` when the ``corrector`` block is absent or ``enabled:
    false``. Loads pre-trained pairs from ``pairs_file`` if present, otherwise
    learns them from the failure log (``min_count`` from config). Pure-Python;
    does not import sherpa-onnx.
    """
    block = cfg.get("corrector")
    if not block or not block.get("enabled", False):
        return None
    from speech.asr_corrector import ASRCorrector, learn_pairs, load_pairs

    pairs_file = block.get("pairs_file")
    if pairs_file:
        p = Path(pairs_file)
        if not p.is_absolute():
            p = _DEFAULT_PATH.parent.parent / p
        if p.exists():
            return ASRCorrector(load_pairs(p))
    # Fall back to learning on the fly from the failure log.
    min_count = int(block.get("min_count", 2))
    return ASRCorrector.from_failures(min_count=min_count)
