#!/bin/bash
#SBATCH --job-name=mcminer_gemini_s60
#SBATCH --partition=cpu
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH --output=mcminer/job_logs/run_mcminer_60_completion_lm_gemini_flash_no_reasoning-%j.out
#SBATCH --error=mcminer/job_logs/run_mcminer_60_completion_lm_gemini_flash_no_reasoning-%j.err

set -euo pipefail

cd /WAVE/projects2/CSEN-346-Sp26/Group2

module purge
module load Python/3.12.3-GCCcore-14.2.0

export PYTHONUSERBASE=/WAVE/projects2/CSEN-346-Sp26/Group2/.python_userbase
export PATH="$PYTHONUSERBASE/bin:$PATH"
export PYTHONPATH="/WAVE/projects2/CSEN-346-Sp26/Group2/mcminer:$PYTHONPATH"

if [ -f mcminer/.env ]; then
  set -a
  source mcminer/.env
  set +a
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY is not set. Export it before submitting this job."
  exit 2
fi

mkdir -p mcminer/job_logs mcminer/results/mcminer_60_completion_lm_gemini_2_5_flash_no_reasoning

python mcminer/src/prepare_completion_lm_mcminer_input.py \
  --clean-output-dir \
  --completion-file-list mcminer/selected_completion_lm_60_paths.txt \
  --output-dir mcminer/dataset/mcminer_60_completion_lm_student_codes \
  --problems-file mcminer/dataset/mcminer_60_completion_lm_problems_processed.json

cd mcminer

python src/run_infer_misc.py \
  --llm gemini \
  --gemini-model gemini-2.5-flash \
  --template zeroshot-no-reasoning \
  --input-dir dataset/mcminer_60_completion_lm_student_codes \
  --problems-file dataset/mcminer_60_completion_lm_problems_processed.json \
  --output-dir results/mcminer_60_completion_lm_gemini_2_5_flash_no_reasoning \
  --use-batch \
  --checkpoint-every 25
