#!/bin/bash
#SBATCH --job-name=all_clm_mcminer
#SBATCH --partition=gpu
#SBATCH --gres=gpu:volta:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=mcminer/job_logs/run_all_completion_lm_mcminer-%j.out
#SBATCH --error=mcminer/job_logs/run_all_completion_lm_mcminer-%j.err

set -euo pipefail

cd /WAVE/projects2/CSEN-346-Sp26/Group2

module purge
module load Python/3.12.3-GCCcore-14.2.0
module load CUDA/12.6.2

export PYTHONUSERBASE=/WAVE/projects2/CSEN-346-Sp26/Group2/.python_userbase
export PATH="$PYTHONUSERBASE/bin:$PATH"
export PYTHONPATH="/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer:$PYTHONPATH"
export HF_HOME=/WAVE/projects2/CSEN-346-Sp26/Group2/.hf_cache
export TRANSFORMERS_CACHE="$HF_HOME"
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export LD_LIBRARY_PATH="$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia/cuda_runtime/lib:$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia/cuda_nvrtc/lib:$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia/cublas/lib:$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia/cudnn/lib:$PYTHONUSERBASE/lib/python3.12/site-packages/nvidia/nccl/lib:$LD_LIBRARY_PATH"

mkdir -p mcminer/job_logs mcminer/results/all_completion_lm_mistral_latest

python mcminer/src/prepare_completion_lm_mcminer_input.py \
  --discover-all-latest \
  --clean-output-dir \
  --output-dir mcminer/dataset/all_completion_lm_student_codes \
  --problems-file mcminer/dataset/all_completion_lm_problems_processed.json

cd mcminer

python src/run_infer_misc.py \
  --llm vllm \
  --vllm-model /WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2 \
  --template zeroshot-no-reasoning \
  --input-dir dataset/all_completion_lm_student_codes \
  --problems-file dataset/all_completion_lm_problems_processed.json \
  --output-dir results/all_completion_lm_mistral_latest \
  --use-batch
