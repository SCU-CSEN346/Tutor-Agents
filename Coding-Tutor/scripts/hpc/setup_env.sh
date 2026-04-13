#!/bin/bash
# =================================================================
# Coding-Tutor: HPC Environment Setup (API Mode — No Model Download)
# =================================================================
# Run this ONCE on the HPC cluster to set up the environment.
# Uses Llama API for inference, so NO model download needed.
# Target: /WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor
# =================================================================

set -e

PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
CONDA_ENV_NAME="coding-tutor"

echo "================================================================="
echo "  Coding-Tutor HPC Environment Setup (API Mode)"
echo "================================================================="
echo "  Project dir: $PROJECT_DIR"
echo "  Mode:        API (no local model download)"
echo ""

# --- Step 1: Load modules ---
echo "[1/4] Loading modules..."
module load Anaconda3 2>/dev/null || module load python/3.10 2>/dev/null || true
module load CUDA/12.2.1 2>/dev/null || module load CUDA 2>/dev/null || true

# Set CUDA_HOME (needed for DeepSpeed/flash-attn if used later)
if [ -z "$CUDA_HOME" ]; then
    for cuda_path in /usr/local/cuda /usr/local/cuda-12.2 \
        $(dirname $(dirname $(which nvcc 2>/dev/null) 2>/dev/null) 2>/dev/null); do
        if [ -d "$cuda_path" ] && [ -f "$cuda_path/bin/nvcc" ]; then
            export CUDA_HOME="$cuda_path"
            break
        fi
    done
fi
echo "  ✓ Modules loaded"
echo "  CUDA_HOME: ${CUDA_HOME:-NOT SET}"

# --- Step 2: Create conda environment ---
echo ""
echo "[2/4] Creating conda environment: $CONDA_ENV_NAME"

# Initialize conda for this shell (required on HPC where conda init hasn't run)
eval "$(conda shell.bash hook)"

if conda env list | grep -q "$CONDA_ENV_NAME"; then
    echo "  ✓ Environment already exists. Activating..."
else
    conda create -n "$CONDA_ENV_NAME" python=3.10 -y
    echo "  ✓ Environment created"
fi
conda activate "$CONDA_ENV_NAME"
echo "  Python: $(python --version)"

# --- Step 3: Install dependencies ---
echo ""
echo "[3/4] Installing dependencies..."

# Phase 1: Install PyTorch first (flash-attn needs it at build time)
pip install torch==2.4.0 torchvision --index-url https://download.pytorch.org/whl/cu121

# Phase 2: Install flash-attn (optional optimization)
if [ -n "$CUDA_HOME" ] && [ -f "$CUDA_HOME/bin/nvcc" ]; then
    echo "  Installing flash-attn (nvcc found at $CUDA_HOME/bin/nvcc)..."
    pip install flash-attn==2.7.2.post1 --no-build-isolation 2>&1 || \
        echo "  ⚠  flash-attn build failed — skipping (not required, just faster)"
else
    echo "  ⚠  Skipping flash-attn (nvcc not found)"
fi

# Phase 3: Install remaining dependencies (skip torch and flash-attn)
pip install $(grep -v -E "^(torch|flash-attn)" "$PROJECT_DIR/requirements.txt" | tr '\n' ' ')

# Phase 4: Ensure openai client is installed (needed for API mode)
pip install --quiet openai

echo "  ✓ Dependencies installed"

# --- Step 4: Verify installation ---
echo ""
echo "[4/4] Verifying installation..."
python -c "
import torch
print(f'  PyTorch: {torch.__version__}')
print(f'  CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'  GPU: {torch.cuda.get_device_name(0)}')
    print(f'  VRAM: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB')
"

python -c "import openai; print(f'  OpenAI client: {openai.__version__}')"
python -c "import transformers; print(f'  Transformers: {transformers.__version__}')"
python -c "import deepspeed; print(f'  DeepSpeed: {deepspeed.__version__}')" 2>/dev/null || \
    echo "  ⚠  DeepSpeed not installed (only needed for verifier training)"

echo ""
echo "================================================================="
echo "  Storage Usage"
echo "================================================================="
du -sh "$PROJECT_DIR"/* 2>/dev/null | sort -rh | head -10
df -h "$(dirname "$PROJECT_DIR")" 2>/dev/null | tail -1

echo ""
echo "================================================================="
echo "  Setup Complete ✅"
echo "================================================================="
echo ""
echo "  Next steps:"
echo "  1. Set your API key:  export HF_TOKEN=your_key"
echo "  2. Setup EvoCodeBench: bash scripts/hpc/setup_evocodebench.sh"
echo "  3. Run experiments:   HF_TOKEN=your_key bash scripts/hpc/run_dialogue_hpc.sh"
echo ""
echo "  Running full 100-task dataset. No model download needed — using API for Llama-3-8B inference."
