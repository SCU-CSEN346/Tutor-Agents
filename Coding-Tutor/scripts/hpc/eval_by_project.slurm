#!/bin/bash
#SBATCH --job-name="eval-by-proj"
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --output="eval_by_project_%j.out"
#SBATCH --mail-user=cawad@scu.edu
#SBATCH --mail-type=END

# =================================================================
# Evaluation-by-Project: Isolated venv per project
# =================================================================
# Evaluates all completions (already generated) project by project.
# For each project:
#   1. Create a temporary venv
#   2. Install the project's requirements.txt + eval deps
#   3. Run pass@k and recall@k for ALL levels × rounds
#   4. Delete the venv to reclaim space
#
# After all projects, print aggregate results.
#
# Usage:
#   sbatch scripts/hpc/eval_by_project.slurm
# =================================================================

set -o pipefail

# --- Paths ---
GROUP_DIR="/WAVE/projects/CSEN-346-Sp26/Group2"
REPO_DIR="$GROUP_DIR/Coding-Tutor"
WORK_DIR="$REPO_DIR"
ECB_ROOT="$REPO_DIR/EvoCodeBench-2403"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
VENV_DIR="$REPO_DIR/.eval_venv"
RESULTS_DIR="$REPO_DIR/eval_results"

# --- Config ---
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
tutor_setting="traver"
student_levels=(low_level med_level high_level)
rounds=(1 2 3 4 5 6 7 8)
n=10
metadata_file="$ECB_ROOT/data.jsonl"

# Projects ordered by task count (smallest first for fast early results)
PROJECTS=(
    Python-Type-Challenges   # 1 task
    microsearch              # 2 tasks
    stable-diffusion-webui-forge  # 3 tasks
    UHGEval                  # 3 tasks
    searcharray              # 6 tasks
    AutoRAG                  # 13 tasks
    microagents              # 18 tasks
    EasyVolcap               # 20 tasks
    camp_zipnerf             # 54 tasks
    litdata                  # 59 tasks
)

# Packages needed by pass_k.py / recall_k.py
EVAL_DEPS="numpy tqdm psutil func_timeout tree_sitter pytest pytest-runner dill"

# --- Setup ---
module load CUDA/12.6.2
source /WAVE/apps/x86_64/packages/Anaconda3/2025.12-2/app/etc/profile.d/conda.sh
conda activate coding-tutor

cd "$WORK_DIR"
mkdir -p "$RESULTS_DIR"

# --- Helper ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "================================================================="
echo "  Evaluation-by-Project (Isolated Environments)"
echo "================================================================="
echo "  Projects:    ${#PROJECTS[@]}"
echo "  Levels:      ${student_levels[*]}"
echo "  Rounds:      ${rounds[*]}"
echo "  Metadata:    $metadata_file"
echo "  Start:       $(date)"
echo "================================================================="

TOTAL_START=$SECONDS
PROJECT_NUM=0
PROJECTS_OK=0
PROJECTS_FAIL=0

for project in "${PROJECTS[@]}"; do
    PROJECT_NUM=$((PROJECT_NUM + 1))
    PROJ_START=$SECONDS

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "▶ [$PROJECT_NUM/${#PROJECTS[@]}] $project"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    PROJ_SOURCE="$Source_Code_Root/$project"
    if [ ! -d "$PROJ_SOURCE" ]; then
        log "  ⚠️  Source code not found at $PROJ_SOURCE, skipping"
        PROJECTS_FAIL=$((PROJECTS_FAIL + 1))
        continue
    fi

    # ── Step 1: Create venv ──
    log "  🔧 Creating isolated venv..."
    rm -rf "$VENV_DIR"
    python -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install --quiet --upgrade pip 2>&1 | tail -1

    # Install eval script dependencies
    log "  📦 Installing eval dependencies..."
    pip install --quiet $EVAL_DEPS 2>&1 | tail -1 || true

    # Install project-specific requirements
    REQ="$PROJ_SOURCE/requirements.txt"
    SETUP="$PROJ_SOURCE/setup.py"
    PYPROJECT="$PROJ_SOURCE/pyproject.toml"
    if [ -f "$REQ" ]; then
        log "  📦 Installing $project requirements.txt..."
        pip install --quiet -r "$REQ" 2>&1 | tail -3 || log "  ⚠️  Some deps failed (non-fatal)"
    fi
    if [ -f "$SETUP" ]; then
        log "  📦 Installing $project via setup.py..."
        pip install --quiet -e "$PROJ_SOURCE" 2>&1 | tail -1 || true
    fi

    # Quick test collection check
    log "  🧪 Checking test collection..."
    COLLECT_RESULT=$(cd "$PROJ_SOURCE" && pytest --collect-only 2>&1 | tail -1 || true)
    log "     $COLLECT_RESULT"

    # ── Step 2: Create filtered data file for this project ──
    FILTERED_DATA="$VENV_DIR/data_filtered.jsonl"
    python -c "
import json
count = 0
with open('$metadata_file') as f, open('$FILTERED_DATA', 'w') as out:
    for line in f:
        js = json.loads(line)
        if js['completion_path'].startswith('$project/'):
            out.write(line)
            count += 1
print(f'  📋 {count} tasks for $project')
"

    # ── Step 3: Run pass@k + recall@k for all levels × rounds ──
    for level in "${student_levels[@]}"; do
        for rdx in "${rounds[@]}"; do
            COMP_FILE="$WORK_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
            LOG_DIR="$WORK_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}"

            if [ ! -f "$COMP_FILE" ]; then
                log "  ⏭️  $level/round_${rdx}: no completion file, skipping to next level"
                break  # no more rounds for this level
            fi

            # Check if this completion file has any tasks for this project
            PROJ_LINES=$(grep -c "\"$project/" "$COMP_FILE" 2>/dev/null || echo 0)
            if [ "$PROJ_LINES" -eq 0 ]; then
                log "  ⏭️  $level/round_${rdx}: 0 tasks for $project, skipping to next level"
                break  # conversation ended for this level
            fi

            log "  📝 $level/round_${rdx} ($PROJ_LINES completions)"

            # --- pass@k ---
            PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/pass_k.py" \
                --output_file "$COMP_FILE" \
                --log_file "$LOG_DIR/test_results.jsonl" \
                --data_file "$FILTERED_DATA" \
                --source_code_root "$Source_Code_Root" \
                --k "1,3,5,10" --n $n 2>&1 | grep -v "^$" || true

            # --- recall@k ---
            if [ -d "$Dependency_Root/$project" ]; then
                PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/recall_k.py" \
                    --output_file "$COMP_FILE" \
                    --log_file "$LOG_DIR/dependency_results.jsonl" \
                    --data_file "$FILTERED_DATA" \
                    --source_code_root "$Source_Code_Root" \
                    --dependency_data_root "$Dependency_Root" \
                    --k "1,3,5,10" 2>&1 | grep -v "^$" || true
            fi
        done
    done

    deactivate

    # ── Step 4: Remove venv ──
    PROJ_ELAPSED=$((SECONDS - PROJ_START))
    log "  🗑️  Removing venv..."
    rm -rf "$VENV_DIR"
    log "  ✓ $project done ($(printf '%dm %ds' $((PROJ_ELAPSED/60)) $((PROJ_ELAPSED%60))))"
    PROJECTS_OK=$((PROJECTS_OK + 1))
done

# =================================================================
# FINAL: Aggregate results across all projects
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ AGGREGATE RESULTS (all projects combined)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Re-activate base env for final reporting
conda activate coding-tutor

python3 -c "
import json, os, numpy as np
from collections import defaultdict

def compute_pass_at_k(n, c, k):
    if n - c < k:
        return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))

tutor_setting = 'traver'
tutor_dir = '$TUTOR_MODEL_DIR'
base = '$WORK_DIR/output/student_posttest'
levels = ['low_level', 'med_level', 'high_level']
rounds_list = [1,2,3,4,5,6,7,8]
n = $n
k_list = [1,3,5,10]

# Load full benchmark data
benchmark_data = {}
with open('$metadata_file') as f:
    for line in f:
        js = json.loads(line)
        benchmark_data[js['namespace']] = js

print()
for level in levels:
    print(f'  === {level} ===')
    for rdx in rounds_list:
        log_file = os.path.join(base, tutor_setting, tutor_dir, level, f'round_{rdx}', 'test_results.jsonl')
        comp_file = os.path.join(base, tutor_setting, tutor_dir, level, f'round_{rdx}', 'completion.jsonl')
        if not os.path.exists(log_file) or not os.path.exists(comp_file):
            continue

        # Collect passed completions
        passed = defaultdict(set)
        with open(log_file) as f:
            for line in f:
                js = json.loads(line)
                if js.get('Result') == 'Pass':
                    passed[js['namespace']].add(js['completion'])

        # Count passes per namespace
        results = {}
        with open(comp_file) as f:
            for line in f:
                js = json.loads(line)
                ns = js['namespace']
                if ns in benchmark_data:
                    if ns not in results:
                        results[ns] = 0
                    if ns in passed and js['completion'] in passed[ns]:
                        results[ns] += 1

        if not results:
            continue

        tested = len(results)
        nonzero = sum(1 for v in results.values() if v > 0)
        metrics = []
        for k in k_list:
            if k > n:
                continue
            pak = np.mean([compute_pass_at_k(n, c, k) for c in results.values()])
            metrics.append(f'P@{k}={pak*100:.1f}%')
        print(f'    round_{rdx}: {\" | \".join(metrics)}  ({nonzero}/{tested} tasks passed)')
    print()

print(f'  Projects evaluated: {len([r for r in results.values() if True])} tasks total')
" 2>&1 || echo "  (aggregate report failed, check individual round outputs)"

TOTAL_ELAPSED=$((SECONDS - TOTAL_START))
echo ""
echo "================================================================="
echo "  Evaluation Complete"
echo "================================================================="
echo "  Projects OK:     $PROJECTS_OK / ${#PROJECTS[@]}"
echo "  Projects failed: $PROJECTS_FAIL"
echo "  Total time:      $(printf '%dh %dm %ds' $((TOTAL_ELAPSED/3600)) $((TOTAL_ELAPSED%3600/60)) $((TOTAL_ELAPSED%60)))"
echo "================================================================="
