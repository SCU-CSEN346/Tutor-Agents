#!/bin/bash
# =================================================================
# Coding-Tutor HPC: Code Generation (API Mode — Groq)
# =================================================================
# Runs post-test code generation using Llama-3-8B via Groq API.
# (Student model generates code, matching the student's capabilities)
#
# Prerequisites:
#   1. Dialogue simulation completed (output/dialogue/)
#   2. API key set: export HF_TOKEN=your_token
#
# Usage:
#   HF_TOKEN=your_token bash scripts/hpc/run_codegen_hpc.sh
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
cd "$PROJECT_DIR"

# --- API Configuration (HuggingFace) ---
HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running}"
HF_API_ENDPOINT="https://router.huggingface.co/v1"

# Code generation uses the student model (8B)
STUDENT_MODEL="${STUDENT_MODEL:-meta-llama/Meta-Llama-3-8B-Instruct}"
# Tutor model name for directory structure (stripping provider prefix)
TUTOR_MODEL_DIR="${TUTOR_MODEL_DIR:-Llama-3.3-70B-Instruct}"

# --- Experiment Configuration ---
tutor_setting="vanilla"
student_levels=(low_level med_level high_level)

prompt_element_file="$PROJECT_DIR/prompt/prompt_elements_final.jsonl"
prompt_base_dir="$PROJECT_DIR/prompt/student_posttest"
output_base_dir="$PROJECT_DIR/output/student_posttest"
output_dir="$PROJECT_DIR/output/dialogue"

rounds=(1 2 3 4 5 6 7 8)
max_interaction_round=8
max_cognitive_load=60
n=10

RESULTS_FILE="$output_base_dir/codegen_results.txt"
mkdir -p "$output_base_dir"

echo "================================================================="
echo "  Coding-Tutor Code Generation (Hugging Face API)"
echo "================================================================="
echo "  Student model: $STUDENT_MODEL"
echo "  Endpoint:      $HF_API_ENDPOINT"
echo "  Setting:       $tutor_setting / $TUTOR_MODEL_DIR"
echo "  Levels:        ${student_levels[*]}"
echo "  Rounds:        ${rounds[*]}"
echo "  Start:         $(date)"
echo ""

if [ ! -f "$prompt_element_file" ]; then
    echo "❌ Subset prompt file not found: $prompt_element_file"
    exit 1
fi
echo "  ✓ Subset data found"

echo ""
echo "Codegen Results — Coding-Tutor HPC (Groq API)" > "$RESULTS_FILE"
echo "Started: $(date)" >> "$RESULTS_FILE"
echo "Student model: $STUDENT_MODEL" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Step 1: Create prompts
echo "================================================================="
echo "  Step 1: Creating post-test prompts"
echo "================================================================="
for level in "${student_levels[@]}"; do
    echo "  Creating prompts: $level"
    PYTHONPATH="$PROJECT_DIR/traver" python -m utils.make_prompt --student_posttest \
        --prompt_element_file "$prompt_element_file" \
        --simulated_file "$output_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl" \
        --output_dir "$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level" \
        --student_level "$level" \
        --max_interaction_round $max_interaction_round \
        --max_cognitive_load $max_cognitive_load \
        2>&1 | tee -a "$output_base_dir/make_prompt_${level}.log"
done
echo "  ✓ Prompts created"

# Step 2: Run code generation via API
echo ""
echo "================================================================="
echo "  Step 2: Running code generation (Hugging Face API)"
echo "================================================================="
for level in "${student_levels[@]}"; do
    for rdx in "${rounds[@]}"; do
        PROMPT_FILE="$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/prompt_round_${rdx}.jsonl"
        if [ ! -f "$PROMPT_FILE" ]; then
            echo "  ⚠  Skipping round $rdx for $level (no prompt file)"
            continue
        fi

        echo "  Generating: $level / round $rdx"
        START_SEC=$SECONDS

        PYTHONPATH="$PROJECT_DIR/traver" python -m utils.LM_inference_api \
            --model_name_or_path "$STUDENT_MODEL" \
            --api_base "$HF_API_ENDPOINT" \
            --api_key "$HF_TOKEN" \
            --prompt_file "$PROMPT_FILE" \
            --output_dir "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}" \
            --decoding "sampling" \
            --N $n \
            2>&1 | tee -a "$output_base_dir/codegen_${level}_round${rdx}.log"

        ELAPSED=$((SECONDS - START_SEC))
        echo "  codegen $level round-$rdx: ${ELAPSED}s" >> "$RESULTS_FILE"
    done
done
echo "  ✓ Code generation complete"

# Step 3: Process completions
echo ""
echo "================================================================="
echo "  Step 3: Processing completions"
echo "================================================================="
for level in "${student_levels[@]}"; do
    for rdx in "${rounds[@]}"; do
        COMP_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
        if [ ! -f "$COMP_FILE" ]; then
            continue
        fi
        echo "  Processing: $level / round $rdx"
        PYTHONPATH="$PROJECT_DIR/traver" python -m utils.process_completion \
            --completion_file "$COMP_FILE" \
            --output_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
    done
done

echo "" >> "$RESULTS_FILE"
echo "Completed: $(date)" >> "$RESULTS_FILE"

echo ""
echo "================================================================="
echo "  CODE GENERATION COMPLETE ✅"
echo "================================================================="
echo "  Results: $RESULTS_FILE"
echo "  Output:  $output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/"
