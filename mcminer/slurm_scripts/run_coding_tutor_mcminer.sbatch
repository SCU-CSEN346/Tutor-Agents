#!/bin/bash
#SBATCH --job-name=ct_mcminer
#SBATCH --partition=gpu
#SBATCH --gres=gpu:volta:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=01:00:00
#SBATCH --output=mcminer/job_logs/run_coding_tutor_mcminer-%j.out
#SBATCH --error=mcminer/job_logs/run_coding_tutor_mcminer-%j.err

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

mkdir -p mcminer/job_logs mcminer/results/coding_tutor_mistral_full

python mcminer/src/prepare_coding_tutor_mcminer_input.py

cd mcminer

python src/run_infer_misc.py \
  --llm vllm \
  --vllm-model /WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2 \
  --template zeroshot-no-reasoning \
  --input-dir dataset/coding_tutor_student_codes \
  --problems-file dataset/coding_tutor_problems_processed.json \
  --output-dir results/coding_tutor_mistral_full \
  --use-batch
