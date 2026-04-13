#!/bin/bash
# =================================================================
# Coding-Tutor HPC: Verifier Training (2 Folds)
# =================================================================
# Trains the turn-by-turn verifier using DeepSpeed + LoRA.
#
# NOTE: Verifier training requires a LOCAL model for fine-tuning.
# Since we use API for inference, you need to download a base model
# for training only. This script will download it if not present.
#
# Only trains on 2 cross-validation folds (part0, part1).
#
# Prerequisites:
#   1. Verifier data prepared from dialogue output
#
# Usage:
#   bash scripts/hpc/run_verifier_hpc.sh
# =================================================================

set -e

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
cd "$PROJECT_DIR"

# --- Configuration ---
MODEL_DIR="$PROJECT_DIR/models"
pretrained_model_name_or_path="$MODEL_DIR/Meta-Llama-3.1-8B-Instruct"
data_dir="$PROJECT_DIR/output/verifier_data"
output_dir="$PROJECT_DIR/output/verifier_model"
RESULTS_FILE="$output_dir/training_results.txt"

# Only train on 2 folds
eval_parts=(part0 part1)

mkdir -p "$output_dir"

echo "================================================================="
echo "  Coding-Tutor Verifier Training (HPC — 2 Folds)"
echo "================================================================="
echo "  Base model:  $(basename $pretrained_model_name_or_path)"
echo "  Data dir:    $data_dir"
echo "  Output dir:  $output_dir"
echo "  Folds:       ${eval_parts[*]}"
echo "  GPU:         $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'unknown')"
echo "  Start:       $(date)"
echo ""

# Check if base model exists; if not, download it
if [ ! -d "$pretrained_model_name_or_path" ]; then
    echo "  ⚠  Base model not found locally. Downloading for training..."
    echo "     (This is only needed for verifier fine-tuning, not inference)"
    mkdir -p "$MODEL_DIR"
    HF_TOKEN="${HF_TOKEN:-}"
    if [ -n "$HF_TOKEN" ]; then
        hf login --token "$HF_TOKEN"
    fi
    hf download meta-llama/Llama-3.1-8B-Instruct \
        --local-dir "$pretrained_model_name_or_path" \
        --local-dir-use-symlinks False
    echo "  ✓ Base model downloaded"
fi
echo "  ✓ Base model found"

if [ ! -d "$data_dir" ]; then
    echo "❌ Verifier data not found: $data_dir"
    echo "   Run prepare_verifier_data.sh first, or use pre-computed data."
    exit 1
fi

# Count data files
DATA_FILES=$(ls "$data_dir"/verifier_data_part*.jsonl 2>/dev/null | wc -l)
echo "  ✓ Found $DATA_FILES data partition files"
echo ""

# Initialize results
echo "Verifier Training Results — Coding-Tutor (HPC)" > "$RESULTS_FILE"
echo "Started: $(date)" >> "$RESULTS_FILE"
echo "Base model: $(basename $pretrained_model_name_or_path)" >> "$RESULTS_FILE"
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'unknown')" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

STEP=1
TOTAL=${#eval_parts[@]}

for part in "${eval_parts[@]}"; do
    echo "================================================================="
    echo "  [$STEP/$TOTAL] Training with eval on $part"
    echo "  Started: $(date '+%H:%M:%S')"
    echo "================================================================="
    STEP=$((STEP + 1))

    PART_OUTPUT="$output_dir/$part"
    mkdir -p "$PART_OUTPUT"

    START_SEC=$SECONDS

    deepspeed --master_port=29400 --include="localhost:0" \
        traver/train_verifier.py \
        --data_dir "$data_dir" \
        --eval_part "$part" \
        --pretrained_model_name_or_path "$pretrained_model_name_or_path" \
        --output_dir "$PART_OUTPUT" \
        --max_length 2200 \
        --per_device_train_batch_size 2 \
        --gradient_accumulation_steps 8 \
        --fp16 true \
        --bf16 false \
        --learning_rate 1e-5 \
        --num_train_epochs 3 \
        --logging_steps 10 \
        --eval_steps 500 \
        --save_steps 100 \
        --deepspeed config/deepspeed_config_s2.json \
        2>&1 | tee "$output_dir/train_${part}.log"

    ELAPSED=$((SECONDS - START_SEC))

    EVAL_LOSS=$(grep "eval_loss" "$output_dir/train_${part}.log" | tail -1 || echo "N/A")
    echo "$part: ${ELAPSED}s | $EVAL_LOSS" >> "$RESULTS_FILE"
    echo "  ✓ $part training done in ${ELAPSED}s"

    echo ""
    echo "  Results so far:"
    cat "$RESULTS_FILE"
    echo ""
done

echo "" >> "$RESULTS_FILE"
echo "Completed: $(date)" >> "$RESULTS_FILE"

echo ""
echo "================================================================="
echo "  VERIFIER TRAINING COMPLETE ✅"
echo "================================================================="
echo "  Results:     $RESULTS_FILE"
echo "  Logs:        $output_dir/train_*.log"
echo "  Checkpoints: $output_dir/part*/"
echo ""
echo "  Note: You can delete models/ after training to free ~16GB"
echo "  Model size:"
du -sh "$output_dir"/*/ 2>/dev/null
