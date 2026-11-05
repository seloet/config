"""Prepare a Colab VM for LocalAssistant Zipformer fine-tuning.

This script is intended to be executed with:

    colab exec -s localassistant-ft -f tools/colab_finetune_setup.py

It is idempotent so a disconnected CLI can safely re-run it on the same VM.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path("/content")
ICEFALL = ROOT / "icefall"
CORPUS_ARCHIVE = ROOT / "localassistant-corpus.tar.gz"
CORPUS = ROOT / "localassistant-corpus"
MODEL = ROOT / "streaming-zipformer-base"
SETUP_PROVENANCE = ROOT / "localassistant-setup-provenance.json"

K2_VERSION = "1.24.4.dev20260625+cuda12.8.torch2.11.0"
K2_INDEX = "https://k2-fsa.github.io/k2/cuda.html"
MODEL_REPO = "Zengwei/icefall-asr-librispeech-streaming-zipformer-2023-05-17"
ICEFALL_COMMIT = "3f848bb6d0acc970c9b294a30ca0a04a7c9c78d1"
MODEL_REVISION = "37cb5606808f3d5e55a3fc73554bdf757d82465a"
SHERPA_ONNX_VERSION = "1.13.8"
EXPERIMENTAL_ACK_ENV = "LOCALASSISTANT_ALLOW_UNVALIDATED_FINETUNE"
EXPERIMENTAL_ACK = "I_ACCEPT_UNVALIDATED_CODE"
CORPUS_SHA256_ENV = "LOCALASSISTANT_CORPUS_SHA256"


def run(args: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def require_experimental_opt_in() -> None:
    """Keep the unvalidated remote-training path fail-closed by default."""
    if os.environ.get(EXPERIMENTAL_ACK_ENV) != EXPERIMENTAL_ACK:
        raise RuntimeError(
            "Colab fine-tuning is unvalidated and disabled by default; set "
            f"{EXPERIMENTAL_ACK_ENV}={EXPERIMENTAL_ACK} only in an isolated VM"
        )


def _prepare_pinned_icefall() -> None:
    if ICEFALL.exists() and not (ICEFALL / ".git").is_dir():
        raise RuntimeError(f"refusing non-git icefall directory: {ICEFALL}")
    if not ICEFALL.exists():
        run(["git", "clone", "--no-checkout", "https://github.com/k2-fsa/icefall", str(ICEFALL)])
    origin = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=ICEFALL,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    if origin.rstrip("/") not in {
        "https://github.com/k2-fsa/icefall",
        "https://github.com/k2-fsa/icefall.git",
    }:
        raise RuntimeError(f"unexpected icefall origin: {origin}")
    run(["git", "fetch", "--depth", "1", "origin", ICEFALL_COMMIT], cwd=ICEFALL)
    # This clone is pipeline-owned and disposable. Resetting removes stale recipe
    # patches from an interrupted rerun before the pinned patch is reapplied.
    run(["git", "checkout", "--detach", "--force", ICEFALL_COMMIT], cwd=ICEFALL)
    run(["git", "clean", "-fdx"], cwd=ICEFALL)


def install_dependencies() -> None:
    run([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--quiet",
        f"k2=={K2_VERSION}",
        "-f",
        K2_INDEX,
    ])
    _prepare_pinned_icefall()
    run([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--quiet",
        "-r",
        str(ICEFALL / "requirements.txt"),
        "lhotse",
        "huggingface_hub",
        "onnx",
        "onnxruntime",
        f"sherpa-onnx=={SHERPA_ONNX_VERSION}",
    ])


def extract_corpus() -> str:
    if not CORPUS_ARCHIVE.is_file():
        raise FileNotFoundError(CORPUS_ARCHIVE)
    expected = os.environ.get(CORPUS_SHA256_ENV, "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise RuntimeError(
            f"set {CORPUS_SHA256_ENV} to the sha256 of {CORPUS_ARCHIVE}"
        )
    digest = hashlib.sha256()
    with CORPUS_ARCHIVE.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != expected:
        raise RuntimeError(
            f"corpus checksum mismatch: expected {expected}, got {actual}"
        )
    if CORPUS.exists():
        shutil.rmtree(CORPUS)
    extract_root = ROOT / "_localassistant_extract"
    if extract_root.exists():
        shutil.rmtree(extract_root)
    extract_root.mkdir(exist_ok=True)
    with tarfile.open(CORPUS_ARCHIVE, "r:gz") as archive:
        archive.extractall(extract_root, filter="data")
    samples = extract_root / "tests" / "fixtures" / "samples"
    samples.rename(CORPUS)
    return actual


def download_base_model() -> None:
    from huggingface_hub import snapshot_download

    MODEL.mkdir(exist_ok=True)
    snapshot_download(
        repo_id=MODEL_REPO,
        revision=MODEL_REVISION,
        allow_patterns=[
            "exp/pretrained.pt",
            "data/lang_bpe_500/bpe.model",
            "data/lang_bpe_500/tokens.txt",
        ],
        local_dir=MODEL,
    )


def main() -> None:
    require_experimental_opt_in()
    install_dependencies()
    corpus_sha256 = extract_corpus()
    download_base_model()
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ICEFALL,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    versions = subprocess.run(
        [
            sys.executable,
            "-c",
            "import json,k2,lhotse,torch;"
            "print(json.dumps({'k2':getattr(k2,'__version__',k2.__dev_version__),"
            "'lhotse':lhotse.__version__,"
            "'torch':torch.__version__,'gpu':torch.cuda.get_device_name(0)}))",
        ],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    provenance = {
        "icefall_commit": sha,
        "base_model_revision": MODEL_REVISION,
        "corpus_sha256": corpus_sha256,
        "runtime": json.loads(versions),
        "corpus_wavs": len(list(CORPUS.glob("*.wav"))),
        "checkpoint": str(MODEL / "exp" / "pretrained.pt"),
    }
    SETUP_PROVENANCE.write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(provenance), flush=True)


if __name__ == "__main__":
    main()
