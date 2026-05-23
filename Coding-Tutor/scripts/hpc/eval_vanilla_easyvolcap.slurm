#!/bin/bash
#SBATCH --job-name="vanilla-ev"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="vanilla_ev_eval_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Vanilla EasyVolcap: Posttest → Codegen → Eval
# =================================================================
# Uses Vanilla dialogues (up to 8 rounds) for posttest
# code generation and evaluation. Dialogues are assumed to be
# uploaded directly to the cluster.
#
# Usage:
#   export HF_TOKEN="hf_your_key_here"
#   sbatch scripts/hpc/eval_vanilla_easyvolcap.slurm
# =================================================================

set -o pipefail

# ── Paths ──
GROUP_DIR="/WAVE/projects/CSEN-346-Sp26/Group2"
REPO_DIR="$GROUP_DIR/Coding-Tutor"
WORK_DIR="$REPO_DIR"
ECB_ROOT="$REPO_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
VENV_DIR="$REPO_DIR/.eval_venv_vanilla_ev"

# ── Config ──
HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN before running}"
TUTOR_MODEL="meta-llama/Llama-3.1-70B-Instruct"
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
CODEGEN_MODEL="meta-llama/Llama-3.1-8B-Instruct"
CODEGEN_API_BASE="https://router.huggingface.co/v1"

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

# ── Vanilla paths ──
DIALOG_BASE="$GROUP_DIR/output_vanilla_4projects/dialogue_vanilla"
POSTTEST_BASE="$WORK_DIR/output/student_posttest/vanilla"

# ── Environment ──
module load CUDA/12.6.2
source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$WORK_DIR"

# ── Helpers ──
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
fmt_time() { printf '%dh %dm %ds' $(($1/3600)) $(($1%3600/60)) $(($1%60)); }

echo "================================================================="
echo "  Vanilla EasyVolcap Evaluation"
echo "================================================================="
echo "  Namespace:   $NS_PREFIX"
echo "  Folder:      $PROJECT_FOLDER"
echo "  Codegen:     $CODEGEN_MODEL (HF API)"
echo "  Dialogue:    $DIALOG_BASE/$NS_PREFIX/dialogue/vanilla/$TUTOR_MODEL_DIR/"
echo "  Output:      $POSTTEST_BASE/$NS_PREFIX/"
echo "  N=$N, T=$T, top_p=$TOP_P, max_rounds=$MAX_ROUNDS"
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
    log "▶ $NS_PREFIX | $level (Vanilla)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LEVEL_START=$SECONDS

    # ── Step 1: Verify Vanilla dialogue exists locally ──
    LOCAL_DIALOG_DIR="$DIALOG_BASE/$NS_PREFIX/dialogue/vanilla/$TUTOR_MODEL_DIR/$level"
    LOCAL_DIALOG="$LOCAL_DIALOG_DIR/simulated_dialogs.jsonl"

    if [ -f "$LOCAL_DIALOG" ]; then
        NUM_D=$(wc -l < "$LOCAL_DIALOG")
        log "  ✓ Vanilla dialogue exists locally ($NUM_D entries)"
    else
        log "  ❌ No Vanilla dialogue found at $LOCAL_DIALOG. Please upload it."
        continue
    fi

    # ── Step 2: Generate posttest prompts ──
    OUT_DIR="$POSTTEST_BASE/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level"
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

rm -rf "$VENV_DIR"
python -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip 2>&1 | tail -1

EVAL_DEPS="numpy tqdm psutil func_timeout tree_sitter pytest pytest-runner dill jinja2"
pip install --quiet $EVAL_DEPS 2>&1 | tail -1

REQ="$Source_Code_Root/$PROJECT_FOLDER/requirements.txt"
if [ -f "$REQ" ]; then
    log "  📦 Installing EasyVolcap requirements..."
    cat "$REQ" | sed -e '/^\s*#.*$/d' -e '/^\s*$/d' | \
        grep -v "git+" | grep -v "cuda-python" | grep -v "pyopengl" | \
        grep -v "open3d" | grep -v "torch-scatter" | \
        xargs -n 1 pip install --quiet 2>&1 | tail -5 || true
    pip install --quiet torch torchvision 2>&1 | tail -1 || true
    pip install --quiet "pytorch3d @ git+https://github.com/facebookresearch/pytorch3d" 2>&1 | tail -3 || \
        log "  ⚠️  pytorch3d install failed (rendering tests may fail)"
fi

pip install --quiet -e "$Source_Code_Root/$PROJECT_FOLDER" --no-deps 2>&1 | tail -1 || true

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
    OUT_DIR="$POSTTEST_BASE/$NS_PREFIX/traver/$TUTOR_MODEL_DIR/$level"

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

        if [ -f "$TEST_LOG" ]; then
            DONE_LINES=$(wc -l < "$TEST_LOG")
            if [ "$DONE_LINES" -ge "$COMP_LINES" ]; then
                log "    round_${rdx}: already evaluated ($DONE_LINES results)"
                continue
            fi
        fi

        log "    round_${rdx}: evaluating $COMP_LINES completions..."

        PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/pass_k.py" \
            --output_file "$COMP_FILE" \
            --log_file "$TEST_LOG" \
            --data_file "$FILTERED_META" \
            --source_code_root "$Source_Code_Root" \
            --k "1,3,5,10" --n $N 2>&1 || true

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
# RESULTS SUMMARY: Vanilla vs Baseline
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "▶ RESULTS: $NS_PREFIX Vanilla"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

conda activate coding-tutor

python3 -c "
import json, os, numpy as np
from collections import defaultdict

def compute_pass_at_k(n, c, k):
    if n - c < k: return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))

def eval_dir(base_dir, tutor_dir, levels, n, k_list, max_rounds=8):
    results = {}
    for level in levels:
        results[level] = {}
        for rdx in range(1, max_rounds + 1):
            log_file = os.path.join(base_dir, tutor_dir, level, f'round_{rdx}', 'test_results.jsonl')
            comp_file = os.path.join(base_dir, tutor_dir, level, f'round_{rdx}', 'completion.jsonl')
            if not os.path.exists(log_file) or not os.path.exists(comp_file):
                continue

            passed = defaultdict(set)
            with open(log_file) as f:
                for line in f:
                    js = json.loads(line)
                    if js.get('Result') == 'Pass':
                        passed[js['namespace']].add(js['completion'])

            task_results = {}
            with open(comp_file) as f:
                for line in f:
                    js = json.loads(line)
                    ns = js['namespace']
                    if ns not in task_results: task_results[ns] = 0
                    if ns in passed and js['completion'] in passed[ns]:
                        task_results[ns] += 1

            if task_results:
                metrics = {}
                for k in k_list:
                    if k > n: continue
                    pak = np.mean([compute_pass_at_k(n, c, k) for c in task_results.values()])
                    metrics[k] = pak * 100
                nonzero = sum(1 for v in task_results.values() if v > 0)
                results[level][rdx] = {'metrics': metrics, 'nonzero': nonzero, 'total': len(task_results)}
    return results

tutor_dir = '$TUTOR_MODEL_DIR'
n = $N
k_list = [1, 3, 5, 10]
levels = ['low_level', 'med_level', 'high_level']

# Vanilla results
mc_base = '$POSTTEST_BASE/$NS_PREFIX/traver'
mc = eval_dir(mc_base, tutor_dir, levels, n, k_list)

print()
for level in levels:
    print(f'  === {level} ===')
    print(f'  {\"Round\":>7s}  {\"Vanilla P@1\":>14s}')
    print(f'  {\"─\"*7:>7s}  {\"─\"*14:>14s}')
    for rdx in range(1, 9):
        mc_p1 = mc.get(level, {}).get(rdx, {}).get('metrics', {}).get(1, None)
        mc_str = f'{mc_p1:.1f}%' if mc_p1 is not None else '  —'
        print(f'  R{rdx:>5d}  {mc_str:>14s}')
    print()

print('  === Paper Reference ===')
print('    low_level:  Pass@1=23.3%, Pass@10=33.3%')
print('    med_level:  Pass@1=14.2%, Pass@10=25.0%')
print('    high_level: Pass@1=23.3%, Pass@10=33.3%')
" 2>&1 || echo "  (results report failed)"

TOTAL_ELAPSED=$((SECONDS - PIPELINE_START))
echo ""
echo "================================================================="
log "  ✅ Vanilla EasyVolcap Pipeline Complete"
log "  Total time: $(fmt_time $TOTAL_ELAPSED)"
echo "================================================================="
