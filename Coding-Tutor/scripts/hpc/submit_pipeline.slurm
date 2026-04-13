#!/bin/bash
#SBATCH --job-name="coding-tutor"
#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --output="coding_tutor_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Full API Pipeline Submission Script
# =================================================================
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/submit_pipeline.slurm
#
# Check status:
#   squeue -u $USER
#
# View output live:
#   tail -f slurm_logs/pipeline_<job_id>.out
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"

source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$PROJECT_DIR"

# 2. Run Dialogue (Takes ~4 - 6 hours for 100 tasks)
echo ""
echo "[2/4] Running Dialogue Simulation (100 tasks)..."
if [ -f "output/dialogue/dialogue_results.txt" ]; then
    echo "  ✓ Dialogue results found. Skipping simulation..."
else
    bash scripts/hpc/run_dialogue_hpc.sh
fi

# 3. Run Code Generation (Takes ~2 - 3 hours for 100 tasks)
echo ""
echo "[3/4] Running Code Generation (100 tasks)..."
if [ -f "output/student_posttest/codegen_results.txt" ]; then
    echo "  ✓ Code generation results found. Skipping..."
else
    bash scripts/hpc/run_codegen_hpc.sh
fi

# 4. Run Coding Test Eval (Takes ~2 - 4 hours for 100 tasks)
echo ""
echo "[4/4] Running Coding Evaluations (100 tasks)..."
if [ -f "output/student_posttest/coding_test_results.txt" ]; then
    echo "  ✓ Coding evaluation results found. Skipping..."
else
    bash scripts/hpc/run_coding_test_hpc.sh
fi

# (Optional offline evaluations commented out as they expect hardcoded pretest outputs)
# python scripts/eval/eval_pretest.py
# python scripts/eval/eval_TOR.py \
#     --pretest_dir output/student_pretest \
#     --posttest_dir output/student_posttest

echo "================================================================="
echo " Pipeline Complete! ✅"
echo " End: $(date)"
echo "================================================================="
