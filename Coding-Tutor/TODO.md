# Coding-Tutor Future Tasks

## Traver Execution Phase
- [x] **Optimize LM Inference API (`traver/utils/LM_inference_api.py`)**: 
  - Refactored to use `asyncio` + `AsyncOpenAI` for concurrent API calls.
  - All N=10 completions per task fire simultaneously; up to 5 tasks process in parallel.
  - Includes exponential backoff with jitter on rate-limit (429) errors.
  - Expected speedup: ~31.5h → ~4h for full 100-task codegen.
