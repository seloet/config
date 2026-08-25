"""Extract the uploaded Colab job bundle and run it."""
import tarfile
from pathlib import Path
from runpy import run_path

archive = Path("/content/localassistant-colab-job.tar.gz")
with tarfile.open(archive, "r:gz") as bundle:
    bundle.extractall("/content", filter="data")
run_path("/content/tools/colab_finetune_all.py", run_name="__main__")
