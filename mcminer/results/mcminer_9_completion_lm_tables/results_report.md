# McMiner Completion LM Results

This report summarizes the McMiner runs on the 9 selected `completion_lm.jsonl` files from the `mcminer` project.

## Inputs

- Selected files: `mcminer/selected_mcminer_completion_lm_latest_paths.txt`
- JSONL records: 20
- Converted code samples: 200
- Problem contexts: 7

## Model Settings

| Run | Tool variant | Model | Template | Reasoning |
| --- | --- | --- | --- | --- |
| McMiner-S | Single-code | `Mistral-7B-Instruct-v0.2` via local vLLM | `zeroshot-no-reasoning` | Disabled |
| McMiner-M | Multi-code grouping | `Mistral-7B-Instruct-v0.2` via local vLLM | `zeroshot-no-reasoning-multi` | Disabled |

## Summary

| Run | Items analyzed | Codes analyzed | Successful parses | Parse success rate | Misconceptions found | Avg misconceptions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| McMiner-S | 200 code samples | 200 | 200 | 100% | 200 | 1.00 per code |
| McMiner-M | 70 groups | 200 | 70 | 100% | 70 | 1.00 per group |

## Output Files

### CSV Tables

- `summary_table.csv`
- `single_predictions_table.csv`
- `multi_predictions_table.csv`

### Raw JSON Results

- `../mcminer_9_completion_lm_mistral/summary.json`
- `../mcminer_9_completion_lm_mistral/predictions.json`
- `../mcminer_m_9_completion_lm_mistral_ctx8192/multi_summary.json`
- `../mcminer_m_9_completion_lm_mistral_ctx8192/multi_predictions.json`

## Notes

- These are local WAVE baseline runs using Mistral, not the best McMiner paper-style settings.
- Claude Sonnet 4.5 with reasoning would require an `ANTHROPIC_API_KEY` and would incur API cost.
- The final McMiner-M run used an 8192-token vLLM context to avoid prompt-length failures from the default 4096-token context.
- Before falling back to Mistral, stronger local open-weight options were attempted:
  - `Qwen3-14B-AWQ`
  - `Qwen3-14B-GPTQ-Int4`
- Those Qwen quantized models could not run on WAVE's available Volta/V100 GPU because the AWQ/GPTQ kernels require newer CUDA GPU architectures than V100's `sm_70` compute capability supports.
- The unusable local Qwen model folders were removed from WAVE to save disk space:
  - `qwen_models/Qwen3-14B-AWQ`
  - `qwen_models/Qwen3-14B-GPTQ-Int4`
- Nothing was deleted from GitHub; only local downloaded model folders on WAVE were removed.
