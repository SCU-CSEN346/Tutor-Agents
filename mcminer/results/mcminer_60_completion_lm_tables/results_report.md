# McMiner 60 Completion LM Results

This report summarizes the McMiner run using all 60 `completion_lm.jsonl` files found under `mcminer/` plus `Coding-Tutor/output/student_posttest/easyvolcap`.

## Inputs

| Source group | Files | JSONL records | Code samples |
| --- | ---: | ---: | ---: |
| codeformer_model | 3 | 3 | 30 |
| easyvolcap | 24 | 246 | 2460 |
| gfpgan_model | 5 | 8 | 80 |
| searcharray | 24 | 106 | 1060 |
| xinhua | 4 | 4 | 40 |

Total files: **60**

Total JSONL records: **367**

Total converted code samples: **3670**

Problem contexts: **22**

## Run Settings

| Setting | Value |
| --- | --- |
| Tool | McMiner-S |
| LLM provider | `vllm` |
| Model | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` |
| Template | `zeroshot-no-reasoning` |
| Reasoning enabled | `False` |
| Processing mode | `batch` |
| Input directory | `dataset/mcminer_60_completion_lm_student_codes` |
| Output directory | `results/mcminer_60_completion_lm_mistral` |

## Summary Metrics

| Metric | Value |
| --- | ---: |
| Codes analyzed | 3670 |
| Successful parses | 3665 |
| Parse success rate | 99.8638% |
| Total misconceptions found | 3665 |
| Average misconceptions per code | 0.9986 |
| Codes with no misconceptions | 5 |
| NONE substitutions | 0 |

## McMiner-M Results

I also ran McMiner-M on the same converted input set. McMiner-M groups multiple code samples together before asking the model to infer a shared misconception, so these results are group-level rather than one prediction per individual code sample.

### Why There Are Two McMiner-M Runs

The first McMiner-M run was useful as a test, but it exposed a problem in the local run configuration. I requested 2-3 codes per group, but when `--bags-per-misconception 1` was used, the script still passed the full misconception group into some prompts. Some groups contained up to 24 code samples, so many prompts exceeded Mistral's 8192-token context window and failed to parse.

I then patched `run_infer_misc_multi.py` so the actual prompt always samples the requested number of code examples. I verified before rerunning that all 220 prompts contained exactly 2 rendered student-code examples.

### McMiner-M Run Settings

| Setting | First McMiner-M run | Fixed 2-code McMiner-M run |
| --- | --- | --- |
| Tool | McMiner-M | McMiner-M |
| LLM provider | `vllm` | `vllm` |
| Model | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` |
| Template | `zeroshot-no-reasoning-multi` | `zeroshot-no-reasoning-multi` |
| Reasoning enabled | `False` | `False` |
| Processing mode | `multi-code-grouping` | `multi-code-grouping` |
| Output directory | `results/mcminer_m_60_completion_lm_mistral_ctx8192` | `results/mcminer_m_60_completion_lm_mistral_2codes_ctx8192` |
| Requested group size | 2-3 codes | exactly 2 codes |
| Verified rendered codes per prompt | no; some prompts included many codes | yes; min=2, max=2 |
| vLLM max model length | 8192 tokens | 8192 tokens |

### McMiner-M Summary Metrics

| Metric | First McMiner-M run | Fixed 2-code McMiner-M run |
| --- | ---: | ---: |
| Total groups | 220 | 220 |
| Misconception groups | 220 | 220 |
| Codes represented by grouping | 3670 | 3670 |
| Codes actually placed into prompts | 3670 | 440 |
| Successful parses | 80 | 220 |
| Parse success rate | 36.36% | 100.00% |
| Total misconceptions found | 80 | 220 |
| Average misconceptions per group | 0.3636 | 1.0000 |
| Groups with no extracted misconception | 140 | 0 |

### McMiner-S vs Fixed McMiner-M

| Metric | McMiner-S | Fixed McMiner-M |
| --- | ---: | ---: |
| Unit of prediction | Code sample | Code group |
| Units processed | 3670 | 220 |
| Codes represented | 3670 | 3670 |
| Codes actually included in prompts | 3670 | 440 |
| Successful parses | 3665 | 220 |
| Parse success rate | 99.86% | 100.00% |
| Misconceptions found | 3665 | 220 |
| No extracted misconception | 5 | 0 |

### McMiner-M Interpretation

The fixed 2-code run is the better local Mistral McMiner-M result. It avoided the context-window failures and produced parseable outputs for every group. However, it should be interpreted as a sampled group-level run: each of the 220 misconception groups is represented by 2 sampled code examples, not by every one of the 3670 code samples.

This makes it useful for checking whether McMiner-M can infer a shared misconception from compact examples, but it is not the same as showing all 3670 code samples to McMiner-M. A stronger future run would use a long-context API model or a truncation strategy that can include more examples per group without exceeding context limits.

### Fixed McMiner-M Example Successful Group

| Field | Value |
| --- | --- |
| Prediction ID | `group_misconception_completion_lm:codeformer_model.setup_model:0_0` |
| Misconception group | `completion_lm:codeformer_model.setup_model:0` |
| Number of grouped codes | 2 |
| Source files | `completion_lm_file_0000_record_00000_completion_000.json`, `completion_lm_file_0001_record_00000_completion_000.json` |
| Parse success | `True` |
| Predicted misconception | The student believes that initializing a global list within a function is necessary for adding an instance to the list within the same function. |

McMiner-M explanation:

```text
Both code samples initialize the global list 'face_restorers' within their
respective functions 'setup_model'. However, initializing the list within the
function is not necessary for adding an instance to the list within the same
function.
```

## Breakdown By Namespace

This table shows the largest namespaces by number of analyzed completions. The full version is in `problem_summary_table.csv`.

| Namespace | Source group | Code samples | Successful parses | No-misconception predictions |
| --- | --- | ---: | ---: | ---: |
| easyvolcap.utils.data_utils.add_batch | easyvolcap | 240 | 239 | 1 |
| easyvolcap.utils.data_utils.to_cuda | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.fcds_utils.get_pulsar_camera_params | easyvolcap | 240 | 239 | 1 |
| easyvolcap.utils.fcds_utils.get_pytorch3d_camera_params | easyvolcap | 240 | 239 | 1 |
| easyvolcap.utils.gl_utils.Quad.upload_to_texture | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.loss_utils.lossfun_distortion | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.prop_utils.anneal_weights | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.prop_utils.max_dilate | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.prop_utils.query | easyvolcap | 240 | 240 | 0 |
| easyvolcap.utils.viewer_utils.Camera.to_batch | easyvolcap | 240 | 240 | 0 |
| searcharray.postings.SearchArray.index | searcharray | 240 | 239 | 1 |
| searcharray.postings.SearchArray.phrase_freq | searcharray | 240 | 240 | 0 |
| searcharray.postings.SearchArray.positions | searcharray | 240 | 239 | 1 |
| searcharray.solr.edismax | searcharray | 240 | 240 | 0 |
| searcharray.utils.bitcount.bit_count64 | searcharray | 70 | 70 | 0 |
| gfpgan_model.gfpgan_fix_faces | gfpgan_model | 50 | 50 | 0 |
| xinhua.XinhuaHallucinations.statistics | xinhua | 40 | 40 | 0 |
| codeformer_model.setup_model | codeformer_model | 30 | 30 | 0 |
| easyvolcap.utils.loss_utils.inner_outer | easyvolcap | 30 | 30 | 0 |
| easyvolcap.utils.loss_utils.lossfun_outer | easyvolcap | 30 | 30 | 0 |
| gfpgan_model.setup_model | gfpgan_model | 30 | 30 | 0 |
| searcharray.solr.parse_min_should_match | searcharray | 30 | 30 | 0 |

## Most Repeated Predicted Misconceptions

This table lists repeated exact descriptions. Repetition does not mean the misconception is correct; it only shows what Mistral produced most often. The full top-50 table is in `top_misconceptions_table.csv`.

| Rank | Count | Predicted misconception |
| ---: | ---: | --- |
| 1 | 7 | The student believes that concatenating and sorting tensors is an efficient way to perform dilation in Python. |
| 2 | 6 | The student believes that the last dimension of the tensor 't' must be one more than the last dimension of tensor 'w' |
| 3 | 5 | The student believes that the annealing slope can be negative. |
| 4 | 5 | The student believes that the annealing factor can be negative. |
| 5 | 4 | The student believes that the default operator for the query is "AND" instead of "OR" |
| 6 | 4 | The student believes that the calculation of phrase frequencies can only be done directly when slop is 1 and all tokens are unique. |
| 7 | 3 | The student believes that if the slop is 1 and all tokens are unique, they can directly calculate phrase frequencies using the positions of terms in the SearchArray instance. |
| 8 | 3 | The student believes that the default operator for the query in the edismax function is "AND" instead of "OR". |
| 9 | 3 | The student believes that importing the same module multiple times with different aliases will result in multiple instances of the module being loaded into memory. |
| 10 | 3 | The student believes that creating a new instance of a class requires copying all the data from the old instance. |
| 11 | 3 | The student believes that creating a new instance of a class requires assigning the result to a new variable. |
| 12 | 3 | The student believes that the calculation of phrase frequencies can only be done when slop is 1 and all tokens are unique. |
| 13 | 3 | The student believes that they need to manually instantiate and return a new instance of the SearchArray class within the index method. |
| 14 | 3 | The student believes that calculating phrase frequencies with a slop greater than 1 or when tokens are not unique requires a different method. |
| 15 | 3 | The student believes that to get the positions of a term in a specific document, they need to call the 'positions' method twice: once for the term ID and once for the document key. |

## Sample Predictions

These are the first 12 predictions from the detailed table. Use `detailed_predictions_table.csv` for source paths, generated code, and raw completions.

| Source group | Namespace | Completion index | Predicted misconception |
| --- | --- | ---: | --- |
| codeformer_model | codeformer_model.setup_model | 0 | The student believes that it is necessary to check if an instance is not None before adding it to a global list. |
| codeformer_model | codeformer_model.setup_model | 1 | The student believes that they need to check the name of the initialized instance to ensure it is a specific type before adding it to a global list. |
| codeformer_model | codeformer_model.setup_model | 2 | The student believes that a local variable can be reassigned to a global variable with the same name without using the global keyword. |
| codeformer_model | codeformer_model.setup_model | 3 | The student believes that global variables can be directly assigned to without declaring them beforehand. |
| codeformer_model | codeformer_model.setup_model | 4 | The student believes that they need to use a try-except block for handling all exceptions, even when only specific exceptions are expected. |
| codeformer_model | codeformer_model.setup_model | 5 | The student believes that it is necessary to use a global variable to store an instance of the FaceRestorerCodeFormer class. |
| codeformer_model | codeformer_model.setup_model | 6 | The student believes that a variable can be assigned the value of an instance directly to another variable without using assignment operator |
| codeformer_model | codeformer_model.setup_model | 7 | The student believes that it's necessary to use a try-except block for initializing an object even when the initialization is guaranteed to succeed in Python. |
| codeformer_model | codeformer_model.setup_model | 8 | The student believes that using a global variable for storing an instance is a good practice for managing instances of a class. |
| codeformer_model | codeformer_model.setup_model | 9 | The student believes that global variables should be initialized within a function to make them accessible within the function |
| codeformer_model | codeformer_model.setup_model | 0 | The student believes that it is necessary to define a global list to store instances of a class before initializing the instances. |
| codeformer_model | codeformer_model.setup_model | 1 | The student believes that using a try-except block to handle exceptions at the function level is a good practice for every function, regardless of whether an exception is expected or not. |

## Review/Quality Flags

| Flag | Count | Table |
| --- | ---: | --- |
| Parse failures | 5 | `parse_failures_table.csv` |
| No-misconception predictions | 5 | `no_misconception_predictions_table.csv` |

## Example Outputs

### Successful Parse Example

This is an example where McMiner successfully parsed Mistral's output and extracted one predicted misconception.

| Field | Value |
| --- | --- |
| Prediction ID | `completion_lm_file_0000_record_00000_completion_000.json_0` |
| Source file | `mcminer/codeformer_model/traver/Llama-3.1-70B-Instruct/high_level/round_1/completion_lm.jsonl` |
| Namespace | `codeformer_model.setup_model` |
| Completion index | `0` |
| Parse success | `True` |
| No misconception | `False` |
| Predicted misconception | The student believes that it is necessary to check if an instance is not None before adding it to a global list. |

Code preview:

```python
def setup_model(dirname: str) -> None:
    """
    This function attempts to set up a model for face restoration by initializing
    a FaceRestorerCodeFormer instance with the given directory name.
    """
    try:
        codeformer = face_restoration_utils.FaceRestorerCodeFormer(dirname)
        if codeformer is not None:
            global face_restorers
            face_restorers.append(codeformer)
```

### No-Misconception / Parse-Failure Example

In this run, all 5 "no misconception" rows are also parse failures. That means McMiner did not extract a valid `<misconception>` block from Mistral's response, so these should be interpreted as **unparsed/no extracted misconception**, not strong evidence that the code has no misconception.

| Field | Value |
| --- | --- |
| Prediction ID | `completion_lm_file_0012_record_00002_completion_004.json_0` |
| Source file | `mcminer/searcharray/traver/Llama-3.1-70B-Instruct/high_level/round_5/completion_lm.jsonl` |
| Namespace | `searcharray.postings.SearchArray.index` |
| Completion index | `4` |
| Parse success | `False` |
| No misconception | `True` |
| Predicted misconception | `NONE / not extracted` |

Code preview:

```python
def index(cls, array: Iterable, tokenizer=ws_tokenizer,
          truncate=False, batch_size=100000, avoid_copies=True) -> 'SearchArray':
    """
    Indexes an array of strings using a specified tokenizer and returns
    an instance of SearchArray containing the indexed data.
    """
```

## Generated Tables

- `summary_table.csv`
- `group_summary_table.csv`
- `input_files_table.csv`
- `predictions_table.csv`
- `detailed_predictions_table.csv`
- `problem_summary_table.csv`
- `top_misconceptions_table.csv`
- `parse_failures_table.csv`
- `no_misconception_predictions_table.csv`

## Raw Results

- `../mcminer_60_completion_lm_mistral/summary.json`
- `../mcminer_60_completion_lm_mistral/predictions.json`
- `../mcminer_m_60_completion_lm_mistral_ctx8192/multi_summary.json`
- `../mcminer_m_60_completion_lm_mistral_ctx8192/multi_predictions.json`
- `../mcminer_m_60_completion_lm_mistral_2codes_ctx8192/multi_summary.json`
- `../mcminer_m_60_completion_lm_mistral_2codes_ctx8192/multi_predictions.json`

## Notes

- This is a local WAVE baseline using Mistral, not the best McMiner paper-style model setting.
- Reasoning was disabled because the run used local Mistral via vLLM.
- The predictions are model outputs, not verified ground truth. The high misconception rate should be manually reviewed before making research claims.
- Previous result folders were not overwritten; this run writes to `mcminer/results/mcminer_60_completion_lm_mistral`.
- The McMiner-M result folder is `mcminer/results/mcminer_m_60_completion_lm_mistral_ctx8192`. Its parse rate is much lower because many grouped prompts exceeded the local 8192-token Mistral context.
- The fixed McMiner-M result folder is `mcminer/results/mcminer_m_60_completion_lm_mistral_2codes_ctx8192`. This rerun was added because the first McMiner-M run did not actually enforce the intended small group size in every prompt.
