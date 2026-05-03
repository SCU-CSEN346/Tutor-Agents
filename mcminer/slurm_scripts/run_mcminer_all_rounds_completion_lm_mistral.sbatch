#!/bin/bash
#SBATCH --job-name=clm_all_rounds
#SBATCH --partition=gpu
#SBATCH --gres=gpu:volta:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=02:00:00
#SBATCH --output=mcminer/job_logs/run_mcminer_all_rounds_completion_lm_mistral-%j.out
#SBATCH --error=mcminer/job_logs/run_mcminer_all_rounds_completion_lm_mistral-%j.err

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

mkdir -p mcminer/job_logs mcminer/results/mcminer_all_rounds_completion_lm_mistral

python mcminer/src/prepare_completion_lm_mcminer_input.py \
  --clean-output-dir \
  --completion-file-list mcminer/selected_mcminer_completion_lm_all_rounds_paths.txt \
  --output-dir mcminer/dataset/mcminer_all_rounds_completion_lm_student_codes \
  --problems-file mcminer/dataset/mcminer_all_rounds_completion_lm_problems_processed.json

cd mcminer

python src/run_infer_misc.py \
  --llm vllm \
  --vllm-model /WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2 \
  --template zeroshot-no-reasoning \
  --input-dir dataset/mcminer_all_rounds_completion_lm_student_codes \
  --problems-file dataset/mcminer_all_rounds_completion_lm_problems_processed.json \
  --output-dir results/mcminer_all_rounds_completion_lm_mistral \
  --use-batch
