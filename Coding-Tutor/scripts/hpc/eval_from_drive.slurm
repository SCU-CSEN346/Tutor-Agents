#!/bin/bash
#SBATCH --job-name="colab-eval"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="colab_eval_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Evaluate Colab Dialogues
# =================================================================
# Runs directly from the git repo. Steps per student level:
#   1. Download dialogue JSONL from Google Drive
#   2. Generate posttest prompts
#   3. Run code generation (local vLLM on GPU)
#   4. Run pass@k + recall@k
#   5. Clean up downloaded dialogue to free disk
#
# Prerequisites:
#   - rclone configured with a remote named "gdrive"
#   - EvoCodeBench set up (Source_Code + Dependency_Data)
#   - Mistral-7B model cached locally
#   - HF_TOKEN set
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/eval_from_drive.slurm
# =================================================================

set -eo pipefail

# Our group project dir
GROUP_DIR="/WAVE/projects/CSEN-346-Sp26/Group2"
# Git repo root
REPO_DIR="$GROUP_DIR/Coding-Tutor"
# Working directory (paper code lives here)
WORK_DIR="$REPO_DIR/Coding-Tutor"
PROGRESS_FILE="$WORK_DIR/output/colab_eval_progress.txt"

module load CUDA/12.6.2

source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

echo "=== GPU Diagnostic ==="
nvidia-smi
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
python -c "import torch; print(f'PyTorch CUDA: {torch.version.cuda}, available: {torch.cuda.is_available()}, devices: {torch.cuda.device_count()}')"
echo "======================"

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
DRIVE_ROOT="Coding-Tutor-Colab"

# Models — must match what Colab used
TUTOR_MODEL="${TUTOR_MODEL:-meta-llama/Llama-3.1-70B-Instruct}"
STUDENT_MODEL="$GROUP_DIR/models/Mistral-7B-Instruct-v0.2"
TUTOR_MODEL_DIR="${TUTOR_MODEL_DIR:-Llama-3.1-70B-Instruct}"

tutor_setting="traver"
student_levels=(low_level med_level high_level)
rounds=(1 2 3 4 5 6 7 8)
n=10

# EvoCodeBench paths
ECB_ROOT="$REPO_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"

# Benchmark metadata (completion_path, tests, body_position, indent)
metadata_file="$ECB_ROOT/metadata.jsonl"
if [ ! -f "$metadata_file" ]; then
    metadata_file="$ECB_ROOT/data.jsonl"
fi

prompt_base_dir="$WORK_DIR/prompt/student_posttest"
output_base_dir="$WORK_DIR/output/student_posttest"

mkdir -p "$WORK_DIR/output"

cd "$WORK_DIR"

# --- Pre-flight checks ---
if [ ! -d "$Source_Code_Root" ]; then
    echo "❌ Source_Code not found: $Source_Code_Root"
    echo "   Run: bash scripts/hpc/setup_evocodebench.sh"
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    echo "❌ rclone not found. Install: conda install -c conda-forge rclone"
    exit 1
fi

if ! rclone lsd "gdrive:$DRIVE_ROOT" &>/dev/null; then
    echo "❌ Cannot access Google Drive path: gdrive:$DRIVE_ROOT"
    echo "   Run: rclone config"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Synchronizing Outputs from Google Drive..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rclone copy "gdrive:$DRIVE_ROOT/output/" "$WORK_DIR/output/" --progress 2>&1 | tail -5
echo "  ✓ Pulled output directory from Drive"

# Unzip any zip archives that Colab uploaded to Drive
for zipfile in $(find "$WORK_DIR/output" -name '*.zip' 2>/dev/null); do
    echo "  📦 Unzipping $(basename $zipfile)..."
    unzip -o -q "$zipfile" -d "$(dirname $zipfile)"
    rm -f "$zipfile"
done

# Download student model weights from Drive if not already cached
if [ ! -f "$STUDENT_MODEL/config.json" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ Downloading Mistral-7B from Google Drive..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    mkdir -p "$STUDENT_MODEL"
    rclone copy "gdrive:$DRIVE_ROOT/models/Mistral-7B-Instruct-v0.2/" "$STUDENT_MODEL/" --progress 2>&1 | tail -5
    echo "  ✓ Mistral-7B downloaded to $STUDENT_MODEL"
else
    echo "  ✓ Mistral-7B already cached at $STUDENT_MODEL"
fi

# Initialize progress file
cat > "$PROGRESS_FILE" <<EOF
================================================================
  Coding-Tutor HPC Evaluation
  Started: $(date)
================================================================
  Tutor:       $TUTOR_MODEL
  Student:     $STUDENT_MODEL
  Work dir:    $WORK_DIR
  Source_Code: $(ls "$Source_Code_Root" | wc -l) projects
================================================================
EOF

echo "================================================================="
echo "  Coding-Tutor HPC Evaluation"
echo "================================================================="
echo "  Tutor model:    $TUTOR_MODEL"
echo "  Student model:  $STUDENT_MODEL"
echo "  Work dir:       $WORK_DIR"
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
    LOCAL_DIALOGUE_DIR="$PAPER_DIR/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/$level"
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
        PYTHONPATH="$PAPER_DIR/traver" python "$PAPER_DIR/traver/utils/make_prompt.py" --student_posttest \
            --prompt_element_file "$PAPER_DIR/prompt/prompt_elements_final.jsonl" \
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

        # If raw completions exist from Drive but haven't been processed yet, just process them
        COMP_LM_CHECK="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
        if [ -f "$COMP_LM_CHECK" ]; then
            log "    🔄 round_$rdx — processing existing completion_lm.jsonl from Drive..."
            PYTHONPATH="$PAPER_DIR/traver" python "$PAPER_DIR/traver/utils/process_completion.py" \
                --completion_file "$COMP_LM_CHECK" \
                --output_file "$COMP_OUT"
            log "    ✓ round_$rdx — processed"
            continue
        fi

        # No completions at all — need to generate (requires GPU + vLLM)
        NUM_PROMPTS=$(wc -l < "$PROMPT_FILE")
        log "    🔄 round_$rdx — $NUM_PROMPTS tasks (generating via vLLM)..."
        ROUND_START=$SECONDS

        PYTHONPATH="$PAPER_DIR/traver" python "$PAPER_DIR/traver/utils/LM_inference.py" \
            --model_name_or_path "$STUDENT_MODEL" \
            --prompt_file "$PROMPT_FILE" \
            --output_dir "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}" \
            --decoding "sampling" \
            --N $n \
            --dtype half \
            --gpu_memory_utilization 0.90

        # Process raw completions into final format
        COMP_LM="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion_lm.jsonl"
        if [ -f "$COMP_LM" ]; then
            PYTHONPATH="$PAPER_DIR/traver" python "$PAPER_DIR/traver/utils/process_completion.py" \
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
        PYTHONPATH="$PAPER_DIR:$PAPER_DIR/traver" python "$PAPER_DIR/traver/parser/pass_k.py" \
            --output_file "$COMP_FILE" \
            --log_file "$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/test_results.jsonl" \
            --data_file "$metadata_file" \
            --source_code_root "$Source_Code_Root" \
            --k "1,3,5,10" --n $n \
            2>&1 | tee -a "$output_base_dir/pass_colab_traver_${level}_round${rdx}.log"

        # recall@k
        if [ -d "$Dependency_Root" ]; then
            PYTHONPATH="$PAPER_DIR:$PAPER_DIR/traver" python "$PAPER_DIR/traver/parser/recall_k.py" \
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
VANILLA_DIR="$PROJECT_DIR/output/student_posttest/vanilla/Llama-3.3-70B-Instruct"
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
echo "  Paper code:    $PAPER_DIR"
echo "  Results:       $output_base_dir"
echo ""
echo "  To view results: cat $PROGRESS_FILE"
