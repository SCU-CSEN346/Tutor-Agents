#!/bin/bash
#SBATCH --job-name="easyvolcap-eval"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="easyvolcap_eval_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# EasyVolcap Focused Pipeline: Dialogue → Posttest → Codegen → Eval
# =================================================================
# Runs the complete post-dialogue pipeline for EasyVolcap (12 tasks).
# Dialogues are pulled from Google Drive (already generated on Colab).
#
# Steps per level:
#   1. Sync dialogues from Drive (per-project layout)
#   2. Generate posttest prompts (make_prompt.py)
#   3. Code generation via HF API (LM_inference_hf.py)
#   4. Parse completions (process_completion.py)
#   5. Create project venv + install EasyVolcap deps
#   6. Run pass@k + recall@k evaluation
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/eval_easyvolcap.slurm
# =================================================================

set -o pipefail

# ── Paths ──
GROUP_DIR="/WAVE/projects/CSEN-346-Sp26/Group2"
REPO_DIR="$GROUP_DIR/Coding-Tutor"
WORK_DIR="$REPO_DIR"
ECB_ROOT="$REPO_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
VENV_DIR="$REPO_DIR/.eval_venv_easyvolcap"

# ── Config ──
HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running}"
TUTOR_MODEL="meta-llama/Llama-3.1-70B-Instruct"
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
CODEGEN_MODEL="meta-llama/Llama-3.1-8B-Instruct"
CODEGEN_API_BASE="https://router.huggingface.co/v1"
DRIVE_ROOT="Coding-Tutor-Colab"

NS_PREFIX="easyvolcap"
PROJECT_FOLDER="EasyVolcap"
student_levels=(low_level med_level high_level)
MAX_ROUNDS=8
N=10
T=0.4
TOP_P=0.95
MAX_TOKENS=1024
MAX_CONCURRENT=3

metadata_file="$ECB_ROOT/data.jsonl"
prompt_elements="$WORK_DIR/prompt/prompt_elements_final.jsonl"

# ── Environment ──
module load CUDA/12.6.2
source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$WORK_DIR"

# ── Helpers ──
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
fmt_time() { printf '%dh %dm %ds' $(($1/3600)) $(($1%3600/60)) $(($1%60)); }

echo "================================================================="
echo "  EasyVolcap Focused Pipeline"
echo "================================================================="
echo "  Namespace:   $NS_PREFIX"
echo "  Folder:      $PROJECT_FOLDER"
echo "  Codegen:     $CODEGEN_MODEL (HF API)"
echo "  N=$N, T=$T, top_p=$TOP_P"
echo "  Start:       $(date)"
echo "================================================================="

# ── Pre-flight checks ──
nvidia-smi | head -5
echo ""

if [ ! -d "$Source_Code_Root/$PROJECT_FOLDER" ]; then
    echo "❌ Source code not found: $Source_Code_Root/$PROJECT_FOLDER"
    exit 1
fi
log "✓ Source code: $Source_Code_Root/$PROJECT_FOLDER"

if ! command -v rclone &>/dev/null; then
    echo "❌ rclone not found"
    exit 1
fi
log "✓ rclone available"

# ── Create per-project prompt file ──
PROJ_DIR="$WORK_DIR/prompt/per_project/$NS_PREFIX"
PROJ_PROMPT="$PROJ_DIR/prompt_elements_final.jsonl"
mkdir -p "$PROJ_DIR"

if [ ! -f "$PROJ_PROMPT" ]; then
    log "📋 Filtering prompt elements for $NS_PREFIX..."
    python3 -c "
import json
count = 0
with open('$prompt_elements') as f, open('$PROJ_PROMPT', 'w') as out:
    for line in f:
        js = json.loads(line)
        if js['namespace'].startswith('$NS_PREFIX.'):
            out.write(line)
            count += 1
print(f'  {count} tasks for $NS_PREFIX')
"
fi

# ── Create filtered metadata for eval ──
FILTERED_META="$PROJ_DIR/metadata_filtered.jsonl"
if [ ! -f "$FILTERED_META" ]; then
    log "📋 Filtering metadata for $NS_PREFIX..."
    python3 -c "
import json
count = 0
with open('$metadata_file') as f, open('$FILTERED_META', 'w') as out:
    for line in f:
        js = json.loads(line)
        if js['namespace'].startswith('$NS_PREFIX.'):
            out.write(line)
            count += 1
print(f'  {count} eval tasks for $NS_PREFIX')
"
fi

PIPELINE_START=$SECONDS

# =================================================================
# MAIN LOOP: Per-level processing
# =================================================================
for level in "${student_levels[@]}"; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "▶ $NS_PREFIX | $level"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LEVEL_START=$SECONDS

    # ── Step 1: Sync dialogue from Drive ──
    DRIVE_DIALOG="$DRIVE_ROOT/output/dialogue_by_project/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level/"
    LOCAL_DIALOG_DIR="$WORK_DIR/output/dialogue_by_project/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level"
    LOCAL_DIALOG="$LOCAL_DIALOG_DIR/simulated_dialogs.jsonl"

    if [ -f "$LOCAL_DIALOG" ]; then
        NUM_D=$(wc -l < "$LOCAL_DIALOG")
        log "  ✓ Dialogue exists locally ($NUM_D entries)"
    else
        log "  📥 Downloading dialogue from Drive..."
        mkdir -p "$LOCAL_DIALOG_DIR"
        rclone copy "gdrive:$DRIVE_DIALOG" "$LOCAL_DIALOG_DIR/" --progress 2>&1 | tail -3

        if [ ! -f "$LOCAL_DIALOG" ]; then
            log "  ❌ No dialogue found on Drive, skipping $level"
            continue
        fi
        NUM_D=$(wc -l < "$LOCAL_DIALOG")
        log "  ✓ Downloaded $NUM_D dialogues"
    fi

    # ── Step 2: Generate posttest prompts ──
    OUT_DIR="$WORK_DIR/output/student_posttest/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level"
    mkdir -p "$OUT_DIR"

    PROMPT_CHECK="$OUT_DIR/prompt_round_1.jsonl"
    if [ -f "$PROMPT_CHECK" ]; then
        log "  ✓ Step 2: Posttest prompts already exist"
    else
        log "  📝 Step 2: Generating posttest prompts..."
        PYTHONPATH="$WORK_DIR/traver:$WORK_DIR" python "$WORK_DIR/traver/utils/make_prompt.py" \
            --student_posttest \
            --prompt_element_file "$PROJ_PROMPT" \
            --simulated_file "$LOCAL_DIALOG" \
            --output_dir "$OUT_DIR" \
            --student_level "$level" \
            --max_interaction_round $MAX_ROUNDS
        log "  ✓ Step 2: Prompts generated"
    fi

    # ── Step 3+4: Code generation + parse (per round) ──
    for rdx in $(seq 1 $MAX_ROUNDS); do
        ROUND_PROMPT="$OUT_DIR/prompt_round_${rdx}.jsonl"
        ROUND_DIR="$OUT_DIR/round_${rdx}"
        COMP_LM="$ROUND_DIR/completion_lm.jsonl"
        COMP_PARSED="$ROUND_DIR/completion.jsonl"

        if [ ! -f "$ROUND_PROMPT" ]; then
            continue
        fi

        NUM_TASKS=$(wc -l < "$ROUND_PROMPT")
        if [ "$NUM_TASKS" -eq 0 ]; then
            continue
        fi

        mkdir -p "$ROUND_DIR"

        # Skip if fully done
        if [ -f "$COMP_PARSED" ]; then
            EXISTING=$(wc -l < "$COMP_PARSED")
            EXPECTED=$((NUM_TASKS * N))
            if [ "$EXISTING" -ge "$EXPECTED" ]; then
                log "  ✓ round_${rdx}: $EXISTING completions (done)"
                continue
            fi
        fi

        # Code generation via HF API
        if [ ! -f "$COMP_LM" ] || [ "$(wc -l < "$COMP_LM")" -lt "$NUM_TASKS" ]; then
            log "  🔧 round_${rdx}: Generating ${NUM_TASKS}×${N} completions via HF API..."
            PYTHONPATH="$WORK_DIR/traver:$WORK_DIR" \
            HF_TOKEN="$HF_TOKEN" \
            python "$WORK_DIR/traver/utils/LM_inference_hf.py" \
                --prompt_file "$ROUND_PROMPT" \
                --output_dir "$ROUND_DIR" \
                --model_name_or_path "$CODEGEN_MODEL" \
                --api_base "$CODEGEN_API_BASE" \
                --api_key "$HF_TOKEN" \
                --N $N \
                --T $T \
                --top_p $TOP_P \
                --max_tokens $MAX_TOKENS \
                --max_concurrent_tasks $MAX_CONCURRENT

            if [ $? -ne 0 ]; then
                log "  ⚠️  round_${rdx}: codegen failed"
                continue
            fi
        fi

        # Parse completions
        if [ ! -f "$COMP_PARSED" ] && [ -f "$COMP_LM" ]; then
            log "  📋 round_${rdx}: Parsing completions..."
            PYTHONPATH="$WORK_DIR/traver:$WORK_DIR" python "$WORK_DIR/traver/utils/process_completion.py" \
                --model_type gpt \
                --completion_file "$COMP_LM" \
                --output_file "$COMP_PARSED"
        fi

        if [ -f "$COMP_PARSED" ]; then
            COMP_LINES=$(wc -l < "$COMP_PARSED")
            log "  ✓ round_${rdx}: $COMP_LINES parsed completions"
        fi
    done

    LEVEL_ELAPSED=$((SECONDS - LEVEL_START))
    log "  ✅ $level codegen complete ($(fmt_time $LEVEL_ELAPSED))"
done

# =================================================================
# EVALUATION: Create venv with EasyVolcap deps
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ Setting up EasyVolcap evaluation environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create fresh venv
rm -rf "$VENV_DIR"
python -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip 2>&1 | tail -1

# Install eval deps
EVAL_DEPS="numpy tqdm psutil func_timeout tree_sitter pytest pytest-runner dill jinja2"
pip install --quiet $EVAL_DEPS 2>&1 | tail -1

# Install EasyVolcap requirements (skip problematic ones)
REQ="$Source_Code_Root/$PROJECT_FOLDER/requirements.txt"
if [ -f "$REQ" ]; then
    log "  📦 Installing EasyVolcap requirements..."
    # Install line-by-line, skip git+ deps that need compilation
    cat "$REQ" | sed -e '/^\s*#.*$/d' -e '/^\s*$/d' | \
        grep -v "git+" | grep -v "cuda-python" | grep -v "pyopengl" | \
        grep -v "open3d" | grep -v "torch-scatter" | \
        xargs -n 1 pip install --quiet 2>&1 | tail -5 || true

    # Install PyTorch (needed for tensor tests)
    pip install --quiet torch torchvision 2>&1 | tail -1 || true

    # Try pytorch3d (needed for rendering tests)
    pip install --quiet "pytorch3d @ git+https://github.com/facebookresearch/pytorch3d" 2>&1 | tail -3 || \
        log "  ⚠️  pytorch3d install failed (rendering tests may fail)"
fi

# Install project in dev mode
pip install --quiet -e "$Source_Code_Root/$PROJECT_FOLDER" --no-deps 2>&1 | tail -1 || true

# Quick sanity check
log "  🧪 Test collection check..."
cd "$Source_Code_Root/$PROJECT_FOLDER"
pytest --collect-only 2>&1 | tail -3 || true
cd "$WORK_DIR"

# =================================================================
# Run pass@k + recall@k for all levels × rounds
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ Running evaluation (pass@k + recall@k)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for level in "${student_levels[@]}"; do
    log "  === $level ==="
    OUT_DIR="$WORK_DIR/output/student_posttest/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level"

    for rdx in $(seq 1 $MAX_ROUNDS); do
        COMP_FILE="$OUT_DIR/round_${rdx}/completion.jsonl"
        LOG_DIR="$OUT_DIR/round_${rdx}"
        TEST_LOG="$LOG_DIR/test_results.jsonl"

        if [ ! -f "$COMP_FILE" ]; then
            continue
        fi

        COMP_LINES=$(wc -l < "$COMP_FILE")
        if [ "$COMP_LINES" -eq 0 ]; then
            continue
        fi

        # Skip if already evaluated
        if [ -f "$TEST_LOG" ]; then
            DONE_LINES=$(wc -l < "$TEST_LOG")
            if [ "$DONE_LINES" -ge "$COMP_LINES" ]; then
                log "    round_${rdx}: already evaluated ($DONE_LINES results)"
                continue
            fi
        fi

        log "    round_${rdx}: evaluating $COMP_LINES completions..."

        # pass@k
        PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/pass_k.py" \
            --output_file "$COMP_FILE" \
            --log_file "$TEST_LOG" \
            --data_file "$FILTERED_META" \
            --source_code_root "$Source_Code_Root" \
            --k "1,3,5,10" --n $N 2>&1 || true

        # recall@k
        DEP_DIR="$Dependency_Root/$PROJECT_FOLDER"
        if [ -d "$DEP_DIR" ]; then
            DEP_LOG="$LOG_DIR/dependency_results.jsonl"
            PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/recall_k.py" \
                --output_file "$COMP_FILE" \
                --log_file "$DEP_LOG" \
                --data_file "$FILTERED_META" \
                --source_code_root "$Source_Code_Root" \
                --dependency_data_root "$Dependency_Root" \
                --k "1,3,5,10" 2>&1 || true
        fi
    done
done

# ── Cleanup ──
deactivate
rm -rf "$VENV_DIR"

# =================================================================
# RESULTS SUMMARY
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ RESULTS SUMMARY: $NS_PREFIX ($PROJECT_FOLDER)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

conda activate coding-tutor

python3 -c "
import json, os, numpy as np
from collections import defaultdict

def compute_pass_at_k(n, c, k):
    if n - c < k: return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))

ns_prefix = '$NS_PREFIX'
tutor_dir = '$TUTOR_MODEL_DIR'
base = '$WORK_DIR/output/student_posttest/$NS_PREFIX/traver'
levels = ['low_level', 'med_level', 'high_level']
n = $N
k_list = [1, 3, 5, 10]

# Load filtered metadata
benchmark_data = {}
with open('$FILTERED_META') as f:
    for line in f:
        js = json.loads(line)
        benchmark_data[js['namespace']] = js

print()
for level in levels:
    print(f'  === {level} ===')
    for rdx in range(1, 9):
        log_file = os.path.join(base, tutor_dir, level, f'round_{rdx}', 'test_results.jsonl')
        comp_file = os.path.join(base, tutor_dir, level, f'round_{rdx}', 'completion.jsonl')
        if not os.path.exists(log_file) or not os.path.exists(comp_file):
            continue

        passed = defaultdict(set)
        with open(log_file) as f:
            for line in f:
                js = json.loads(line)
                if js.get('Result') == 'Pass':
                    passed[js['namespace']].add(js['completion'])

        results = {}
        with open(comp_file) as f:
            for line in f:
                js = json.loads(line)
                ns = js['namespace']
                if ns in benchmark_data:
                    if ns not in results: results[ns] = 0
                    if ns in passed and js['completion'] in passed[ns]:
                        results[ns] += 1

        if not results: continue
        nonzero = sum(1 for v in results.values() if v > 0)
        metrics = []
        for k in k_list:
            if k > n: continue
            pak = np.mean([compute_pass_at_k(n, c, k) for c in results.values()])
            metrics.append(f'P@{k}={pak*100:.1f}%')
        print(f'    round_{rdx}: {\" | \".join(metrics)}  ({nonzero}/{len(results)} passed)')
    print()

# Paper comparison
print('  === Paper Reference ===')
print('    low_level:  Pass@1=23.3%, Pass@10=33.3%')
print('    med_level:  Pass@1=14.2%, Pass@10=25.0%')
print('    high_level: Pass@1=23.3%, Pass@10=33.3%')
" 2>&1 || echo "  (results report failed)"

TOTAL_ELAPSED=$((SECONDS - PIPELINE_START))
echo ""
echo "================================================================="
log "  ✅ EasyVolcap Pipeline Complete"
log "  Total time: $(fmt_time $TOTAL_ELAPSED)"
echo "================================================================="
