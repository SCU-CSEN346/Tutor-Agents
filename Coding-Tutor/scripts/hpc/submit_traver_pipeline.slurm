#!/bin/bash
#SBATCH --job-name="coding-tutor-traver"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="coding_tutor_traver_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Full TRAVER Pipeline
# =================================================================
# Runs the complete Traver workflow:
#   1. Prepare verifier training data (from vanilla outputs)
#   2. Download base model (if not cached)
#   3. Train verifier (DeepSpeed + LoRA, needs GPU)
#   4. Run Traver dialogue simulation (with verifier)
#   5. Code generation (async API, same as vanilla)
#   6. Coding test evaluation (pass@k + recall@k)
#
# Prerequisites:
#   - Vanilla pipeline already completed (dialogue + codegen + eval)
#   - HF_TOKEN set for API inference
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/submit_traver_pipeline.slurm
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
PROGRESS_FILE="$PROJECT_DIR/output/traver_progress.txt"

source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

# Load CUDA for DeepSpeed import (it checks CUDA_HOME at import time).
# We use deepspeed_config_s2_nooffload.json to avoid CPUAdam JIT compilation,
# which is where the CUDA 12.2 vs PyTorch's 11.8 mismatch would actually fail.
module load CUDA/12.2.1
export CUDA_HOME="$EBROOTCUDA"

# Fix datasets/pyarrow incompatibility (pin key packages to prevent downgrades)
pip install -q "pyarrow>=14.0,<17.0" "datasets>=2.20.0" "transformers==4.44.2" "tokenizers>=0.19.1"

cd "$PROJECT_DIR"

# --- Helper: log progress to both stdout and progress file ---
log() {
    echo "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$PROGRESS_FILE"
}

fmt_time() {
    local secs=$1
    printf '%dh %dm %ds' $((secs/3600)) $((secs%3600/60)) $((secs%60))
}

# --- Configuration ---
HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running}"
HF_API_ENDPOINT="https://router.huggingface.co/v1"

TUTOR_MODEL="${TUTOR_MODEL:-meta-llama/Llama-3.3-70B-Instruct}"
STUDENT_MODEL="${STUDENT_MODEL:-meta-llama/Meta-Llama-3-8B-Instruct}"
TUTOR_MODEL_DIR="${TUTOR_MODEL_DIR:-Llama-3.3-70B-Instruct}"

# Verifier config
MODEL_DIR="$PROJECT_DIR/models"
VERIFIER_BASE_MODEL="$MODEL_DIR/Meta-Llama-3.1-8B-Instruct"
VERIFIER_DATA_DIR="$PROJECT_DIR/output/verifier_data"
VERIFIER_MODEL_DIR="$PROJECT_DIR/output/verifier_model"

# Experiment config
tutor_setting="traver"
student_levels=(low_level med_level high_level)

mkdir -p "$PROJECT_DIR/output"

# Initialize progress file
cat > "$PROGRESS_FILE" << EOF
================================================================
  TRAVER PIPELINE PROGRESS
  Started: $(date)
================================================================
  Tutor:    $TUTOR_MODEL
  Student:  $STUDENT_MODEL
  GPU:      $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'none')
================================================================

  Step 1/6: Prepare verifier data ......... PENDING
  Step 2/6: Download base model ........... PENDING
  Step 3/6: Train verifier (5 folds) ...... PENDING
  Step 4/6: Traver dialogue simulation .... PENDING
  Step 5/6: Code generation (async) ....... PENDING
  Step 6/6: Coding test evaluation ........ PENDING

================================================================
  DETAILED LOG:
================================================================
EOF

echo "================================================================="
echo "  Coding-Tutor TRAVER Pipeline"
echo "================================================================="
echo "  Tutor model:    $TUTOR_MODEL"
echo "  Student model:  $STUDENT_MODEL"
echo "  GPU:            $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'none')"
echo "  Progress file:  $PROGRESS_FILE"
echo "  Start:          $(date)"
echo "================================================================="

PIPELINE_START=$SECONDS

# =================================================================
# STEP 1: Prepare verifier training data
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 1/6: Preparing verifier training data..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

if [ -f "$VERIFIER_DATA_DIR/verifier_data.jsonl" ]; then
    log "  ✓ SKIP — Verifier data already exists"
else
    mkdir -p "$VERIFIER_DATA_DIR"
    log "  Using vanilla dialogue + posttest results to build training data"
    
    PYTHONPATH="$PROJECT_DIR/traver/verifier" python "$PROJECT_DIR/traver/verifier/preprocess_data.py" \
        --simulation_dir output/dialogue/vanilla \
        --posttest_dir output/student_posttest/vanilla \
        --output_dir "$VERIFIER_DATA_DIR" \
        2>&1 | tee "$VERIFIER_DATA_DIR/preprocess.log"
    
    NUM_SAMPLES=$(wc -l < "$VERIFIER_DATA_DIR/verifier_data.jsonl" 2>/dev/null || echo 0)
    NUM_PARTS=$(ls "$VERIFIER_DATA_DIR"/verifier_data_part*.jsonl 2>/dev/null | wc -l)
    # Count positives vs negatives
    POS=$(python3 -c "import json; data=open('$VERIFIER_DATA_DIR/verifier_data.jsonl'); pos=sum(1 for l in data if json.loads(l)['label']>0); print(pos)" 2>/dev/null || echo '?')
    log "  ✓ DONE — $NUM_SAMPLES training samples ($POS positive), $NUM_PARTS folds ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# STEP 2: Download base model for fine-tuning (if needed)
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 2/6: Checking base model for verifier training..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

if [ -d "$VERIFIER_BASE_MODEL" ]; then
    log "  ✓ SKIP — Base model found at $VERIFIER_BASE_MODEL"
else
    log "  Downloading Meta-Llama-3.1-8B-Instruct (~16GB)..."
    mkdir -p "$MODEL_DIR"
    huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
        --local-dir "$VERIFIER_BASE_MODEL" \
        --token "$HF_TOKEN" \
        2>&1 | tee "$MODEL_DIR/download.log"
    log "  ✓ DONE — Base model downloaded ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# STEP 3: Train verifier (DeepSpeed + LoRA)
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 3/6: Training verifier (5-fold cross-validation)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

eval_parts=(part0 part1 part2 part3 part4)
TRAIN_RESULTS="$VERIFIER_MODEL_DIR/training_results.txt"
mkdir -p "$VERIFIER_MODEL_DIR"

if [ -f "$VERIFIER_MODEL_DIR/part4/pytorch_model.bin" ]; then
    log "  ✓ SKIP — All verifier folds already trained"
else
    echo "Verifier Training Results" > "$TRAIN_RESULTS"
    echo "Started: $(date)" >> "$TRAIN_RESULTS"
    echo "" >> "$TRAIN_RESULTS"

    FOLD_NUM=1
    for part in "${eval_parts[@]}"; do
        PART_OUTPUT="$VERIFIER_MODEL_DIR/$part"
        
        if [ -f "$PART_OUTPUT/pytorch_model.bin" ]; then
            log "  ✓ SKIP — $part already trained (fold $FOLD_NUM/5)"
            FOLD_NUM=$((FOLD_NUM + 1))
            continue
        fi
        
        log "  🔄 Training fold $FOLD_NUM/5 (eval on $part)..."
        mkdir -p "$PART_OUTPUT"
        FOLD_START=$SECONDS

        deepspeed --master_port=29400 --include="localhost:0" \
            traver/train_verifier.py \
            --data_dir "$VERIFIER_DATA_DIR" \
            --eval_part "$part" \
            --pretrained_model_name_or_path "$VERIFIER_BASE_MODEL" \
            --output_dir "$PART_OUTPUT" \
            --max_length 2200 \
            --per_device_train_batch_size 1 \
            --gradient_accumulation_steps 16 \
            --gradient_checkpointing true \
            --fp16 true \
            --bf16 false \
            --learning_rate 1e-5 \
            --num_train_epochs 3 \
            --logging_steps 10 \
            --eval_steps 500 \
            --save_steps 100 \
            --deepspeed config/deepspeed_config_s2_nooffload.json \
            2>&1 | tee "$VERIFIER_MODEL_DIR/train_${part}.log"

        FOLD_ELAPSED=$((SECONDS - FOLD_START))
        echo "  $part: ${FOLD_ELAPSED}s" >> "$TRAIN_RESULTS"
        # Extract final eval loss
        EVAL_LOSS=$(grep -a "eval_loss" "$VERIFIER_MODEL_DIR/train_${part}.log" | tail -1 | grep -oP 'eval_loss.*?[0-9.]+' | grep -oP '[0-9.]+$' || echo 'N/A')
        TRAIN_LOSS=$(grep -a "'loss'" "$VERIFIER_MODEL_DIR/train_${part}.log" | tail -1 | grep -oP "'loss': [0-9.]+" | grep -oP '[0-9.]+' || echo 'N/A')
        log "  ✓ Fold $FOLD_NUM/5 ($part) — train_loss=$TRAIN_LOSS, eval_loss=$EVAL_LOSS ($(fmt_time $FOLD_ELAPSED))"
        FOLD_NUM=$((FOLD_NUM + 1))
    done

    echo "" >> "$TRAIN_RESULTS"
    echo "Completed: $(date)" >> "$TRAIN_RESULTS"
    log "  ✓ DONE — All 5 verifier folds trained ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# STEP 4: Run Traver dialogue simulation (with verifier)
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 4/6: Running Traver dialogue simulation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

TRAVER_OUTPUT="$PROJECT_DIR/output/dialogue"
TRAVER_RESULTS="$TRAVER_OUTPUT/traver_dialogue_results.txt"

EXPECTED_COUNT=$(wc -l < "prompt/prompt_elements_final.jsonl" | xargs)
TRAVER_DONE=true
for level in "${student_levels[@]}"; do
    FILE="$TRAVER_OUTPUT/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl"
    if [ ! -f "$FILE" ] || [ "$(wc -l < "$FILE" | xargs)" -lt "$EXPECTED_COUNT" ]; then
        TRAVER_DONE=false
        break
    fi
done

if $TRAVER_DONE; then
    log "  ✓ SKIP — All Traver dialogues already exist and are complete"
else
    echo "Traver Dialogue Results" > "$TRAVER_RESULTS"
    echo "Started: $(date)" >> "$TRAVER_RESULTS"
    echo "" >> "$TRAVER_RESULTS"

    LEVEL_NUM=1
    for level in "${student_levels[@]}"; do
        OUTPUT_CHECK="$TRAVER_OUTPUT/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl"
        if [ -f "$OUTPUT_CHECK" ] && [ "$(wc -l < "$OUTPUT_CHECK" | xargs)" -ge "$EXPECTED_COUNT" ]; then
            log "  ✓ SKIP — $level dialogues already done and complete ($LEVEL_NUM/3)"
            LEVEL_NUM=$((LEVEL_NUM + 1))
            continue
        fi

        log "  🔄 Simulating $level dialogues ($LEVEL_NUM/3, with verifier)..."
        LEVEL_START=$SECONDS

        python traver/run_traver.py \
            --tutor_setting "$tutor_setting" \
            --prompt_element_file "prompt/prompt_elements_final.jsonl" \
            --output_dir "$TRAVER_OUTPUT" \
            --tutor_model_name_or_path "$TUTOR_MODEL" \
            --student_model_name_or_path "$STUDENT_MODEL" \
            --student_setting "$level" \
            --vllm_api_key "$HF_TOKEN" \
            --vllm_endpoint_tutor "$HF_API_ENDPOINT" \
            --vllm_endpoint_student "$HF_API_ENDPOINT" \
            --verifier_base_model_path "$VERIFIER_BASE_MODEL" \
            --verifier_model_dir "$VERIFIER_MODEL_DIR" \
            --verifier_model_parts "0,1,2,3,4" \
            --use_KT true \
            --show_description false \
            --show_message false \
            2>&1 | tee "$TRAVER_OUTPUT/traver_dialogue_${level}.log"

        LEVEL_ELAPSED=$((SECONDS - LEVEL_START))
        echo "  $level: ${LEVEL_ELAPSED}s" >> "$TRAVER_RESULTS"
        # Count dialogues and avg turns
        DIAL_FILE="$TRAVER_OUTPUT/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl"
        if [ -f "$DIAL_FILE" ]; then
            NUM_DIALS=$(wc -l < "$DIAL_FILE")
            AVG_TURNS=$(python3 -c "
import json
turns = [len(json.loads(l)['conversation'])//2 for l in open('$DIAL_FILE')]
print(f'{sum(turns)/len(turns):.1f}')
" 2>/dev/null || echo '?')
            log "  ✓ $level ($LEVEL_NUM/3) — $NUM_DIALS dialogues, avg $AVG_TURNS turns ($(fmt_time $LEVEL_ELAPSED))"
        else
            log "  ✓ $level ($LEVEL_NUM/3) done in $(fmt_time $LEVEL_ELAPSED)"
        fi
        LEVEL_NUM=$((LEVEL_NUM + 1))
    done

    echo "" >> "$TRAVER_RESULTS"
    echo "Completed: $(date)" >> "$TRAVER_RESULTS"
    log "  ✓ DONE — Traver dialogues complete ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# STEP 5: Code generation (async API)
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 5/6: Running code generation (async API)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

prompt_base_dir="$PROJECT_DIR/prompt/student_posttest"
output_base_dir="$PROJECT_DIR/output/student_posttest"
rounds=(1 2 3 4 5 6 7 8)
n=10

CODEGEN_RESULTS="$output_base_dir/traver_codegen_results.txt"

if [ -f "$CODEGEN_RESULTS" ] && grep -q "Completed:" "$CODEGEN_RESULTS"; then
    log "  ✓ SKIP — Traver codegen results found and complete"
else
    echo "Traver Codegen Results" > "$CODEGEN_RESULTS"
    echo "Started: $(date)" >> "$CODEGEN_RESULTS"
    echo "" >> "$CODEGEN_RESULTS"

    # Create prompts from Traver dialogues
    log "  Creating prompts from Traver dialogues..."
    for level in "${student_levels[@]}"; do
        PYTHONPATH="$PROJECT_DIR/traver" python -m utils.make_prompt --student_posttest \
            --prompt_element_file "prompt/prompt_elements_final.jsonl" \
            --simulated_file "$TRAVER_OUTPUT/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl" \
            --output_dir "$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level" \
            --student_level "$level" \
            --max_interaction_round 8 \
            --max_cognitive_load 60
    done
    log "  ✓ Prompts created for all levels"

    # Run codegen
    TOTAL_ROUNDS=$((${#student_levels[@]} * ${#rounds[@]}))
    ROUND_NUM=1
    for level in "${student_levels[@]}"; do
        for rdx in "${rounds[@]}"; do
            PROMPT_FILE="$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/prompt_round_${rdx}.jsonl"
            if [ ! -f "$PROMPT_FILE" ]; then
                log "  ⚠  SKIP — No prompt file for $level/round_$rdx ($ROUND_NUM/$TOTAL_ROUNDS)"
                ROUND_NUM=$((ROUND_NUM + 1))
                continue
            fi

            NUM_PROMPTS=$(wc -l < "$PROMPT_FILE")
            log "  🔄 Generating $level/round_$rdx — $NUM_PROMPTS tasks ($ROUND_NUM/$TOTAL_ROUNDS)..."
            ROUND_START=$SECONDS

            PYTHONPATH="$PROJECT_DIR/traver" python -m utils.LM_inference_api \
                --model_name_or_path "$STUDENT_MODEL" \
                --api_base "$HF_API_ENDPOINT" \
                --api_key "$HF_TOKEN" \
                --prompt_file "$PROMPT_FILE" \
                --output_dir "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}" \
                --decoding "sampling" \
                --N $n \
                --max_concurrent_tasks 5

            ROUND_ELAPSED=$((SECONDS - ROUND_START))
            echo "  codegen $level round-$rdx: ${ROUND_ELAPSED}s" >> "$CODEGEN_RESULTS"
            # Count completions generated
            COMP_OUT="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
            NUM_COMP=$(wc -l < "$COMP_OUT" 2>/dev/null || echo 0)
            log "  ✓ $level/round_$rdx — $NUM_COMP completions generated ($(fmt_time $ROUND_ELAPSED)) ($ROUND_NUM/$TOTAL_ROUNDS)"
            ROUND_NUM=$((ROUND_NUM + 1))
        done
    done

    # Process completions
    log "  Processing completions into final format..."
    for level in "${student_levels[@]}"; do
        for rdx in "${rounds[@]}"; do
            COMP_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
            if [ ! -f "$COMP_FILE" ]; then
                continue
            fi
            PYTHONPATH="$PROJECT_DIR/traver" python -m utils.process_completion \
                --completion_file "$COMP_FILE" \
                --output_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
        done
    done

    echo "" >> "$CODEGEN_RESULTS"
    echo "Completed: $(date)" >> "$CODEGEN_RESULTS"
    log "  ✓ DONE — Code generation complete ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# STEP 6: Coding test evaluation
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ STEP 6/6: Running coding test evaluation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STEP_START=$SECONDS

ECB_ROOT="$PROJECT_DIR/EvoCodeBench-2403"
if [ -f "$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl" ]; then
    metadata_file="$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl"
elif [ -f "$ECB_ROOT/metadata.jsonl" ]; then
    metadata_file="$ECB_ROOT/metadata.jsonl"
else
    metadata_file="$ECB_ROOT/data.jsonl"
fi

EVAL_RESULTS="$output_base_dir/traver_coding_test_results.txt"

if [ -f "$EVAL_RESULTS" ] && grep -q "Completed:" "$EVAL_RESULTS"; then
    log "  ✓ SKIP — Traver eval results found and complete"
else
    echo "Traver Coding Test Results" > "$EVAL_RESULTS"
    echo "Started: $(date)" >> "$EVAL_RESULTS"
    echo "" >> "$EVAL_RESULTS"

    TOTAL_EVALS=$((${#student_levels[@]} * ${#rounds[@]}))
    EVAL_NUM=1
    for level in "${student_levels[@]}"; do
        for rdx in "${rounds[@]}"; do
            COMP_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
            if [ ! -f "$COMP_FILE" ]; then
                EVAL_NUM=$((EVAL_NUM + 1))
                continue
            fi

            log "  🔄 Evaluating $level/round_$rdx ($EVAL_NUM/$TOTAL_EVALS)..."
            EVAL_START=$SECONDS

            # pass@k
            PYTHONPATH="$PROJECT_DIR/EvoCodeBench-2403:$PROJECT_DIR/traver" \
            python -m parser.pass_k \
                --output_file "$COMP_FILE" \
                --log_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl" \
                --data_file "$metadata_file" \
                --source_code_root "EvoCodeBench-2403/Source_Code" \
                --k "1,3,5,10" --n 10

            # recall@k
            PYTHONPATH="$PROJECT_DIR/EvoCodeBench-2403:$PROJECT_DIR/traver:$PROJECT_DIR/traver/parser" \
            python -m parser.recall_k \
                --output_file "$COMP_FILE" \
                --log_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/dependency_results.jsonl" \
                --data_file "$metadata_file" \
                --source_code_root "EvoCodeBench-2403/Source_Code" \
                --dependency_data_root "EvoCodeBench-2403/Dependency_Data" \
                --k "1,3,5,10"

            EVAL_ELAPSED=$((SECONDS - EVAL_START))
            echo "  $tutor_setting/$TUTOR_MODEL_DIR/$level/round_$rdx: ${EVAL_ELAPSED}s" >> "$EVAL_RESULTS"
            # Extract pass/fail counts
            TEST_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl"
            if [ -f "$TEST_FILE" ]; then
                PASS_FAIL=$(python3 -c "
import json
results = [json.loads(l) for l in open('$TEST_FILE')]
passed = sum(1 for r in results if r.get('Result') == 'Pass')
failed = sum(1 for r in results if r.get('Result') == 'Fail')
total = len(results)
rate = (passed/total*100) if total > 0 else 0
print(f'{passed}/{total} pass ({rate:.1f}%)')
" 2>/dev/null || echo 'N/A')
                log "  ✓ $level/round_$rdx — $PASS_FAIL ($(fmt_time $EVAL_ELAPSED)) ($EVAL_NUM/$TOTAL_EVALS)"
            else
                log "  ✓ $level/round_$rdx evaluated in $(fmt_time $EVAL_ELAPSED) ($EVAL_NUM/$TOTAL_EVALS)"
            fi
            EVAL_NUM=$((EVAL_NUM + 1))
        done
    done

    echo "" >> "$EVAL_RESULTS"
    echo "Completed: $(date)" >> "$EVAL_RESULTS"
    log "  ✓ DONE — Evaluation complete ($(fmt_time $((SECONDS - STEP_START))))"
fi

# =================================================================
# FINAL SUMMARY
# =================================================================
TOTAL_ELAPSED=$((SECONDS - PIPELINE_START))
echo ""
echo "================================================================="
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  🎉 TRAVER PIPELINE COMPLETE"
log "  Total time: $(fmt_time $TOTAL_ELAPSED)"
log "  End: $(date)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Print a results summary table
log ""
log "  📊 TRAVER RESULTS SUMMARY (pass rate per round)"
log "  ─────────────────────────────────────────────────"
log "  Round   low_level     med_level     high_level"
for rdx in "${rounds[@]}"; do
    ROW="  R$rdx    "
    for level in "${student_levels[@]}"; do
        TEST_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl"
        if [ -f "$TEST_FILE" ]; then
            RATE=$(python3 -c "
import json
results = [json.loads(l) for l in open('$TEST_FILE')]
passed = sum(1 for r in results if r.get('Result') == 'Pass')
total = len(results)
rate = (passed/total*100) if total > 0 else 0
print(f'{rate:>6.1f}%')
" 2>/dev/null || echo '   N/A ')
        else
            RATE="   N/A "
        fi
        ROW="${ROW}${RATE}       "
    done
    log "$ROW"
done
log "  ─────────────────────────────────────────────────"

# Compare with vanilla baseline if available
VANILLA_DIR="$output_base_dir/vanilla/$TUTOR_MODEL_DIR"
if [ -d "$VANILLA_DIR" ]; then
    log ""
    log "  📊 VANILLA BASELINE COMPARISON (pass rate per round)"
    log "  ─────────────────────────────────────────────────"
    log "  Round   low_level     med_level     high_level"
    for rdx in "${rounds[@]}"; do
        ROW="  R$rdx    "
        for level in "${student_levels[@]}"; do
            TEST_FILE="$VANILLA_DIR/$level/round_${rdx}/test_results.jsonl"
            if [ -f "$TEST_FILE" ]; then
                RATE=$(python3 -c "
import json
results = [json.loads(l) for l in open('$TEST_FILE')]
passed = sum(1 for r in results if r.get('Result') == 'Pass')
total = len(results)
rate = (passed/total*100) if total > 0 else 0
print(f'{rate:>6.1f}%')
" 2>/dev/null || echo '   N/A ')
            else
                RATE="   N/A "
            fi
            ROW="${ROW}${RATE}       "
        done
        log "$ROW"
    done
    log "  ─────────────────────────────────────────────────"
fi

echo "================================================================="
echo ""
echo "  Progress log:  $PROGRESS_FILE"
echo "  Eval results:  $output_base_dir/traver_coding_test_results.txt"
echo "  Codegen log:   $output_base_dir/traver_codegen_results.txt"
echo ""
echo "  To view results: cat $PROGRESS_FILE"
