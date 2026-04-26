#!/bin/bash
# =================================================================
# Clean up old evaluation results from eval_by_project.slurm
# Run this on HPC before re-submitting eval_by_project.slurm
#
# Usage:
#   bash scripts/hpc/clean_eval_results.sh
# =================================================================

GROUP_DIR="/WAVE/projects/CSEN-346-Sp26/Group2"
REPO_DIR="$GROUP_DIR/Coding-Tutor"
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
POSTTEST_BASE="$REPO_DIR/output/student_posttest/traver/$TUTOR_MODEL_DIR"

echo "================================================================="
echo "  Cleaning old eval_by_project results"
echo "================================================================="

DELETED=0

for level in low_level med_level high_level; do
    for rdx in 1 2 3 4 5 6 7 8; do
        ROUND_DIR="$POSTTEST_BASE/$level/round_${rdx}"

        if [ -f "$ROUND_DIR/test_results.jsonl" ]; then
            echo "  🗑️  Removing $level/round_${rdx}/test_results.jsonl"
            rm -f "$ROUND_DIR/test_results.jsonl"
            DELETED=$((DELETED + 1))
        fi

        if [ -f "$ROUND_DIR/dependency_results.jsonl" ]; then
            echo "  🗑️  Removing $level/round_${rdx}/dependency_results.jsonl"
            rm -f "$ROUND_DIR/dependency_results.jsonl"
            DELETED=$((DELETED + 1))
        fi
    done
done

# Clean eval_results directory
if [ -d "$REPO_DIR/eval_results" ]; then
    echo "  🗑️  Removing eval_results/ directory"
    rm -rf "$REPO_DIR/eval_results"
    DELETED=$((DELETED + 1))
fi

# Clean leftover venv
if [ -d "$REPO_DIR/.eval_venv" ]; then
    echo "  🗑️  Removing .eval_venv/ directory"
    rm -rf "$REPO_DIR/.eval_venv"
    DELETED=$((DELETED + 1))
fi

echo ""
echo "  ✅ Cleaned $DELETED items. Ready for fresh eval_by_project.slurm run."
echo "================================================================="
