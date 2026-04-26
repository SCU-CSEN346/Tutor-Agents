#!/bin/bash
# =================================================================
# Evaluation-by-Project: Local Mac version
# =================================================================
# Equivalent to eval_by_project.slurm but runs locally on macOS.
# Uses Python 3.11 (via pyenv) to fix StrEnum import errors.
#
# Prerequisites:
#   - pyenv install 3.11.9
#   - Completion files synced from HPC to output/student_posttest/
#
# Usage:
#   bash scripts/local/eval_by_project_local.sh
# =================================================================

set -o pipefail

# --- Paths ---
REPO_DIR="/Users/catherine/PycharmProjects/Coding-Tutor"
WORK_DIR="$REPO_DIR/Coding-Tutor"
ECB_ROOT="$REPO_DIR/benchmark_data/Tutor-Agents"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
VENV_DIR="$REPO_DIR/.eval_venv_local"
metadata_file="$REPO_DIR/benchmark/EvoCodeBench-2403/metadata_filtered.jsonl"

# --- Config ---
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
tutor_setting="traver"
student_levels=(low_level med_level high_level)
rounds=(1 2 3 4 5 6 7 8)
n=10

# Python 3.12 via pyenv (3.12 required by Python-Type-Challenges; StrEnum still available)
PYTHON3="$(pyenv root)/versions/3.12.4/bin/python3.12"
if [ ! -f "$PYTHON3" ]; then
    echo "❌ Python 3.12.4 not found at $PYTHON3"
    echo "   Run: pyenv install 3.12.4"
    exit 1
fi

# Projects (must match Source_Code subdirectory names exactly)
PROJECTS=(
    Python-Type-Challenges
    microsearch
    stable-diffusion-webui-forge
    UHGEval
    searcharray
    AutoRAG
    microagents
    EasyVolcap
    camp_zipnerf
    litdata
)

# Projects to skip — platform-incompatible on macOS (Linux/GPU/CUDA deps).
# Their test suites cannot collect any tests locally; results would be
# artificially 0% and are excluded from Pass@k / Recall@k averages.
# See evaluation_findings.txt for details.
SKIP_PROJECTS=(
    microsearch          # test collection error: missing platform-specific deps
    EasyVolcap           # requires CUDA/GPU (OpenGL/CUDA extensions)
    camp_zipnerf         # requires tensorflow==2.15.0.post1 (Linux-only build)
    stable-diffusion-webui-forge  # requires CUDA/GPU (torch+xformers)
)

# Packages needed by pass_k.py / recall_k.py (jinja2 required by pyan_zyf_v2 in recall_k)
EVAL_DEPS="numpy tqdm psutil func_timeout tree_sitter pytest pytest-runner dill jinja2"

# --- Helper ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "================================================================="
echo "  Evaluation-by-Project (Local Mac, Python 3.11)"
echo "================================================================="
echo "  Projects:    ${#PROJECTS[@]}"
echo "  Levels:      ${student_levels[*]}"
echo "  Rounds:      ${rounds[*]}"
echo "  Metadata:    $metadata_file"
echo "  Python:      $($PYTHON3 --version)"
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

    # Check if this project is in the skip list
    SKIP=false
    for skip_proj in "${SKIP_PROJECTS[@]}"; do
        if [ "$skip_proj" = "$project" ]; then
            SKIP=true
            break
        fi
    done
    if [ "$SKIP" = true ]; then
        log "  ⏭️  Skipping $project (platform-incompatible: Linux/GPU deps)"
        continue
    fi

    # ── Step 1: Create venv with Python 3.11 ──
    log "  🔧 Creating isolated venv (Python 3.11)..."
    rm -rf "$VENV_DIR"
    "$PYTHON3" -m venv "$VENV_DIR"
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
    elif [ -f "$PYPROJECT" ]; then
        log "  📦 Installing $project via pyproject.toml..."
        pip install --quiet -e "$PROJ_SOURCE" 2>&1 | tail -1 || true
    fi

    # Project-specific dependency overrides (fix known version conflicts)
    case "$project" in
        microagents)
            # microagents tests require openai==1.12.0 (newer SDK breaks attribute access)
            log "  📦 Pinning openai==1.12.0 for microagents..."
            pip install --quiet "openai==1.12.0" 2>&1 | tail -1 || true
            ;;
    esac

    # Quick test collection check
    log "  🧪 Checking test collection..."
    COLLECT_RESULT=$(cd "$PROJ_SOURCE" && pytest --collect-only -q 2>&1 | tail -2 || true)
    log "     $COLLECT_RESULT"

    # ── Step 2: Create filtered data file for this project ──
    FILTERED_DATA="$VENV_DIR/data_filtered.jsonl"
    "$PYTHON3" -c "
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

    # Check if we have any tasks at all for this project
    TASK_COUNT=$(wc -l < "$FILTERED_DATA" | tr -d ' ')
    if [ "$TASK_COUNT" -eq 0 ]; then
        log "  ⏭️  No tasks in metadata for $project, skipping"
        deactivate
        rm -rf "$VENV_DIR"
        PROJECTS_FAIL=$((PROJECTS_FAIL + 1))
        continue
    fi

    # ── Step 3: Run pass@k + recall@k for all levels × rounds ──
    for level in "${student_levels[@]}"; do
        for rdx in "${rounds[@]}"; do
            COMP_FILE="$REPO_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
            LOG_DIR="$REPO_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}"

            if [ ! -f "$COMP_FILE" ]; then
                log "  ⏭️  $level/round_${rdx}: no completion file, skipping level"
                break  # no more rounds for this level
            fi

            # Count tasks for this project by matching namespaces from filtered metadata
            # (completion files use namespace format, not directory paths)
            PROJ_LINES=$("$PYTHON3" -c "
import json
namespaces = set()
with open('$FILTERED_DATA') as f:
    for line in f:
        namespaces.add(json.loads(line)['namespace'])
count = 0
with open('$COMP_FILE') as f:
    for line in f:
        if json.loads(line).get('namespace') in namespaces:
            count += 1
print(count)
" 2>/dev/null || echo 0)
            if [ "$PROJ_LINES" -eq 0 ]; then
                log "  ⏭️  $level/round_${rdx}: 0 tasks for $project, skipping level"
                break  # conversation ended for this project at this level
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
# FINAL: Aggregate results across all projects (skipped ones excluded)
# =================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ AGGREGATE RESULTS (platform-compatible projects only)"
echo "  Excluded (Linux/GPU deps): ${SKIP_PROJECTS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

"$PYTHON3" -c "
import json, os, numpy as np
from collections import defaultdict

def compute_pass_at_k(n, c, k):
    if n - c < k:
        return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))

tutor_setting = 'traver'
tutor_dir = '$TUTOR_MODEL_DIR'
base = '$REPO_DIR/output/student_posttest'
levels = ['low_level', 'med_level', 'high_level']
rounds_list = [1,2,3,4,5,6,7,8]
n = $n
k_list = [1,3,5,10]

# Projects excluded from Mac evaluation (platform-incompatible)
skip_projects = ['microsearch', 'EasyVolcap', 'camp_zipnerf', 'stable-diffusion-webui-forge']

benchmark_data = {}
skip_namespaces = set()
with open('$metadata_file') as f:
    for line in f:
        js = json.loads(line)
        benchmark_data[js['namespace']] = js
        proj = js.get('completion_path', '').split('/')[0]
        if proj in skip_projects:
            skip_namespaces.add(js['namespace'])

print(f'  (Excluding {len(skip_namespaces)} namespaces from {len(skip_projects)} platform-incompatible projects)')
print()
for level in levels:
    print(f'  === {level} ===')
    for rdx in rounds_list:
        log_file = os.path.join(base, tutor_setting, tutor_dir, level, f'round_{rdx}', 'test_results.jsonl')
        comp_file = os.path.join(base, tutor_setting, tutor_dir, level, f'round_{rdx}', 'completion.jsonl')
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
                if ns in benchmark_data and ns not in skip_namespaces:
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
" 2>&1 || echo "  (aggregate report failed)"

TOTAL_ELAPSED=$((SECONDS - TOTAL_START))
echo ""
echo "================================================================="
echo "  Evaluation Complete"
echo "================================================================="
echo "  Projects OK:     $PROJECTS_OK / ${#PROJECTS[@]}"
echo "  Projects failed: $PROJECTS_FAIL"
echo "  Total time:      $(printf '%dh %dm %ds' $((TOTAL_ELAPSED/3600)) $((TOTAL_ELAPSED%3600/60)) $((TOTAL_ELAPSED%60)))"
echo "================================================================="
