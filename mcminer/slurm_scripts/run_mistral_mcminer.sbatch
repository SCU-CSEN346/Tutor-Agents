#!/bin/bash
#SBATCH --job-name=run_mistral_mcminer
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --gres=gpu:1
#SBATCH --time=02:00:00
#SBATCH --output=/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer/job_logs/run_mistral_mcminer-%j.out
#SBATCH --error=/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer/job_logs/run_mistral_mcminer-%j.err

set -euo pipefail

PROJECT_DIR="/WAVE/projects2/CSEN-346-Sp26/Group2"
MCMINER_DIR="$PROJECT_DIR/mcminer"
MODEL_DIR="${MODEL_DIR:-$PROJECT_DIR/models/Mistral-7B-Instruct-v0.2}"
OUTPUT_DIR="${OUTPUT_DIR:-$MCMINER_DIR/results/mistral_7b_full}"

mkdir -p "$MCMINER_DIR/job_logs" "$OUTPUT_DIR" "$PROJECT_DIR/.hf_cache"
cd "$MCMINER_DIR"

export PYTHONUSERBASE="${PYTHONUSERBASE:-$PROJECT_DIR/.python_userbase}"
export PATH="$PYTHONUSERBASE/bin:$PATH"
NVIDIA_SITE="$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia"
for lib_dir in "$NVIDIA_SITE"/*/lib; do
  if [ -d "$lib_dir" ]; then
    export LD_LIBRARY_PATH="$lib_dir:${LD_LIBRARY_PATH:-}"
  fi
done
export HF_HOME="${HF_HOME:-$PROJECT_DIR/.hf_cache}"
export HF_HUB_CACHE="$HF_HOME/hub"
export PYTHONPATH="$MCMINER_DIR:${PYTHONPATH:-}"

echo "Job: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Model dir: $MODEL_DIR"
echo "Output dir: $OUTPUT_DIR"
echo "Start: $(date)"

module purge || true
module load Python/3.12.3-GCCcore-14.2.0 || true
module load CUDA/12.6.2 || true

python --version

python src/run_infer_misc.py \
  --llm vllm \
  --vllm-model "$MODEL_DIR" \
  --template zeroshot-no-reasoning \
  --input-dir dataset/corrupted_codes_best \
  --problems-file dataset/problems_processed.json \
  --output-dir "$OUTPUT_DIR" \
  --use-batch

echo "End: $(date)"
