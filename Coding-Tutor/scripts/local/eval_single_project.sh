#!/bin/bash
# =================================================================
# Single-Project Evaluation Script
# =================================================================
# Usage: bash scripts/local/eval_single_project.sh <project_name>
# Example: bash scripts/local/eval_single_project.sh litdata
# =================================================================

set -o pipefail

PROJECT="$1"
if [ -z "$PROJECT" ]; then
    echo "Usage: $0 <project_name>"
    echo "Available projects:"
    ls /Users/catherine/PycharmProjects/Coding-Tutor/benchmark_data/Tutor-Agents/Source_Code/
    exit 1
fi

# --- Paths ---
REPO_DIR="/Users/catherine/PycharmProjects/Coding-Tutor"
WORK_DIR="$REPO_DIR/Coding-Tutor"
ECB_ROOT="$REPO_DIR/benchmark_data/Tutor-Agents"
Source_Code_Root="$ECB_ROOT/Source_Code"
Dependency_Root="$ECB_ROOT/Dependency_Data"
VENV_DIR="$REPO_DIR/.eval_venv_single"
metadata_file="$REPO_DIR/benchmark/EvoCodeBench-2403/metadata_filtered.jsonl"

# --- Config ---
TUTOR_MODEL_DIR="Llama-3.1-70B-Instruct"
tutor_setting="traver"
student_levels=(low_level med_level high_level)
rounds=(1 2 3 4 5 6 7 8)
n=10

PYTHON3="$(pyenv root)/versions/3.12.4/bin/python3.12"
if [ ! -f "$PYTHON3" ]; then
    echo "❌ Python 3.12.4 not found at $PYTHON3"
    exit 1
fi

PROJ_SOURCE="$Source_Code_Root/$PROJECT"
if [ ! -d "$PROJ_SOURCE" ]; then
    echo "❌ Source code not found at $PROJ_SOURCE"
    exit 1
fi

EVAL_DEPS="numpy tqdm psutil func_timeout tree_sitter pytest pytest-runner dill jinja2"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

echo "================================================================="
echo "  Single-Project Evaluation: $PROJECT"
echo "================================================================="

# ── Step 1: Create venv ──
log "🔧 Creating isolated venv..."
rm -rf "$VENV_DIR"
"$PYTHON3" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip 2>&1 | tail -1

log "📦 Installing eval dependencies..."
pip install --quiet $EVAL_DEPS 2>&1 | tail -1 || true

# Install project-specific requirements
REQ="$PROJ_SOURCE/requirements.txt"
SETUP="$PROJ_SOURCE/setup.py"
PYPROJECT="$PROJ_SOURCE/pyproject.toml"
if [ -f "$REQ" ]; then
    log "📦 Installing $PROJECT requirements.txt..."
    pip install -r "$REQ" 2>&1 | tail -5 || log "⚠️  Some deps failed (non-fatal)"
fi
if [ -f "$SETUP" ]; then
    log "📦 Installing $PROJECT via setup.py..."
    pip install -e "$PROJ_SOURCE" 2>&1 | tail -3 || true
elif [ -f "$PYPROJECT" ]; then
    log "📦 Installing $PROJECT via pyproject.toml..."
    pip install -e "$PROJ_SOURCE" 2>&1 | tail -3 || true
fi

# Project-specific dependency overrides
case "$PROJECT" in
    microagents)
        log "📦 Pinning openai==1.12.0 for microagents..."
        pip install --quiet "openai==1.12.0" 2>&1 | tail -1 || true
        ;;
esac

# Quick test collection check
log "🧪 Checking test collection..."
COLLECT_RESULT=$(cd "$PROJ_SOURCE" && pytest --collect-only -q 2>&1 | tail -5 || true)
echo "   $COLLECT_RESULT"

# ── Step 2: Create filtered data file ──
FILTERED_DATA="$VENV_DIR/data_filtered.jsonl"
"$PYTHON3" -c "
import json
count = 0
with open('$metadata_file') as f, open('$FILTERED_DATA', 'w') as out:
    for line in f:
        js = json.loads(line)
        if js['completion_path'].startswith('$PROJECT/'):
            out.write(line)
            count += 1
print(f'📋 {count} tasks for $PROJECT')
"

TASK_COUNT=$(wc -l < "$FILTERED_DATA" | tr -d ' ')
if [ "$TASK_COUNT" -eq 0 ]; then
    log "⏭️  No tasks in metadata for $PROJECT"
    deactivate
    rm -rf "$VENV_DIR"
    exit 1
fi

# ── Step 3: Run pass@k + recall@k ──
for level in "${student_levels[@]}"; do
    for rdx in "${rounds[@]}"; do
        COMP_FILE="$REPO_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}/completion.jsonl"
        LOG_DIR="$REPO_DIR/output/student_posttest/$tutor_setting/$TUTOR_MODEL_DIR/$level/round_${rdx}"

        if [ ! -f "$COMP_FILE" ]; then
            log "  ⏭️  $level/round_${rdx}: no completion file, skipping level"
            break
        fi

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
            log "  ⏭️  $level/round_${rdx}: 0 tasks for $PROJECT, skipping level"
            break
        fi

        log "📝 $level/round_${rdx} ($PROJ_LINES completions)"

        # --- pass@k ---
        PYTHONPATH="$WORK_DIR:$WORK_DIR/traver" python "$WORK_DIR/traver/parser/pass_k.py" \
            --output_file "$COMP_FILE" \
            --log_file "$LOG_DIR/test_results.jsonl" \
            --data_file "$FILTERED_DATA" \
            --source_code_root "$Source_Code_Root" \
            --k "1,3,5,10" --n $n 2>&1 | grep -v "^$" || true

        # --- recall@k ---
        if [ -d "$Dependency_Root/$PROJECT" ]; then
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
log "🗑️  Removing venv..."
rm -rf "$VENV_DIR"
log "✓ $PROJECT evaluation complete"
