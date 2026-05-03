#!/bin/bash
#SBATCH --job-name=mcminer_m60_sf
#SBATCH --partition=gpu
#SBATCH --gres=gpu:volta:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=02:00:00
#SBATCH --output=mcminer/job_logs/run_mcminer_m_60_completion_lm_mistral_s_filtered_2codes-%j.out
#SBATCH --error=mcminer/job_logs/run_mcminer_m_60_completion_lm_mistral_s_filtered_2codes-%j.err

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

mkdir -p mcminer/job_logs

python mcminer/src/create_mcminer_m_s_filtered_input.py \
  --clean-output-dir \
  --single-predictions mcminer/results/mcminer_60_completion_lm_mistral/predictions.json \
  --source-input-dir mcminer/dataset/mcminer_60_completion_lm_student_codes \
  --output-dir mcminer/dataset/mcminer_60_completion_lm_student_codes_s_filtered \
  --filter-report mcminer/results/mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192/filter_report.json \
  --min-repeat-count 2

cd mcminer

python src/run_infer_misc_multi.py \
  --llm vllm \
  --vllm-model /WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2 \
  --vllm-max-model-len 8192 \
  --template zeroshot-no-reasoning-multi \
  --input-dir dataset/mcminer_60_completion_lm_student_codes_s_filtered \
  --problems-file dataset/mcminer_60_completion_lm_problems_processed.json \
  --output-dir results/mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192 \
  --min-codes-for-processing 2 \
  --min-codes-per-group 2 \
  --max-codes-per-group 2 \
  --bags-per-misconception 1 \
  --correct-bags-ratio 0 \
  --max-tokens 2000 \
  --use-batch
