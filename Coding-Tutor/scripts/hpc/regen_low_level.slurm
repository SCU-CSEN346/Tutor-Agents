#!/bin/bash
#SBATCH --job-name="regen-low"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="regen_low_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Coding-Tutor HPC: Generate Completions from Colab Dialogues
# =================================================================
# Steps per student level:
#   1. Download dialogue JSONL from Google Drive
#   2. Generate posttest prompts (make_prompt.py)
#   3. Run code generation (local Mistral-7B via vLLM)
#   4. Process completions
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
REPO_DIR="$GROUP_DIR/Coding-Tutor"
WORK_DIR="$REPO_DIR"
PROGRESS_FILE="$WORK_DIR/output/regen_low_progress.txt"

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

# Models
TUTOR_MODEL="${TUTOR_MODEL:-meta-llama/Llama-3.1-70B-Instruct}"
STUDENT_MODEL="$GROUP_DIR/models/Mistral-7B-Instruct-v0.2"
TUTOR_MODEL_DIR="${TUTOR_MODEL_DIR:-Llama-3.1-70B-Instruct}"

tutor_setting="traver"
student_levels=(low_level)
rounds=(1 2 3 4 5 6 7 8)
n=10

# EvoCodeBench paths
ECB_ROOT="$REPO_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
metadata_file="$ECB_ROOT/data.jsonl"

prompt_base_dir="$WORK_DIR/prompt/student_posttest"
output_base_dir="$WORK_DIR/output/student_posttest"

mkdir -p "$WORK_DIR/output"
cd "$WORK_DIR"

# =================================================================
# FORCE CLEAN: Delete existing low_level completions
# =================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ FORCE CLEAN: Removing existing low_level data..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
COMP_DIR="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/low_level"
PROMPT_DIR="$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/low_level"
if [ -d "$COMP_DIR" ]; then
    echo "  🗑️  Removing completions: $(find "$COMP_DIR" -name '*.jsonl' | wc -l) files"
    rm -rf "$COMP_DIR"
fi
if [ -d "$PROMPT_DIR" ]; then
    echo "  🗑️  Removing prompts: $(find "$PROMPT_DIR" -name '*.jsonl' | wc -l) files"
    rm -rf "$PROMPT_DIR"
fi
echo "  ✓ Low level clean"

# --- Pre-flight checks ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Pre-flight checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -d "$Source_Code_Root" ]; then
    echo "  ❌ Source_Code not found: $Source_Code_Root"
    exit 1
fi
echo "  ✓ Source_Code: $(ls "$Source_Code_Root" | wc -l) projects"

if ! command -v rclone &> /dev/null; then
    echo "  ❌ rclone not found"
    exit 1
fi
echo "  ✓ rclone available"

if ! rclone lsd "gdrive:$DRIVE_ROOT" &>/dev/null; then
    echo "  ❌ Cannot access gdrive:$DRIVE_ROOT"
    exit 1
fi
echo "  ✓ Google Drive accessible"

if [ ! -f "$STUDENT_MODEL/config.json" ]; then
    echo "  ⚠️  Student model not cached, will download from Drive"
else
    echo "  ✓ Student model: $STUDENT_MODEL"
fi

if [ ! -f "$metadata_file" ]; then
    echo "  ❌ Metadata file not found: $metadata_file"
    exit 1
fi
echo "  ✓ Metadata: $(wc -l < "$metadata_file") tasks in $metadata_file"
echo "  ✓ Prompt elements: $WORK_DIR/prompt/prompt_elements_final.jsonl"
echo ""

# --- Download ONLY the low_level dialogue (no global sync) ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Downloading low_level dialogue from Drive..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
LOW_DIALOGUE_DIR="$WORK_DIR/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/low_level"
mkdir -p "$LOW_DIALOGUE_DIR"
rclone copy "gdrive:$DRIVE_ROOT/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/low_level/simulated_dialogs.jsonl" \
    "$LOW_DIALOGUE_DIR/" --progress 2>&1 | tail -3
if [ -f "$LOW_DIALOGUE_DIR/simulated_dialogs.jsonl" ]; then
    echo "  ✓ Downloaded $(wc -l < "$LOW_DIALOGUE_DIR/simulated_dialogs.jsonl") dialogues"
else
    echo "  ❌ Download failed!"
    exit 1
fi
echo "  ✓ Mistral-7B already cached: $STUDENT_MODEL"

# Initialize progress file
cat > "$PROGRESS_FILE" <<EOF
================================================================
  Coding-Tutor HPC: Completion Generation (Clean Start)
  Started: $(date)
================================================================
  Tutor:       $TUTOR_MODEL
  Student:     $STUDENT_MODEL
  Levels:      ${student_levels[*]}
  Rounds:      ${rounds[*]}
  N:           $n completions per task
================================================================
EOF

echo ""
echo "================================================================="
echo "  Coding-Tutor HPC: Completion Generation"
echo "================================================================="
echo "  Tutor model:    $TUTOR_MODEL"
echo "  Student model:  $STUDENT_MODEL"
echo "  Levels:         ${student_levels[*]}"
echo "  Rounds:         ${rounds[*]}"
echo "  N:              $n completions per task"
echo "  Start:          $(date)"
echo "================================================================="

PIPELINE_START=$SECONDS

# =================================================================
# MAIN LOOP: Process one level at a time
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
    LOCAL_DIALOGUE_DIR="$WORK_DIR/output/dialogue/$tutor_setting/$TUTOR_MODEL_DIR/$level"
    LOCAL_DIALOGUE_FILE="$LOCAL_DIALOGUE_DIR/simulated_dialogs.jsonl"

    # ── Step A: Check/Download dialogue ──
    log "  📥 Step A: Getting $level dialogue..."
    mkdir -p "$LOCAL_DIALOGUE_DIR"

    if [ -f "$LOCAL_DIALOGUE_FILE" ]; then
        NUM_EXISTING=$(wc -l < "$LOCAL_DIALOGUE_FILE")
        log "  ✓ Already exists locally ($NUM_EXISTING dialogues)"
    else
        log "  Downloading from gdrive:$DRIVE_DIALOGUE_PATH"
        rclone copy "gdrive:$DRIVE_DIALOGUE_PATH" "$LOCAL_DIALOGUE_DIR/" --progress 2>&1 | tail -5

        if [ ! -f "$LOCAL_DIALOGUE_FILE" ]; then
            log "  ❌ Download failed! File not found on Drive. Skipping $level."
            log "     Tried: gdrive:$DRIVE_DIALOGUE_PATH"
            LEVEL_NUM=$((LEVEL_NUM + 1))
            continue
        fi
        NUM_DIALS=$(wc -l < "$LOCAL_DIALOGUE_FILE")
        log "  ✓ Downloaded $NUM_DIALS dialogues"
    fi

    # Debug: Dialogue turn distribution
    log "  📊 Dialogue analysis:"
    python3 -c "
import json
from collections import Counter
turns = {}
with open('$LOCAL_DIALOGUE_FILE') as f:
    for line in f:
        js = json.loads(line)
        turns[js['namespace']] = len(js.get('conversation', [])) // 2
dist = Counter(sorted(turns.values()))
total = len(turns)
print(f'     Total tasks: {total}')
for t, count in sorted(dist.items()):
    print(f'     {t} rounds: {count} tasks ({count/total*100:.0f}%)')
"

    # ── Step B: Generate posttest prompts ──
    log "  📝 Step B: Generating posttest prompts..."
    PROMPT_DIR="$prompt_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level"

    PYTHONPATH="$WORK_DIR/traver" python "$WORK_DIR/traver/utils/make_prompt.py" --student_posttest \
        --prompt_element_file "$WORK_DIR/prompt/prompt_elements_final.jsonl" \
        --simulated_file "$LOCAL_DIALOGUE_FILE" \
        --output_dir "$PROMPT_DIR" \
        --student_level "$level" \
        --max_interaction_round 8 \
        --max_cognitive_load 60

    # Debug: Show prompt files created
    log "  📊 Prompt files created:"
    for rdx in "${rounds[@]}"; do
        PFILE="$PROMPT_DIR/prompt_round_${rdx}.jsonl"
        if [ -f "$PFILE" ]; then
            PLINES=$(wc -l < "$PFILE")
            log "     round_$rdx: $PLINES prompts"
        else
            log "     round_$rdx: NOT CREATED (no tasks with $rdx+ rounds)"
        fi
    done

    # ── Step C: Code generation (per round) ──
    log "  🔧 Step C: Running code generation..."
    for rdx in "${rounds[@]}"; do
        PROMPT_FILE="$PROMPT_DIR/prompt_round_${rdx}.jsonl"
        COMP_DIR="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}"
        COMP_OUT="$COMP_DIR/completion.jsonl"

        if [ ! -f "$PROMPT_FILE" ]; then
            log "    ⏭️  round_$rdx: no prompt file, skipping remaining rounds"
            break
        fi

        NUM_PROMPTS=$(wc -l < "$PROMPT_FILE")
        mkdir -p "$COMP_DIR"

        # If raw completions exist from Drive but haven't been processed
        COMP_LM_CHECK="$COMP_DIR/completion_lm.jsonl"
        if [ -f "$COMP_LM_CHECK" ]; then
            log "    🔄 round_$rdx: processing existing completion_lm.jsonl..."
            PYTHONPATH="$WORK_DIR/traver" python "$WORK_DIR/traver/utils/process_completion.py" \
                --completion_file "$COMP_LM_CHECK" \
                --output_file "$COMP_OUT"
            NUM_COMP=$(wc -l < "$COMP_OUT" 2>/dev/null || echo 0)
            log "    ✓ round_$rdx: $NUM_COMP completions (from existing LM output)"
            continue
        fi

        # Generate from scratch via vLLM
        log "    🔄 round_$rdx: generating $NUM_PROMPTS × $n = $((NUM_PROMPTS * n)) completions via vLLM..."
        ROUND_START=$SECONDS

        PYTHONPATH="$WORK_DIR/traver" python "$WORK_DIR/traver/utils/LM_inference.py" \
            --model_name_or_path "$STUDENT_MODEL" \
            --prompt_file "$PROMPT_FILE" \
            --output_dir "$COMP_DIR" \
            --decoding "sampling" \
            --N $n \
            --dtype half \
            --gpu_memory_utilization 0.90

        # Process raw completions
        COMP_LM="$COMP_DIR/completion_lm.jsonl"
        if [ -f "$COMP_LM" ]; then
            COMP_LM_LINES=$(wc -l < "$COMP_LM")
            log "    📄 completion_lm.jsonl: $COMP_LM_LINES lines"
            PYTHONPATH="$WORK_DIR/traver" python "$WORK_DIR/traver/utils/process_completion.py" \
                --completion_file "$COMP_LM" \
                --output_file "$COMP_OUT"
        else
            log "    ❌ round_$rdx: completion_lm.jsonl NOT created!"
        fi

        ROUND_ELAPSED=$((SECONDS - ROUND_START))
        if [ -f "$COMP_OUT" ]; then
            NUM_COMP=$(wc -l < "$COMP_OUT")
            log "    ✓ round_$rdx: $NUM_COMP completions ($(fmt_time $ROUND_ELAPSED))"
        else
            log "    ❌ round_$rdx: completion.jsonl NOT created! ($(fmt_time $ROUND_ELAPSED))"
        fi
    done

    # ── Step D: Cleanup ──
    log "  🗑️  Step D: Cleaning up dialogue file..."
    rm -f "$LOCAL_DIALOGUE_FILE"

    LEVEL_ELAPSED=$((SECONDS - LEVEL_START))
    log "  ✅ $level COMPLETE ($(fmt_time $LEVEL_ELAPSED))"

    LEVEL_NUM=$((LEVEL_NUM + 1))
done

# =================================================================
# FINAL SUMMARY
# =================================================================
TOTAL_ELAPSED=$((SECONDS - PIPELINE_START))
echo ""
echo "================================================================="
log "  🎉 COMPLETION GENERATION COMPLETE"
log "  Total time: $(fmt_time $TOTAL_ELAPSED)"
log "  End: $(date)"
echo "================================================================="
echo ""
echo "  📊 Completion file inventory:"
echo "  ─────────────────────────────────────────────────"
for level in "${student_levels[@]}"; do
    echo "  === $level ==="
    for rdx in "${rounds[@]}"; do
        COMP="$output_base_dir/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
        if [ -f "$COMP" ]; then
            echo "    round_$rdx: $(wc -l < "$COMP") completions ✓"
        else
            echo "    round_$rdx: MISSING"
        fi
    done
    echo ""
done
echo "  ─────────────────────────────────────────────────"
echo ""
echo "  Next step: run eval_by_project.slurm for evaluation"
echo "    sbatch scripts/hpc/eval_by_project.slurm"
echo ""
