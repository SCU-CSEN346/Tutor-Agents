#!/bin/bash
# =================================================================
# EvoCodeBench: Download & Environment Setup (Full 100 Tasks)
# =================================================================
# Downloads the 14 projects needed for all 100 Coding-Tutor tasks,
# installs deps into the shared conda env, and updates test paths.
#
# TOTAL DATA: ~1.2GB compressed, ~3-4GB uncompressed (14 of 25 projects)
# SHARED CONDA ENV: deps installed into coding-tutor (no per-project venvs)
# GRAND TOTAL: ~4-6GB (fits within the 30GB project budget)
#
# Usage:
#   bash scripts/hpc/setup_evocodebench.sh
# =================================================================

set -e

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
ECB_DIR="$PROJECT_DIR/EvoCodeBench-2403"
SOURCE_CODE="$ECB_DIR/Source_Code"
DEPENDENCY_DATA="$ECB_DIR/Dependency_Data"
DATA_FILE="$ECB_DIR/data.jsonl"

# All 14 projects needed for the full 100-task dataset (all 5 folds)
NEEDED_PROJECTS=(
    AutoRAG
    EasyVolcap
    Generalizable-BEV
    Python-Type-Challenges
    UHGEval
    UniRef
    camp_zipnerf
    litdata
    microagents
    microsearch
    nlm-ingestor
    open-iris
    searcharray
    stable-diffusion-webui-forge
)

echo "================================================================="
echo "  EvoCodeBench Setup (14/25 projects — full 100 tasks)"
echo "================================================================="
echo "  Target:   $ECB_DIR"
echo "  Projects: ${#NEEDED_PROJECTS[@]}"
echo "  Start:    $(date)"
echo ""

# =================================================================
# STEP 1: Download from HuggingFace (if not already present)
# =================================================================
echo "[1/4] Downloading EvoCodeBench-2403 data..."

mkdir -p "$ECB_DIR"

# Download to PROJECT_DIR so the repo path "EvoCodeBench-2403/..." maps
# correctly to $ECB_DIR (avoids nested EvoCodeBench-2403/EvoCodeBench-2403/)

if [ ! -f "$ECB_DIR/Source_Code.tar.gz" ] && [ ! -d "$SOURCE_CODE" ]; then
    echo "  Downloading Source_Code.tar.gz (~1GB)..."
    if command -v hf &>/dev/null; then
        hf download LJ0815/EvoCodeBench \
            EvoCodeBench-2403/Source_Code.tar.gz \
            --repo-type dataset \
            --local-dir "$PROJECT_DIR" \
            --local-dir-use-symlinks False 2>/dev/null || \
        wget -q -O "$ECB_DIR/Source_Code.tar.gz" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/Source_Code.tar.gz"
    else
        wget -q -O "$ECB_DIR/Source_Code.tar.gz" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/Source_Code.tar.gz"
    fi
    echo "  ✓ Downloaded Source_Code.tar.gz"
else
    echo "  ✓ Source_Code already present"
fi

if [ ! -f "$ECB_DIR/Dependency_Data.tar.gz" ] && [ ! -d "$DEPENDENCY_DATA" ]; then
    echo "  Downloading Dependency_Data.tar.gz (~160MB)..."
    if command -v hf &>/dev/null; then
        hf download LJ0815/EvoCodeBench \
            EvoCodeBench-2403/Dependency_Data.tar.gz \
            --repo-type dataset \
            --local-dir "$PROJECT_DIR" \
            --local-dir-use-symlinks False 2>/dev/null || \
        wget -q -O "$ECB_DIR/Dependency_Data.tar.gz" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/Dependency_Data.tar.gz"
    else
        wget -q -O "$ECB_DIR/Dependency_Data.tar.gz" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/Dependency_Data.tar.gz"
    fi
    echo "  ✓ Downloaded Dependency_Data.tar.gz"
else
    echo "  ✓ Dependency_Data already present"
fi

# Download data.jsonl (metadata)
if [ ! -f "$DATA_FILE" ]; then
    echo "  Downloading data.jsonl..."
    if command -v hf &>/dev/null; then
        hf download LJ0815/EvoCodeBench \
            EvoCodeBench-2403/data.jsonl \
            --repo-type dataset \
            --local-dir "$PROJECT_DIR" \
            --local-dir-use-symlinks False 2>/dev/null || \
        wget -q -O "$DATA_FILE" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/data.jsonl"
    else
        wget -q -O "$DATA_FILE" \
            "https://huggingface.co/datasets/LJ0815/EvoCodeBench/resolve/main/EvoCodeBench-2403/data.jsonl"
    fi
    echo "  ✓ Downloaded data.jsonl"
fi

# Fix: if files ended up in nested dir, move them up
if [ -d "$ECB_DIR/EvoCodeBench-2403" ]; then
    echo "  Fixing nested directory structure..."
    mv "$ECB_DIR/EvoCodeBench-2403"/* "$ECB_DIR/" 2>/dev/null || true
    rmdir "$ECB_DIR/EvoCodeBench-2403" 2>/dev/null || true
fi

cd "$ECB_DIR"

# =================================================================
# STEP 2: Extract ONLY needed projects (not the full archive)
# =================================================================
echo ""
echo "[2/4] Extracting subset projects from archives..."

if [ -f "Source_Code.tar.gz" ] && [ ! -d "$SOURCE_CODE" ]; then
    mkdir -p "$SOURCE_CODE"
    
    # Extract only the projects we need (saves disk space!)
    for proj in "${NEEDED_PROJECTS[@]}"; do
        echo "  Extracting Source_Code/$proj..."
        tar -xzf Source_Code.tar.gz "Source_Code/$proj" \
            --strip-components=1 -C "$SOURCE_CODE/" 2>/dev/null || \
        # Some archives might have different root dir names
        tar -xzf Source_Code.tar.gz "*/$proj" \
            --strip-components=1 -C "$SOURCE_CODE/" 2>/dev/null || \
        echo "  ⚠  Could not extract $proj (may need manual extraction)"
    done
    
    # If selective extraction failed, fall back to full extract + delete
    EXTRACTED=$(ls "$SOURCE_CODE" 2>/dev/null | wc -l)
    if [ "$EXTRACTED" -lt 5 ]; then
        echo "  Selective extraction failed. Extracting full archive..."
        tar -xzf Source_Code.tar.gz
        # If extracted to a subdirectory, move contents up
        if [ -d "Source_Code" ] && [ "$SOURCE_CODE" != "$(pwd)/Source_Code" ]; then
            mv Source_Code/* "$SOURCE_CODE/" 2>/dev/null || true
        fi
        
        # Delete projects we DON'T need to save space
        echo "  Removing unneeded projects..."
        for dir in "$SOURCE_CODE"/*/; do
            proj_name=$(basename "$dir")
            KEEP=false
            for needed in "${NEEDED_PROJECTS[@]}"; do
                if [ "$proj_name" == "$needed" ]; then
                    KEEP=true
                    break
                fi
            done
            if [ "$KEEP" == "false" ]; then
                echo "    Removing: $proj_name"
                rm -rf "$dir"
            fi
        done
    fi
    
    # Remove the archive to save space
    echo "  Removing Source_Code.tar.gz to save space..."
    rm -f Source_Code.tar.gz
    echo "  ✓ Source code extracted (subset only)"
else
    echo "  ✓ Source code already extracted"
fi

if [ -f "Dependency_Data.tar.gz" ] && [ ! -d "$DEPENDENCY_DATA" ]; then
    mkdir -p "$DEPENDENCY_DATA"
    
    # Extract only needed projects
    for proj in "${NEEDED_PROJECTS[@]}"; do
        tar -xzf Dependency_Data.tar.gz "Dependency_Data/$proj" \
            --strip-components=1 -C "$DEPENDENCY_DATA/" 2>/dev/null || true
    done
    
    EXTRACTED=$(ls "$DEPENDENCY_DATA" 2>/dev/null | wc -l)
    if [ "$EXTRACTED" -lt 3 ]; then
        echo "  Extracting full dependency archive..."
        tar -xzf Dependency_Data.tar.gz
        if [ -d "Dependency_Data" ] && [ "$DEPENDENCY_DATA" != "$(pwd)/Dependency_Data" ]; then
            mv Dependency_Data/* "$DEPENDENCY_DATA/" 2>/dev/null || true
        fi
        
        # Delete unneeded
        for dir in "$DEPENDENCY_DATA"/*/; do
            proj_name=$(basename "$dir")
            KEEP=false
            for needed in "${NEEDED_PROJECTS[@]}"; do
                if [ "$proj_name" == "$needed" ]; then
                    KEEP=true
                    break
                fi
            done
            if [ "$KEEP" == "false" ]; then
                rm -rf "$dir"
            fi
        done
    fi
    
    rm -f Dependency_Data.tar.gz
    echo "  ✓ Dependency data extracted (subset only)"
else
    echo "  ✓ Dependency data already extracted"
fi

# =================================================================
# STEP 3: Install project deps into shared conda env
# =================================================================
echo ""
echo "[3/4] Installing project dependencies into shared conda env..."
echo "  (No per-project venvs — saves ~13GB of duplicated packages)"
echo ""

# Make sure conda env is active
eval "$(conda shell.bash hook)" 2>/dev/null || true
conda activate coding-tutor 2>/dev/null || true

# Install pytest (shared)
pip install --quiet pytest pytest-runner 2>/dev/null

STEP=1
for proj in "${NEEDED_PROJECTS[@]}"; do
    PROJ_PATH="$SOURCE_CODE/$proj"
    if [ ! -d "$PROJ_PATH" ]; then
        echo "  ⚠  [$STEP/${#NEEDED_PROJECTS[@]}] Skipping $proj (not found)"
        STEP=$((STEP + 1))
        continue
    fi
    
    echo "  [$STEP/${#NEEDED_PROJECTS[@]}] Installing deps for $proj..."
    cd "$PROJ_PATH"
    
    if [ -f "requirements.txt" ]; then
        pip install --quiet -r requirements.txt 2>/dev/null || \
            echo "    ⚠  Some deps failed (non-fatal)"
    fi
    
    STEP=$((STEP + 1))
done

# =================================================================
# STEP 4: Update test paths
# =================================================================
echo ""
echo "[4/4] Updating test paths..."

cd "$PROJECT_DIR"
# Use the EvoCodeBench-main update script if available, or the inline version
if [ -f "EvoCodeBench-main/update_test_path.py" ]; then
    python3 EvoCodeBench-main/update_test_path.py \
        --data_path "$DATA_FILE" \
        --source_code_root "$SOURCE_CODE"
else
    python3 -c "
import json, os, sys
data_path = '$DATA_FILE'
source_code_root = '$SOURCE_CODE'
needed = set('''$(printf '%s\n' "${NEEDED_PROJECTS[@]}")'''.strip().split('\n'))

test_file_paths = []
with open(data_path, 'r') as f:
    for line in f:
        data = json.loads(line)
        project_name = data['completion_path'].split('/')[0]
        if project_name not in needed:
            continue
        project_path = os.path.join(source_code_root, project_name)
        for test in data['tests']:
            test_path = test.split('::')[0]
            if (project_path, test_path) not in test_file_paths:
                test_file_paths.append((project_path, test_path))

for project_path, test_path in test_file_paths:
    full_test_path = os.path.join(project_path, test_path)
    if not os.path.exists(full_test_path):
        continue
    with open(full_test_path, 'r') as f:
        code = f.read()
    _import = f'import sys\nsys.path.append(\"{project_path}\")\n'
    if _import not in code:
        code = _import + code
        with open(full_test_path, 'w') as f:
            f.write(code)
        print(f'Updated {full_test_path}')
"
fi
echo "  ✓ Test paths updated"

# =================================================================
# Summary
# =================================================================
echo ""
echo "================================================================="
echo "  EvoCodeBench Subset Setup Complete ✅"
echo "================================================================="
echo ""
echo "  Storage usage:"
du -sh "$SOURCE_CODE" 2>/dev/null || echo "  Source_Code: not found"
du -sh "$DEPENDENCY_DATA" 2>/dev/null || echo "  Dependency_Data: not found"
echo ""
echo "  Projects installed:"
ls -1 "$SOURCE_CODE" 2>/dev/null | while read p; do
    HAS_VENV="✗"
    [ -d "$SOURCE_CODE/$p/myenv" ] && HAS_VENV="✓"
    echo "    $HAS_VENV $p"
done

echo ""
echo "  Total:"
du -sh "$ECB_DIR"

echo ""
echo "  To run coding tests:"
echo "    bash scripts/hpc/run_coding_test_hpc.sh"
