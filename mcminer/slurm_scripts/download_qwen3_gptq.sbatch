#!/bin/bash
#SBATCH --job-name=dl_qwen3_gptq
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --output=/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer/job_logs/download_qwen3_gptq-%j.out
#SBATCH --error=/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer/job_logs/download_qwen3_gptq-%j.err

set -euo pipefail

PROJECT_DIR="/WAVE/projects2/CSEN-346-Sp26/Group2"
MODEL_ID="${MODEL_ID:-JunHowie/Qwen3-14B-GPTQ-Int4}"
MODEL_NAME="${MODEL_ID##*/}"
MODEL_DIR="${MODEL_DIR:-$PROJECT_DIR/qwen_models/$MODEL_NAME}"
HF_HOME="${HF_HOME:-$PROJECT_DIR/.hf_cache}"
PYTHONUSERBASE="${PYTHONUSERBASE:-$PROJECT_DIR/.python_userbase}"

mkdir -p "$PROJECT_DIR/qwen_models" "$PROJECT_DIR/.hf_cache" "$PROJECT_DIR/.python_userbase" "$PROJECT_DIR/mcminer/job_logs"
cd "$PROJECT_DIR"

export MODEL_ID
export MODEL_DIR
export HF_HOME
export HF_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HF_HOME/transformers"
export HF_HUB_ENABLE_HF_TRANSFER=1
export PYTHONUSERBASE
export PATH="$PYTHONUSERBASE/bin:$PATH"

echo "Job: $SLURM_JOB_ID"
echo "Model: $MODEL_ID"
echo "Destination: $MODEL_DIR"
echo "HF_HOME: $HF_HOME"
echo "Start: $(date)"

python - <<'PY'
import importlib.util
import subprocess
import sys

missing = [pkg for pkg in ("huggingface_hub",) if importlib.util.find_spec(pkg) is None]
if missing:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "huggingface_hub[hf_transfer]"])
PY

python - <<'PY'
import os
from huggingface_hub import snapshot_download

model_id = os.environ["MODEL_ID"]
model_dir = os.environ["MODEL_DIR"]
token = os.environ.get("HF_TOKEN") or None

snapshot_download(
    repo_id=model_id,
    local_dir=model_dir,
    local_dir_use_symlinks=False,
    token=token,
    ignore_patterns=["*.msgpack", "*.h5", "*.ot", "*.onnx", "*.tflite"],
)
PY

echo "Downloaded size:"
du -sh "$MODEL_DIR"
echo "End: $(date)"
