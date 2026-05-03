# McMiner 60 Completion LM Results

This report summarizes the McMiner run using all 60 `completion_lm.jsonl` files found under `mcminer/` plus `Coding-Tutor/output/student_posttest/easyvolcap`.

## Executive Summary

This experiment used the local WAVE Mistral model, `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2`, as a practical baseline for McMiner. It did **not** use the strongest paper-style API configuration such as Claude/Gemini/OpenAI with reasoning.

The main single-code run, McMiner-S, analyzed **3670 converted code samples** from **367 JSONL records** across **60 `completion_lm.jsonl` files**. It parsed **3665/3670** outputs successfully. The 5 no-misconception rows are also parse failures, so they should be read as **no extracted misconception**, not as confident evidence that the corresponding code has no misconception.

The best full local McMiner-M run is the fixed 2-code run. It processed **220 misconception groups** and sampled exactly **2 code examples per group**, for **440 prompted code samples**. It achieved **220/220 successful parses**. This is a group-level sampled result: it covers all groups, but not all individual code samples inside every group.

The newest run uses McMiner-S as a filter before McMiner-M. It selected **20/220 groups** where single-code predictions repeated or looked suspicious, then ran McMiner-M on exactly **2 codes per selected group**. This reduced the McMiner-M prompt load to **40 prompted code samples**, with **20/20 successful parses** and **19 extracted misconceptions**. This run is useful for focused manual review, but it is intentionally biased toward repeated/suspicious groups.

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

### What The Counts Mean

- **JSONL records** are lines in the original `completion_lm.jsonl` files. One record usually contains the problem context plus a list of generated completions.
- **Code samples** are the individual completions extracted from those records. In this dataset, each JSONL record contributed about 10 completions, giving **367 records x 10 = 3670 code samples**.
- **McMiner-S units** are individual code samples, so McMiner-S produced one prediction attempt per converted code JSON file.
- **McMiner-M groups** are grouped by synthetic misconception ID, for example `completion_lm:searcharray.solr.edismax:6`. These groups collect the same completion index across rounds/files for the same function/problem namespace.
- **Codes represented** means the amount of source data contained in the selected groups.
- **Codes actually placed into prompts** means how many code examples were shown to the model after sampling. For the fixed and filtered McMiner-M runs, this is intentionally smaller than the represented source data.

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

### McMiner-S Quality Notes

McMiner-S produced a very high extraction rate: **3665 parsed predictions** and **3665 extracted misconceptions**. That does not mean all 3665 predicted misconceptions are correct. It only means Mistral returned parseable XML-like output matching the McMiner parser. The descriptions still need human review or evaluator-model validation before they are used as research claims.

The repeated predictions table is useful as a triage signal. Exact repetition can mean a real recurring misconception, but it can also mean the local model is reusing a generic explanation. I used repetition only as a filter for follow-up McMiner-M, not as ground truth.

## McMiner-M Results

I also ran McMiner-M on the same converted input set. McMiner-M groups multiple code samples together before asking the model to infer a shared misconception, so these results are group-level rather than one prediction per individual code sample.

### Why There Are Three McMiner-M Runs

The first McMiner-M run was useful as a test, but it exposed a problem in the local run configuration. I requested 2-3 codes per group, but when `--bags-per-misconception 1` was used, the script still passed the full misconception group into some prompts. Some groups contained up to 24 code samples, so many prompts exceeded Mistral's 8192-token context window and failed to parse.

I then patched `run_infer_misc_multi.py` so the actual prompt always samples the requested number of code examples. I verified before rerunning that all 220 prompts contained exactly 2 rendered student-code examples.

I also tried a third, more targeted run: use McMiner-S as a cheap first-pass filter, then run McMiner-M only on groups where the single-code predictions repeat or look suspicious. The reason for trying this method is that McMiner-M is more expensive per prompt and should be most useful where single-code extraction suggests a pattern worth checking across examples, or where McMiner-S failed/returned no extracted misconception.

For this filtered run, a group was selected if McMiner-S had either:

- at least one exact predicted misconception description repeated 2 or more times inside that group, or
- a suspicious single-code output: parse failure, no-misconception/`NONE`, or empty predicted misconception.

This selected **20 of 220** groups: **15** due to repeated McMiner-S predictions and **5** due to suspicious McMiner-S outputs. The selected groups contained **480 available source code JSON files**, and McMiner-M then sampled exactly **2 code examples per group**, so the actual prompt load was **40 code examples**.

The filter script is:

`mcminer/src/create_mcminer_m_s_filtered_input.py`

It writes the selected subset to:

`mcminer/dataset/mcminer_60_completion_lm_student_codes_s_filtered`

It writes the filter audit trail to:

`mcminer/results/mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192/filter_report.json`

### McMiner-M Run Settings

| Setting | First McMiner-M run | Fixed 2-code McMiner-M run | S-filtered 2-code McMiner-M run |
| --- | --- | --- | --- |
| Tool | McMiner-M | McMiner-M | McMiner-M |
| LLM provider | `vllm` | `vllm` | `vllm` |
| Model | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` | `/WAVE/projects2/CSEN-346-Sp26/Group2/models/Mistral-7B-Instruct-v0.2` |
| Template | `zeroshot-no-reasoning-multi` | `zeroshot-no-reasoning-multi` | `zeroshot-no-reasoning-multi` |
| Reasoning enabled | `False` | `False` | `False` |
| Processing mode | `multi-code-grouping` | `multi-code-grouping` | `multi-code-grouping` |
| Output directory | `results/mcminer_m_60_completion_lm_mistral_ctx8192` | `results/mcminer_m_60_completion_lm_mistral_2codes_ctx8192` | `results/mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192` |
| Requested group size | 2-3 codes | exactly 2 codes | exactly 2 codes |
| Verified rendered codes per prompt | no; some prompts included many codes | yes; min=2, max=2 | yes; sampled exactly 2 by the fixed script |
| vLLM max model length | 8192 tokens | 8192 tokens | 8192 tokens |
| Group selection | all groups | all groups | McMiner-S repeated/suspicious groups only |

### McMiner-M Summary Metrics

| Metric | First McMiner-M run | Fixed 2-code McMiner-M run | S-filtered 2-code McMiner-M run |
| --- | ---: | ---: | ---: |
| Total groups | 220 | 220 | 20 |
| Misconception groups | 220 | 220 | 20 |
| Codes represented by grouping | 3670 | 3670 | 480 selected / 3670 original |
| Codes actually placed into prompts | 3670 | 440 | 40 |
| Successful parses | 80 | 220 | 20 |
| Parse success rate | 36.36% | 100.00% | 100.00% |
| Total misconceptions found | 80 | 220 | 19 |
| Average misconceptions per group | 0.3636 | 1.0000 | 0.9500 |
| Groups with no extracted misconception | 140 | 0 | 1 |

### McMiner-S vs Fixed McMiner-M

| Metric | McMiner-S | Fixed McMiner-M | S-filtered McMiner-M |
| --- | ---: | ---: | ---: |
| Unit of prediction | Code sample | Code group | Code group |
| Units processed | 3670 | 220 | 20 |
| Codes represented | 3670 | 3670 | 480 selected / 3670 original |
| Codes actually included in prompts | 3670 | 440 | 40 |
| Successful parses | 3665 | 220 | 20 |
| Parse success rate | 99.86% | 100.00% | 100.00% |
| Misconceptions found | 3665 | 220 | 19 |
| No extracted misconception | 5 | 0 | 1 |

### McMiner-M Interpretation

The fixed 2-code run is the better local Mistral McMiner-M result. It avoided the context-window failures and produced parseable outputs for every group. However, it should be interpreted as a sampled group-level run: each of the 220 misconception groups is represented by 2 sampled code examples, not by every one of the 3670 code samples.

This makes it useful for checking whether McMiner-M can infer a shared misconception from compact examples, but it is not the same as showing all 3670 code samples to McMiner-M. A stronger future run would use a long-context API model or a truncation strategy that can include more examples per group without exceeding context limits.

The S-filtered 2-code run is the most targeted version. It does not replace the full fixed McMiner-M run because it only analyzes 20 selected groups. Its value is efficiency and review focus: it spends McMiner-M prompts on groups where McMiner-S either showed repeated signals or had extraction problems. The result is easier to manually inspect, but it is intentionally biased toward suspicious/repeated cases.

### Filtered McMiner-M Selected Groups

This table lists all 20 groups selected by the McMiner-S filter. The repeated prediction text is copied from McMiner-S and was used only as a selection signal.

| Selected group | Selection reason | Single-code predictions in group | Repeated McMiner-S signal | Suspicious single outputs |
| --- | --- | ---: | --- | ---: |
| `completion_lm:easyvolcap.utils.data_utils.add_batch:7` | suspicious_single_prediction | 24 | - | 1 |
| `completion_lm:easyvolcap.utils.fcds_utils.get_pulsar_camera_params:7` | repeated_single_prediction | 24 | 2x The student believes that checking the shape of a tensor with a single check for all dimensions is sufficient. | 0 |
| `completion_lm:easyvolcap.utils.fcds_utils.get_pulsar_camera_params:8` | suspicious_single_prediction | 24 | - | 1 |
| `completion_lm:easyvolcap.utils.fcds_utils.get_pytorch3d_camera_params:3` | suspicious_single_prediction | 24 | - | 1 |
| `completion_lm:easyvolcap.utils.loss_utils.lossfun_distortion:6` | repeated_single_prediction | 24 | 2x The student believes that the last dimension of the target tensor `t` should be one more than that of the weights tensor `w` for the distortion loss calculation. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.anneal_weights:4` | repeated_single_prediction | 24 | 2x The student believes that handling cases where adjacent intervals have zero distance by setting their weight to zero is necessary when using the Schlick's bias function for annealing weights. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.anneal_weights:6` | repeated_single_prediction | 24 | 2x The student believes that the annealing factor can be negative. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.anneal_weights:9` | repeated_single_prediction | 24 | 2x The student believes that the annealing factor can be negative. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.max_dilate:2` | repeated_single_prediction | 24 | 2x The student believes that concatenating and sorting tensors is an efficient way to perform dilation in Python. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.max_dilate:7` | repeated_single_prediction | 24 | 3x The student believes that concatenating and sorting tensors is an efficient way to perform dilation in Python. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.max_dilate:9` | repeated_single_prediction | 24 | 2x The student believes that the dilation of time steps can be achieved by simply multiplying the original time steps with the dilation factor. | 0 |
| `completion_lm:easyvolcap.utils.prop_utils.query:9` | repeated_single_prediction | 24 | 2x The student believes that linear interpolation is the only method to interpolate values in a step function. | 0 |
| `completion_lm:easyvolcap.utils.viewer_utils.Camera.to_batch:5` | repeated_single_prediction | 24 | 2x The student believes that NumPy arrays cannot be directly converted to PyTorch tensors without using the `as_tensor` function. | 0 |
| `completion_lm:searcharray.postings.SearchArray.index:2` | repeated_single_prediction | 24 | 2x The student believes that they need to manually instantiate and return a new instance of the SearchArray class within the index method. | 0 |
| `completion_lm:searcharray.postings.SearchArray.index:4` | suspicious_single_prediction | 24 | - | 1 |
| `completion_lm:searcharray.postings.SearchArray.index:5` | repeated_single_prediction | 24 | 2x The student believes that creating a new instance of a class inside a method and returning it is the standard way to implement method chaining in Python. | 0 |
| `completion_lm:searcharray.postings.SearchArray.phrase_freq:5` | repeated_single_prediction | 24 | 2x The student believes that the calculation of phrase frequencies can only be done directly when slop is 1 and all tokens are unique. | 0 |
| `completion_lm:searcharray.postings.SearchArray.positions:4` | suspicious_single_prediction | 24 | - | 1 |
| `completion_lm:searcharray.postings.SearchArray.positions:7` | repeated_single_prediction | 24 | 2x The student believes that a list of one numpy array can be represented as a list of numpy arrays. | 0 |
| `completion_lm:searcharray.solr.edismax:6` | repeated_single_prediction | 24 | 3x The student believes that the default operator for the query is "AND" instead of "OR" | 0 |

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

### S-Filtered McMiner-M Example Group

| Field | Value |
| --- | --- |
| Prediction ID | `group_misconception_completion_lm:easyvolcap.utils.data_utils.add_batch:7_0` |
| Misconception group | `completion_lm:easyvolcap.utils.data_utils.add_batch:7` |
| Why selected | McMiner-S had a suspicious output in this group |
| Number of grouped codes | 2 |
| Source files | `completion_lm_file_0038_record_00008_completion_007.json`, `completion_lm_file_0059_record_00007_completion_007.json` |
| Parse success | `True` |
| Predicted misconception | The student believes that all data structures, including scalars, need to be wrapped in a Tensor or NumPy array to be processed by the add_batch function. |

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

## Conclusions And Limitations

The most reliable statement from these runs is about **pipeline behavior**, not final misconception quality: the McMiner pipeline can process the converted completion data on WAVE with local Mistral, and the fixed McMiner-M script now enforces the requested 2-code prompt size.

The McMiner-S output is broad and high-volume. It is useful for generating candidate misconceptions across all 3670 samples, but it likely contains over-specific, generic, or incorrect model explanations. The repeated-description table can help prioritize review, but repeated text is not automatically evidence of correctness.

The fixed McMiner-M output is cleaner operationally than the first McMiner-M run because every group parsed successfully. It is still sampled: only 2 examples were shown per group. This means a group-level prediction may miss patterns present in other completions from the same group.

The S-filtered McMiner-M output is the best targeted review set. It reduced McMiner-M from 220 groups to 20 groups by using McMiner-S as a triage step. This is useful when we want to spend limited model budget or human review time on likely-interesting cases. It should not be reported as complete coverage of all misconception groups.

The strongest next step would be manual validation or evaluator-model validation of a small sample from:

- top repeated McMiner-S predictions,
- fixed McMiner-M predictions,
- S-filtered McMiner-M predictions,
- the 5 McMiner-S parse failures/no-extraction cases.

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
- `../mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192/filter_report.json`
- `../mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192/multi_summary.json`
- `../mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192/multi_predictions.json`

## Notes

- This is a local WAVE baseline using Mistral, not the best McMiner paper-style model setting.
- Reasoning was disabled because the run used local Mistral via vLLM.
- The predictions are model outputs, not verified ground truth. The high misconception rate should be manually reviewed before making research claims.
- Previous result folders were not overwritten; this run writes to `mcminer/results/mcminer_60_completion_lm_mistral`.
- The McMiner-M result folder is `mcminer/results/mcminer_m_60_completion_lm_mistral_ctx8192`. Its parse rate is much lower because many grouped prompts exceeded the local 8192-token Mistral context.
- The fixed McMiner-M result folder is `mcminer/results/mcminer_m_60_completion_lm_mistral_2codes_ctx8192`. This rerun was added because the first McMiner-M run did not actually enforce the intended small group size in every prompt.
- The S-filtered McMiner-M result folder is `mcminer/results/mcminer_m_60_completion_lm_mistral_s_filtered_2codes_ctx8192`. This rerun was added to test whether McMiner-S can reduce McMiner-M prompts by identifying groups with repeated or suspicious single-code predictions.
