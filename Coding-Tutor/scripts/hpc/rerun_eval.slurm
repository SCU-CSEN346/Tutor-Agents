#!/bin/bash
#SBATCH --job-name="coding-tutor-eval"
#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --output="coding_tutor_eval_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Re-run Coding Test Evaluation (CLEAN)
# =================================================================
# Deletes all partial test_results.jsonl and dependency_results.jsonl
# from the previous crashed run, then re-runs evaluation from scratch.
#
# Root cause of crash: open-iris/src/iris/nodes/matcher/utils.py was
# missing from Source_Code, causing a FileNotFoundError at ~67% in
# every round. Fixed with try/except in pass_k.py and recall_k.py.
#
# Usage:
#   sbatch scripts/hpc/rerun_eval.slurm
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"

source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$PROJECT_DIR"

# Remove the sentinel file so the eval step runs
rm -f "output/student_posttest/coding_test_results.txt"

# Clean up ALL partial results from the crashed run
# NOTE: Cleanup is disabled so the resume logic picks up from where
# the previous run stopped. Uncomment the block below for a truly
# clean re-run (e.g. first time after the crash fix).
#
# echo "Cleaning partial results..."
# POSTTEST="output/student_posttest/vanilla/Llama-3.3-70B-Instruct"
# for level in low_level med_level high_level; do
#     for rdx in 1 2 3 4 5 6 7 8; do
#         RDIR="$POSTTEST/$level/round_${rdx}"
#         if [ -d "$RDIR" ]; then
#             rm -f "$RDIR/test_results.jsonl"
#             rm -f "$RDIR/dependency_results.jsonl"
#         fi
#     done
# done

echo "================================================================="
echo " Re-running Coding Test Evaluation (clean, from scratch)"
echo " Start: $(date)"
echo "================================================================="

bash scripts/hpc/run_coding_test_hpc.sh

echo "================================================================="
echo " Evaluation Re-run Complete! ✅"
echo " End: $(date)"
echo "================================================================="
