#!/bin/bash
# =================================================================
# Coding-Tutor HPC: Run Dialogue Simulation (API Mode — Groq)
# =================================================================
# Runs tutoring simulation with separate models via Groq API:
#   - Tutor:     Llama 3.3 70B (powerful, like GPT-4 in original paper)
#   - Student:   Llama 3 8B  (weaker, simulates student)
#   - Moderator: Llama 3 8B  (lightweight role)
#
# Prerequisites:
#   1. Prompt data available: prompt/prompt_elements_final.jsonl
#   2. API key set: export HF_TOKEN=your_key
#
# Usage:
#   HF_TOKEN=your_token bash scripts/hpc/run_dialogue_hpc.sh
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
cd "$PROJECT_DIR"

# --- API Configuration (HuggingFace) ---
HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running (get one at huggingface.co/settings/tokens)}"
HF_API_ENDPOINT="https://router.huggingface.co/v1"

# Model assignments
TUTOR_MODEL="${TUTOR_MODEL:-meta-llama/Llama-3.3-70B-Instruct}"     # 70B = stronger tutor
STUDENT_MODEL="${STUDENT_MODEL:-meta-llama/Meta-Llama-3-8B-Instruct}"    # 8B = weaker student

# --- Experiment Configuration ---
tutor_setting="vanilla"

# Use full dataset (all 100 tasks)
prompt_element_file="$PROJECT_DIR/prompt/prompt_elements_final.jsonl"
output_dir="$PROJECT_DIR/output/dialogue"

# Student levels to simulate
student_levels=(low_level med_level high_level)

RESULTS_FILE="$output_dir/dialogue_results.txt"
mkdir -p "$output_dir"

echo "================================================================="
echo "  Coding-Tutor Dialogue Simulation (Hugging Face API)"
echo "================================================================="
echo "  Tutor model:    $TUTOR_MODEL"
echo "  Student model:  $STUDENT_MODEL"
echo "  API endpoint:   $HF_API_ENDPOINT"
echo "  Prompt file:    $prompt_element_file"
echo "  Output dir:     $output_dir"
echo "  Start:          $(date)"
echo ""

# Pre-flight checks
if [ ! -f "$prompt_element_file" ]; then
    echo "❌ Subset prompt file not found: $prompt_element_file"
    echo "   Run: python scripts/hpc/create_subset.py --folds 0 1 --output_dir hpc_subset"
    exit 1
fi

NUM_TASKS=$(wc -l < "$prompt_element_file")
echo "  ✓ Prompt file: $NUM_TASKS tasks"

# Test API connectivity
echo "  Testing Hugging Face API connectivity..."
python3 -c "
from openai import OpenAI
client = OpenAI(api_key='$HF_TOKEN', base_url='$HF_API_ENDPOINT')
models = client.models.list()
available = [m.id for m in models.data]
print('  ✓ API connected. Models:', [m for m in available if 'llama' in m.lower()][:5])
" 2>/dev/null || echo "  ⚠  Could not verify API (will try anyway)"
echo ""

# Initialize results
echo "Dialogue Simulation Results — Coding-Tutor (Groq API)" > "$RESULTS_FILE"
echo "Started: $(date)" >> "$RESULTS_FILE"
echo "Tutor: $TUTOR_MODEL" >> "$RESULTS_FILE"
echo "Student: $STUDENT_MODEL" >> "$RESULTS_FILE"
echo "Tasks: $NUM_TASKS" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

STEP=1
TOTAL=${#student_levels[@]}

for level in "${student_levels[@]}"; do
    echo "================================================================="
    echo "  [$STEP/$TOTAL] Simulating $level student dialogues"
    echo "  Started: $(date '+%H:%M:%S')"
    echo "================================================================="

    START_SEC=$SECONDS

    python traver/run_base.py \
        --tutor_setting "$tutor_setting" \
        --prompt_element_file "$prompt_element_file" \
        --output_dir "$output_dir" \
        --tutor_model_name_or_path "$TUTOR_MODEL" \
        --student_model_name_or_path "$STUDENT_MODEL" \
        --student_setting "$level" \
        --vllm_api_key "$HF_TOKEN" \
        --vllm_endpoint_tutor "$HF_API_ENDPOINT" \
        --vllm_endpoint_student "$HF_API_ENDPOINT" \
        --show_description false \
        --show_message false \
        2>&1 | tee "$output_dir/dialogue_${level}.log"

    ELAPSED=$((SECONDS - START_SEC))
    echo "$level: completed in ${ELAPSED}s" >> "$RESULTS_FILE"
    echo "  ✓ $level done in ${ELAPSED}s"

    STEP=$((STEP + 1))
done

echo "" >> "$RESULTS_FILE"
echo "Completed: $(date)" >> "$RESULTS_FILE"

echo ""
echo "================================================================="
echo "  ALL DIALOGUE SIMULATIONS COMPLETE ✅"
echo "================================================================="
echo "  Results: $RESULTS_FILE"
echo "  Logs:    $output_dir/dialogue_*.log"
echo "  Output:  $output_dir/$tutor_setting/"
