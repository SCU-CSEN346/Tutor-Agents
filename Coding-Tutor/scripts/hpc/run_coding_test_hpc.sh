#!/bin/bash
# =================================================================
# Coding-Tutor HPC: Coding Test Evaluation (Subset)
# =================================================================
# Runs recall@k and pass@k on subset EvoCodeBench data.
#
# Prerequisites:
#   1. Code generation completed: bash scripts/hpc/run_codegen_hpc.sh
#   2. EvoCodeBench subset: Source_Code + Dependency_Data in hpc_subset/
#
# Usage:
#   bash scripts/hpc/run_coding_test_hpc.sh
# =================================================================

set -e

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
cd "$PROJECT_DIR"

# --- Configuration ---
# EvoCodeBench paths — downloaded directly by setup_evocodebench.sh
ECB_ROOT="$PROJECT_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"

# Use Coding-Tutor's metadata.jsonl (namespaces must match completion files)
# Falls back to data.jsonl if metadata.jsonl not present
if [ -f "$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl" ]; then
    metadata_file="$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl"
elif [ -f "$ECB_ROOT/metadata.jsonl" ]; then
    metadata_file="$ECB_ROOT/metadata.jsonl"
else
    metadata_file="$ECB_ROOT/data.jsonl"
    echo "  ⚠  Using data.jsonl — namespaces may not match completions!"
fi
prompt_element_file="$PROJECT_DIR/prompt/prompt_elements_final.jsonl"
prompt_base_dir="$PROJECT_DIR/prompt/student_posttest"
output_base_dir="$PROJECT_DIR/output/student_posttest"

tutor_settings=(vanilla)
# Notice: Codegen saves to the TUTOR model string in this setup
models=(Llama-3.3-70B-Instruct)
student_levels=(low_level med_level high_level)
k="1,3,5,10"
n=10

RESULTS_FILE="$output_base_dir/coding_test_results.txt"

echo "================================================================="
echo "  Coding-Tutor Coding Test Evaluation (Full 100 Tasks)"
echo "================================================================="
echo "  EvoCodeBench: $ECB_ROOT"
echo "  Metadata:     $metadata_file"
echo "  Start:        $(date)"
echo ""

# Pre-flight checks
if [ ! -d "$Source_Code_Root" ]; then
    echo "❌ Source_Code not found: $Source_Code_Root"
    echo "   Run: bash scripts/hpc/setup_evocodebench.sh"
    exit 1
fi
echo "  ✓ Source_Code found ($(ls "$Source_Code_Root" | wc -l) projects)"

if [ ! -d "$Dependency_Root" ]; then
    echo "  ⚠  Dependency_Data not found — recall@k may fail."
fi

if [ ! -f "$metadata_file" ]; then
    echo "❌ Metadata not found: $metadata_file"
    exit 1
fi
echo "  ✓ Metadata found"

echo ""
echo "Coding Test Results — Coding-Tutor HPC" > "$RESULTS_FILE"
echo "Started: $(date)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

for setting in "${tutor_settings[@]}"; do
    for model in "${models[@]}"; do
        for level in "${student_levels[@]}"; do
            for rdx in {1..8}; do
                COMP_FILE="$output_base_dir/$setting/$model/$level/round_${rdx}/completion.jsonl"
                if [ ! -f "$COMP_FILE" ]; then
                    echo "  ⚠  Skipping: $setting/$model/$level/round_$rdx (no completion file)"
                    continue
                fi

                echo "================================================================="
                echo "  Testing: $setting / $model / $level / round_$rdx"
                echo "================================================================="

                START_SEC=$SECONDS

            # recall@k
            echo "  Running recall@k..."
            PYTHONPATH="$PROJECT_DIR/traver:$PROJECT_DIR/traver/parser" python -m utils.check_source_code "$Source_Code_Root" 2>/dev/null || true
            PYTHONPATH="$PROJECT_DIR/traver:$PROJECT_DIR/traver/parser" python -m parser.recall_k \
                --output_file "$COMP_FILE" \
                --log_file "$output_base_dir/$setting/$model/$level/round_${rdx}/dependency_results.jsonl" \
                --data_file "$metadata_file" \
                --source_code_root "$Source_Code_Root" \
                --dependency_data_root "$Dependency_Root" \
                --k "$k" \
                2>&1 | tee -a "$output_base_dir/recall_${setting}_${model}_${level}.log"

            # pass@k
            echo "  Running pass@k..."
            PYTHONPATH="$PROJECT_DIR/traver" python -m utils.check_source_code "$Source_Code_Root" 2>/dev/null || true
            PYTHONPATH="$PROJECT_DIR/traver" python -m parser.pass_k \
                --output_file "$COMP_FILE" \
                --log_file "$output_base_dir/$setting/$model/$level/round_${rdx}/test_results.jsonl" \
                --data_file "$metadata_file" \
                --source_code_root "$Source_Code_Root" \
                --k "$k" \
                --n "$n" \
                2>&1 | tee -a "$output_base_dir/pass_${setting}_${model}_${level}_round${rdx}.log"

                ELAPSED=$((SECONDS - START_SEC))
                echo "  $setting/$model/$level/round_$rdx: ${ELAPSED}s" >> "$RESULTS_FILE"
                echo "  ✓ $level/round_$rdx done in ${ELAPSED}s"
            done
        done
    done
done

echo "" >> "$RESULTS_FILE"
echo "Completed: $(date)" >> "$RESULTS_FILE"

echo ""
echo "================================================================="
echo "  CODING TESTS COMPLETE ✅"
echo "================================================================="
echo "  Results: $RESULTS_FILE"
echo "  Logs:    $output_base_dir/recall_*.log, $output_base_dir/pass_*.log"
