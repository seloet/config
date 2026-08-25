"""Run the complete setup, fine-tune, and export pipeline on a Colab VM."""
from runpy import run_path

run_path("/content/tools/colab_finetune_setup.py", run_name="__main__")
run_path("/content/tools/colab_finetune_train.py", run_name="__main__")
