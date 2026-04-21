#!/bin/bash
#SBATCH --job-name="colab-eval"
#SBATCH --partition=cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --output="colab_eval_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Evaluate Colab Dialogues (Streamed from Drive)
# =================================================================
# Processes one student level at a time:
#   1. Download that level's dialogue JSONL from Drive
#   2. Generate posttest prompts
#   3. Run code generation (HF API)
#   4. Run pass@k + recall@k
#   5. Delete the downloaded dialogue file to free disk space
#
# This way only ~1 MB of dialogue data is on disk at any time.
#
# Prerequisites:
#   - rclone configured with a remote named "gdrive"
#     (run `rclone config` interactively first — one-time setup)
#   - EvoCodeBench set up on HPC (Source_Code + Dependency_Data)
#   - HF_TOKEN set
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/eval_from_drive.slurm
# =================================================================

set -eo pipefail

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
PROGRESS_FILE="$PROJECT_DIR/output/colab_eval_progress.txt"

source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$PROJECT_DIR"

# --- Helper functions ---
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

# Google Drive path (relative to your Drive root)
# This is the path inside "My Drive"
DRIVE_ROOT="Coding-Tutor-Colab"

# Models — must match what Colab used
TUTOR_MODEL="${TUTOR_MODEL:-meta-llama/Llama-3.1-70B-Instruct}"
STUDENT_MODEL="${STUDENT_MODEL:-meta-llama/Meta-Llama-3-8B-Instruct}"
TUTOR_MODEL_DIR="${TUTOR_MODEL_DIR:-Llama-3.1-70B-Instruct}"

tutor_setting="traver"
student_levels=(low_level med_level high_level)
rounds=(1 2 3 4 5 6 7 8)
n=10

# EvoCodeBench paths
ECB_ROOT="$PROJECT_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"

if [ -f "$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl" ]; then
    metadata_file="$PROJECT_DIR/benchmark/EvoCodeBench-2403/metadata.jsonl"
elif [ -f "$ECB_ROOT/metadata.jsonl" ]; then
    metadata_file="$ECB_ROOT/metadata.jsonl"
else
    metadata_file="$ECB_ROOT/data.jsonl"
fi

prompt_base_dir="$PROJECT_DIR/prompt/student_posttest"
output_base_dir="$PROJECT_DIR/output/student_posttest"

mkdir -p "$PROJECT_DIR/output"

# --- Pre-flight checks ---
if [ ! -d "$Source_Code_Root" ]; then
    echo "❌ Source_Code not found: $Source_Code_Root"
    echo "   Run: bash scripts/hpc/setup_evocodebench.sh"
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    echo "❌ rclone not found. Install it first:"
    echo "   conda install -c conda-forge rclone"
    echo "   Then run: rclone config  (choose Google Drive, name it 'gdrive')"
    exit 1
fi

# Verify rclone can see the Drive folder
if ! rclone lsd "gdrive:$DRIVE_ROOT" &>/dev/null; then
    echo "❌ Cannot access Drive folder: $DRIVE_ROOT"
    echo "   Make sure rclone is configured: rclone config"
    echo "   Test with: rclone ls gdrive:$DRIVE_ROOT/output/dialogue/"
    exit 1
fi

# Initialize progress file
cat > "$PROGRESS_FILE" <<EOF
================================================================
  COLAB → HPC EVALUATION PIPELINE (Streamed)
  Started: $(date)
================================================================
  Tutor:       $TUTOR_MODEL
  Student:     $STUDENT_MODEL
  Drive path:  $DRIVE_ROOT
  Source_Code:  $(ls "$Source_Code_Root" | wc -l) projects
================================================================
EOF

echo "================================================================="
echo "  Colab → HPC Evaluation Pipeline (Streamed from Drive)"
echo "================================================================="
echo "  Tutor model:    $TUTOR_MODEL"
echo "  Student model:  $STUDENT_MODEL"
echo "  Drive path:     gdrive:$DRIVE_ROOT"
echo "  Source_Code:    $(ls "$Source_Code_Root" | wc -l) projects"
echo "  Start:          $(date)"
echo "================================================================="

PIPELINE_START=$SECONDS

# =================================================================
# MAIN LOOP: Process one level at a time (stream from Drive)
# =================================================================
LEVEL_NUM=1
for level in "${student_levels[@]}"; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "▶ PROCESSING $level ($LEVEL_NUM/3)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LEVEL_START=$SECONDS

    # --- Path setup ---
    DRIVE_DIALOGUE_PATH="$DRIVE_ROOT/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/$level/simulated_dialogs.jsonl"
    LOCAL_DIALOGUE_DIR="$PROJECT_DIR/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/$level"
    LOCAL_DIALOGUE_FILE="$LOCAL_DIALOGUE_DIR/simulated_dialogs.jsonl"

    # ── Step A: Download this level's dialogue from Drive ──
    log "  📥 Downloading $level dialogue from Drive..."
    mkdir -p "$LOCAL_DIALOGUE_DIR"

    if [ -f "$LOCAL_DIALOGUE_FILE" ]; then
        NUM_EXISTING=$(wc -l < "$LOCAL_DIALOGUE_FILE")
        log "  ✓ Already exists locally ($NUM_EXISTING dialogues), skipping download"
    else
        rclone copy "gdrive:$DRIVE_DIALOGUE_PATH" "$LOCAL_DIALOGUE_DIR/" --progress 2>&1 | tail -5

        if [ ! -f "$LOCAL_DIALOGUE_FILE" ]; then
            log "  ⚠  Download failed or file not found on Drive. Skipping $level."
            log "  Tried: gdrive:$DRIVE_DIALOGUE_PATH"
            LEVEL_NUM=$((LEVEL_NUM + 1))
            continue
        fi
        NUM_DIALS=$(wc -l < "$LOCAL_DIALOGUE_FILE")
        log "  ✓ Downloaded $NUM_DIALS dialogues"
    fi

    # ── Step B: Generate posttest prompts ──
    log "  📝 Generating posttest prompts..."
    PROMPT_DIR="$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level"

    if [ -f "$PROMPT_DIR/prompt_round_1.jsonl" ]; then
        log "  ✓ Prompts already exist, skipping"
    else
        PYTHONPATH="$PROJECT_DIR/traver" python -m utils.make_prompt --student_posttest \
            --prompt_element_file "prompt/prompt_elements_final.jsonl" \
            --simulated_file "$LOCAL_DIALOGUE_FILE" \
            --output_dir "$PROMPT_DIR" \
            --student_level "$level" \
            --max_interaction_round 8 \
            --max_cognitive_load 60

        NUM_ROUNDS=$(ls "$PROMPT_DIR"/prompt_round_*.jsonl 2>/dev/null | wc -l)
        log "  ✓ $NUM_ROUNDS prompt rounds created"
    fi

    # ── Step C: Code generation (per round) ──
    log "  🔧 Running code generation..."
    for rdx in "${rounds[@]}"; do
        PROMPT_FILE="$PROMPT_DIR/prompt_round_${rdx}.jsonl"
        COMP_OUT="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"

        if [ ! -f "$PROMPT_FILE" ]; then
            continue
        fi

        if [ -f "$COMP_OUT" ]; then
            log "    ✓ round_$rdx — completions exist, skipping"
            continue
        fi

        NUM_PROMPTS=$(wc -l < "$PROMPT_FILE")
        log "    🔄 round_$rdx — $NUM_PROMPTS tasks..."
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

        # Process raw completions into final format
        COMP_LM="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
        if [ -f "$COMP_LM" ]; then
            PYTHONPATH="$PROJECT_DIR/traver" python -m utils.process_completion \
                --completion_file "$COMP_LM" \
                --output_file "$COMP_OUT"
        fi

        ROUND_ELAPSED=$((SECONDS - ROUND_START))
        NUM_COMP=$(wc -l < "$COMP_OUT" 2>/dev/null || echo 0)
        log "    ✓ round_$rdx — $NUM_COMP completions ($(fmt_time $ROUND_ELAPSED))"
    done

    # ── Step D: Evaluation (pass@k + recall@k per round) ──
    log "  📊 Running evaluation..."
    for rdx in "${rounds[@]}"; do
        COMP_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
        if [ ! -f "$COMP_FILE" ]; then
            continue
        fi

        log "    🔄 Evaluating round_$rdx..."
        EVAL_START=$SECONDS

        # pass@k
        PYTHONPATH="$PROJECT_DIR/traver" python -m parser.pass_k \
            --output_file "$COMP_FILE" \
            --log_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl" \
            --data_file "$metadata_file" \
            --source_code_root "$Source_Code_Root" \
            --k "1,3,5,10" --n $n \
            2>&1 | tee -a "$output_base_dir/pass_colab_traver_${level}_round${rdx}.log"

        # recall@k
        if [ -d "$Dependency_Root" ]; then
            PYTHONPATH="$PROJECT_DIR/traver:$PROJECT_DIR/traver/parser" python -m parser.recall_k \
                --output_file "$COMP_FILE" \
                --log_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/dependency_results.jsonl" \
                --data_file "$metadata_file" \
                --source_code_root "$Source_Code_Root" \
                --dependency_data_root "$Dependency_Root" \
                --k "1,3,5,10" \
                2>&1 | tee -a "$output_base_dir/recall_colab_traver_${level}_round${rdx}.log"
        fi

        EVAL_ELAPSED=$((SECONDS - EVAL_START))

        TEST_FILE="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl"
        if [ -f "$TEST_FILE" ]; then
            PASS_FAIL=$(python3 -c "
import json
results = [json.loads(l) for l in open('$TEST_FILE')]
passed = sum(1 for r in results if r.get('Result') == 'Pass')
total = len(results)
rate = (passed/total*100) if total > 0 else 0
print(f'{passed}/{total} pass ({rate:.1f}%)')
" 2>/dev/null || echo 'N/A')
            log "    ✓ round_$rdx — $PASS_FAIL ($(fmt_time $EVAL_ELAPSED))"
        fi
    done

    # ── Step E: Cleanup — delete downloaded dialogue to free disk ──
    log "  🗑️  Cleaning up downloaded dialogue file..."
    rm -f "$LOCAL_DIALOGUE_FILE"
    log "  ✓ $level COMPLETE ($(fmt_time $((SECONDS - LEVEL_START))))"

    LEVEL_NUM=$((LEVEL_NUM + 1))
done

# =================================================================
# FINAL SUMMARY
# =================================================================
TOTAL_ELAPSED=$((SECONDS - PIPELINE_START))
echo ""
echo "================================================================="
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  🎉 COLAB → HPC EVALUATION COMPLETE"
log "  Total time: $(fmt_time $TOTAL_ELAPSED)"
log "  End: $(date)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Print results summary table
log ""
log "  📊 COLAB-TRAVER RESULTS (pass rate per round)"
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
VANILLA_DIR="$output_base_dir/vanilla/Llama-3.3-70B-Instruct"
if [ -d "$VANILLA_DIR" ]; then
    log ""
    log "  📊 VANILLA BASELINE (for comparison)"
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
echo ""
echo "  To view results: cat $PROGRESS_FILE"
