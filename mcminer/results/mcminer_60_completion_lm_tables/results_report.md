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

## Notes

- This is a local WAVE baseline using Mistral, not the best McMiner paper-style model setting.
- Reasoning was disabled because the run used local Mistral via vLLM.
- The predictions are model outputs, not verified ground truth. The high misconception rate should be manually reviewed before making research claims.
- Previous result folders were not overwritten; this run writes to `mcminer/results/mcminer_60_completion_lm_mistral`.
