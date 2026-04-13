#!/bin/bash
# =================================================================
# Coding-Tutor HPC: vLLM Engine (NOT NEEDED IN API MODE)
# =================================================================
# This script is NOT needed when using the Llama API.
# It's kept for reference if you switch to local model serving.
#
# In API mode, the dialogue and codegen scripts connect directly
# to the API endpoint (Groq, Together, etc.) — no local server.
# =================================================================

echo "================================================================="
echo "  ⚠  vLLM Engine is NOT needed in API mode"
echo "================================================================="
echo ""
echo "  Your scripts are configured to use the Llama API directly."
echo "  No local model or vLLM server is required."
echo ""
echo "  To run experiments, just set your API key and run:"
echo "    export LLAMA_API_KEY=your_key"
echo "    bash scripts/hpc/run_dialogue_hpc.sh"
echo ""
echo "  If you want to switch to local serving, download the model"
echo "  and update MODEL_PATH below."
echo ""

exit 0

# --- Legacy local serving (uncomment if needed) ---
# PROJECT_DIR="/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
# MODEL_DIR="$PROJECT_DIR/models"
# MODEL_PATH="$MODEL_DIR/Meta-Llama-3.1-8B-Instruct"
# 
# CUDA_VISIBLE_DEVICES=0 python -m vllm.entrypoints.openai.api_server \
#     --model "$MODEL_PATH" \
#     --port 8001 \
#     --tensor-parallel-size 1 \
#     --gpu-memory-utilization 0.90 \
#     --max-model-len 16384 \
#     --enforce-eager \
#     --api-key "EMPTY"
