"""Train and export a LocalAssistant streaming Zipformer adapter on Colab.

Prerequisite: run ``tools/colab_finetune_setup.py`` on the same VM.
The resulting archive is written to
``/content/localassistant-finetuned.tar.gz`` for ``colab download``.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

try:
    from tools.colab_finetune_setup import (
        ICEFALL_COMMIT,
        MODEL_REPO,
        MODEL_REVISION,
        SETUP_PROVENANCE,
        SHERPA_ONNX_VERSION,
        require_experimental_opt_in,
    )
except ModuleNotFoundError as exc:
    if exc.name != "tools":
        raise
    # ``python tools/colab_finetune_train.py`` puts tools/ rather than the repo
    # root on sys.path. Import the sibling so the fail-closed opt-in gate still
    # runs before any dependency, network, or training side effect.
    from colab_finetune_setup import (  # type: ignore[import-not-found,no-redef]
        ICEFALL_COMMIT,
        MODEL_REPO,
        MODEL_REVISION,
        SETUP_PROVENANCE,
        SHERPA_ONNX_VERSION,
        require_experimental_opt_in,
    )

ROOT = Path("/content")
ICEFALL = ROOT / "icefall"
ASR = ICEFALL / "egs" / "librispeech" / "ASR"
CORPUS = ROOT / "localassistant-corpus"
BASE = ROOT / "streaming-zipformer-base"
MANIFESTS = ROOT / "localassistant-manifests"
EXP = ROOT / "localassistant-exp"
RESULT = ROOT / "localassistant-result"

EPOCHS = 12
ADAPTER_DIM = 8
TRAIN_VOICES = {
    "af_heart",
    "af_sky",
    "af_nova",
    "am_michael",
    "am_adam",
    "am_liam",
}
DEV_VOICE = "af_bella"
TEST_VOICE = "bf_emma"


def run(args: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(args), flush=True)
    env = os.environ.copy()
    env["PYTHONPATH"] = f"{ICEFALL}:{env.get('PYTHONPATH', '')}"
    env["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"
    process = subprocess.Popen(
        args,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
    if process.wait() != 0:
        raise subprocess.CalledProcessError(process.returncode, args)


def prepare_manifests() -> dict[str, int]:
    """Create raw-audio Lhotse cuts using speaker-disjoint splits."""
    script = r'''
import json
from pathlib import Path
from lhotse import CutSet, MonoCut, Recording, SupervisionSegment

corpus = Path("/content/localassistant-corpus")
out = Path("/content/localassistant-manifests")
out.mkdir(exist_ok=True)
train_voices = {"af_heart", "af_sky", "af_nova", "am_michael", "am_adam", "am_liam"}
groups = {"train": [], "dev": [], "test": []}

for wav in sorted(corpus.glob("*.wav")):
    metadata = json.loads(wav.with_suffix(".json").read_text())
    voice = metadata["voice"]
    split = "train" if voice in train_voices else ("dev" if voice == "af_bella" else "test")
    recording = Recording.from_file(wav, recording_id=wav.stem)
    supervision = SupervisionSegment(
        id=wav.stem,
        recording_id=recording.id,
        start=0.0,
        duration=recording.duration,
        channel=0,
        text=metadata["phrase"].upper(),
        language="English",
        speaker=voice,
    )
    groups[split].append(MonoCut(
        id=wav.stem,
        start=0.0,
        duration=recording.duration,
        channel=0,
        recording=recording,
        supervisions=[supervision],
    ))

manifests = {
    "cuts_S.jsonl.gz": groups["train"],
    "librispeech_cuts_dev-clean.jsonl.gz": groups["dev"],
    "librispeech_cuts_dev-other.jsonl.gz": groups["test"],
    "cuts_DEV.jsonl.gz": groups["test"],
}
for name, cuts in manifests.items():
    CutSet.from_cuts(cuts).to_file(out / name)
print(json.dumps({key: len(value) for key, value in groups.items()}))
'''
    completed = subprocess.run(
        [sys.executable, "-c", script],
        check=True,
        text=True,
        capture_output=True,
    )
    counts = json.loads(completed.stdout.strip().splitlines()[-1])
    if counts != {"train": 336, "dev": 56, "test": 56}:
        raise RuntimeError(f"unexpected corpus split: {counts}")
    return counts


def patch_recipe_for_raw_audio() -> None:
    """Let icefall's length filter handle cuts with on-the-fly features."""
    path = ASR / "zipformer_adapter" / "train.py"
    text = path.read_text(encoding="utf-8")
    old = "        T = ((c.num_frames - 7) // 2 + 1) // 2"
    new = (
        "        num_frames = c.num_frames or int(c.duration * 100)\n"
        "        T = ((num_frames - 7) // 2 + 1) // 2"
    )
    if old in text:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
    elif new not in text:
        raise RuntimeError("icefall raw-audio length-filter patch no longer applies")


def train() -> None:
    checkpoint = BASE / "exp" / "pretrained.pt"
    bpe = BASE / "data" / "lang_bpe_500" / "bpe.model"
    run(
        [
            sys.executable,
            "zipformer_adapter/train.py",
            "--world-size",
            "1",
            "--num-epochs",
            str(EPOCHS),
            "--start-epoch",
            "1",
            "--do-finetune",
            "true",
            "--use-mux",
            "false",
            "--use-adapters",
            "true",
            "--adapter-dim",
            str(ADAPTER_DIM),
            "--finetune-ckpt",
            str(checkpoint),
            "--exp-dir",
            str(EXP),
            "--bpe-model",
            str(bpe),
            "--manifest-dir",
            str(MANIFESTS),
            "--causal",
            "true",
            "--chunk-size",
            "16",
            "--left-context-frames",
            "128",
            "--use-fp16",
            "true",
            "--base-lr",
            "0.005",
            "--max-duration",
            "50",
            "--on-the-fly-feats",
            "true",
            "--enable-musan",
            "false",
            "--enable-spec-aug",
            "true",
            "--drop-last",
            "false",
            "--num-workers",
            "2",
            "--tensorboard",
            "false",
        ],
        cwd=ASR,
    )


def prepare_streaming_exporter() -> Path:
    """Reuse icefall's streaming exporter with the adapter model factory."""
    source = ASR / "zipformer" / "export-onnx-streaming.py"
    target = ASR / "zipformer_adapter" / "export-onnx-streaming.py"
    text = source.read_text(encoding="utf-8")
    text = text.replace(
        "from train import add_model_arguments, get_model, get_params",
        "from train import add_finetune_arguments, add_model_arguments, get_model, get_params",
    )
    text = text.replace(
        "    add_model_arguments(parser)\n\n    return parser",
        "    add_model_arguments(parser)\n"
        "    add_finetune_arguments(parser)\n\n"
        "    return parser",
    )
    target.write_text(text, encoding="utf-8")
    return target


def export_onnx() -> None:
    exporter = prepare_streaming_exporter()
    tokens = BASE / "data" / "lang_bpe_500" / "tokens.txt"
    run(
        [
            sys.executable,
            str(exporter),
            "--tokens",
            str(tokens),
            "--use-averaged-model",
            "false",
            "--epoch",
            str(EPOCHS),
            "--avg",
            "5",
            "--exp-dir",
            str(EXP),
            "--use-adapters",
            "true",
            "--adapter-dim",
            str(ADAPTER_DIM),
            "--causal",
            "true",
            "--chunk-size",
            "16",
            "--left-context-frames",
            "128",
            "--enable-int8-quantization",
            "1",
        ],
        cwd=ASR,
    )


def select_export_files(exp_dir: Path = EXP) -> dict[str, Path]:
    """Require exactly one int8 export for each transducer component."""
    selected: dict[str, Path] = {}
    for role in ("encoder", "decoder", "joiner"):
        matches = sorted(exp_dir.glob(f"{role}-*.int8.onnx"))
        if len(matches) != 1:
            raise RuntimeError(
                f"expected exactly one {role} int8 export, found {len(matches)}: "
                f"{[path.name for path in matches]}"
            )
        selected[role] = matches[0]
    return selected


def validate_export(result_dir: Path = RESULT) -> None:
    """Construct the target sherpa-onnx recognizer before archiving exports."""
    import sherpa_onnx

    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(result_dir / "tokens.txt"),
        encoder=str(result_dir / "encoder.onnx"),
        decoder=str(result_dir / "decoder.onnx"),
        joiner=str(result_dir / "joiner.onnx"),
        num_threads=1,
        decoding_method="modified_beam_search",
    )
    if recognizer.create_stream() is None:
        raise RuntimeError("sherpa-onnx failed to create a stream from the export")


def load_setup_provenance(path: Path = SETUP_PROVENANCE) -> dict:
    """Require setup evidence from the pinned dependency/corpus stage."""
    if not path.is_file():
        raise RuntimeError("missing setup provenance; run colab_finetune_setup.py")
    provenance = json.loads(path.read_text(encoding="utf-8"))
    if provenance.get("icefall_commit") != ICEFALL_COMMIT:
        raise RuntimeError("setup provenance has an unexpected icefall commit")
    if provenance.get("base_model_revision") != MODEL_REVISION:
        raise RuntimeError("setup provenance has an unexpected base-model revision")
    corpus_sha256 = provenance.get("corpus_sha256")
    if (
        not isinstance(corpus_sha256, str)
        or len(corpus_sha256) != 64
        or any(char not in "0123456789abcdef" for char in corpus_sha256)
    ):
        raise RuntimeError("setup provenance has an invalid corpus checksum")
    return provenance


def package(counts: dict[str, int], setup_provenance: dict) -> None:
    selected = select_export_files()
    if RESULT.exists():
        shutil.rmtree(RESULT)
    RESULT.mkdir()
    for role, source in selected.items():
        shutil.copy2(source, RESULT / f"{role}.onnx")
    shutil.copy2(BASE / "data" / "lang_bpe_500" / "tokens.txt", RESULT / "tokens.txt")
    shutil.copy2(BASE / "data" / "lang_bpe_500" / "bpe.model", RESULT / "bpe.model")
    validate_export()
    if (EXP / "log").exists():
        shutil.copytree(EXP / "log", RESULT / "log", dirs_exist_ok=True)

    hashes = {}
    for path in RESULT.glob("*"):
        if path.is_file():
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    provenance = {
        "base_model": MODEL_REPO,
        "base_model_revision": MODEL_REVISION,
        "sherpa_onnx_version": SHERPA_ONNX_VERSION,
        "corpus_sha256": setup_provenance["corpus_sha256"],
        "icefall_commit": subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ICEFALL,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip(),
        "epochs": EPOCHS,
        "adapter_dim": ADAPTER_DIM,
        "base_lr": 0.005,
        "split": counts,
        "train_voices": sorted(TRAIN_VOICES),
        "dev_voice": DEV_VOICE,
        "test_voice": TEST_VOICE,
        "sha256": hashes,
    }
    (RESULT / "provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    archive = ROOT / "localassistant-finetuned.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(RESULT, arcname="localassistant-finetuned")
    print(
        json.dumps(
            {
                "artifact": str(archive),
                "bytes": archive.stat().st_size,
                "files": sorted(path.name for path in RESULT.iterdir()),
            }
        ),
        flush=True,
    )


def main() -> None:
    require_experimental_opt_in()
    if not (ICEFALL / "egs").exists():
        raise RuntimeError("run colab_finetune_setup.py first")
    setup_provenance = load_setup_provenance()
    counts = prepare_manifests()
    patch_recipe_for_raw_audio()
    train()
    export_onnx()
    package(counts, setup_provenance)


if __name__ == "__main__":
    main()
