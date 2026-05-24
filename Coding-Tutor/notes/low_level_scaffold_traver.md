# Low-Level Scaffolded TRAVER

## Motivation

The paper results show that low-level EasyVolcap students perform best under the
baseline TRAVER condition and degrade under McMiner:

- Baseline low_level: 23.0% Pass@1 at R7
- McMiner low_level: 11.0% Pass@1 at R6
- Clean low_level: 10.8% Pass@1 at R1

The likely failure mode is that low-level students produce incomplete or broken
diagnostic code, which McMiner can misread as a conceptual misconception. For
this condition, we avoid McMiner entirely and make the tutor more scaffolded.

## Condition

`traver_low_scaffold`

Changes from baseline TRAVER:

1. Adds a low-level scaffold policy to the tutor prompt.
2. Blocks moderator early stopping until at least 6 full tutor/student rounds.
3. Adds a compact API-hint block from dependency paths and likely API calls.
4. Keeps the rest of the TRAVER pipeline unchanged.

The scaffold policy asks the tutor to:

- avoid misconception-mining language,
- identify inputs, expected outputs, and one dependency/API at a time,
- provide small code skeletons with placeholders,
- ask the student to fill exactly one missing line or branch,
- use simple test-case traces when logic is unclear.

The API-hint block is intentionally compact. It gives the tutor concrete
repository dependencies and likely utility calls to explain, without pasting the
full reference solution as the answer.

## Run

```bash
cd Coding-Tutor
./scripts/run/run_low_scaffold_traver.sh
```

Direct runner:

```bash
cd Coding-Tutor
python3 traver/run_low_scaffold_traver.py \
  --scaffold_tutor_setting traver_low_scaffold \
  --min_low_level_rounds 6 \
  --tutor_setting traver_low_scaffold \
  --namespace_file prompt/namespaces.json \
  --prompt_element_file prompt/prompt_elements_final.jsonl \
  --output_dir output/dialogue \
  --student_setting low_level \
  --tutor_model_name_or_path gpt-4o \
  --student_model_name_or_path /path/to/student/model
```

## Hypothesis

Low-level performance should improve over raw McMiner/Clean and may improve over
baseline if the extra scaffolded rounds preserve the R7 benefit while reducing
student confusion.
