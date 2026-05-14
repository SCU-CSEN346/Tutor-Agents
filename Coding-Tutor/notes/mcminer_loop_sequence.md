# McMiner-in-the-Loop: Pipeline Sequence

## Overview

Instead of running all 8 dialogue rounds at once, then analyzing misconceptions post-hoc,
we interleave McMiner between every round so the tutor gets real-time feedback about
what the student is actually getting wrong in their code.

## Architecture

```
Baseline (current):
  Full dialogue (8 rounds) → Posttest prompts → Codegen → Eval → McMiner (post-hoc)

McMiner-in-the-Loop (new):
  Round 1 → Codegen → McMiner → Inject → Round 2 → Codegen → McMiner → Inject → ... → Eval
```

## Models Used

| Role              | Model                        | Location         | Purpose                        |
|-------------------|------------------------------|------------------|--------------------------------|
| Tutor             | Llama-3.1-70B-Instruct       | HF API (remote)  | Guides student, receives misconceptions |
| Student (dialogue)| Mistral-7B-Instruct-v0.2     | Local GPU (4-bit) | Simulates student responses    |
| Verifier          | Mistral-7B + LoRA head       | Local GPU (4-bit) | Scores tutor candidate responses |
| Codegen (diagnostic) | Llama-3.1-8B-Instruct     | HF API (remote)  | Generates N=1 code per round   |
| McMiner           | Gemini 2.5 Flash             | Google API        | Detects misconceptions in code |
| Moderator         | Mistral-7B-Instruct-v0.2     | Local GPU (4-bit) | Decides early stop             |

## Step-by-Step Sequence

### 1. Setup (Notebook Cells 0–14)

Same as the baseline focused notebook:
- Clone repo from GitHub
- Install dependencies (transformers, bitsandbytes, peft, vllm, etc.)
- Patch VLLMChat: tutor → HF Inference API, student → local 4-bit GPU
- Patch model_utils: 4-bit NF4 quantization for verifier
- Download models from Drive (Mistral-7B-v0.1 base, Verifier-7B, Mistral-7B-Instruct-v0.2)

### 2. McMiner-Loop Dialogue (per project, per level)

Script: `traver/run_mcminer_loop.py`
Output: `output/mcminer_loop/{project}/traver/{model}/{level}/simulated_dialogs.jsonl`

For each task (namespace):

#### 2a. Create Arena Components

- **Tutor**: system prompt from `prompt_tutor()` with task description, dependencies, reference steps
- **Student**: system prompt from `prompt_student()` based on level (low/med/high)
- **Moderator**: checks if tutor's goal is completed after each round
- **Environment**: TutoringConversation manages turn order
- **Arena**: TutoringArena wraps players + environment

#### 2b. Round-by-Round Loop (max 8 rounds)

For round_idx = 1 to 8:

**Step A — Tutor speaks** (`arena.step()`)
- Knowledge Tracing (KT): tutor estimates what the student knows so far
- If `tutor_num_responses > 1`: generates N candidates, verifier scores them, picks best
- If misconceptions were injected: tutor prompt now includes them, so the tutor
  can address them directly (e.g., "I notice you might be confused about X...")

**Step B — Student responds** (`arena.step()`)
- Student model generates response based on conversation history
- Moderator evaluates: "Is the tutor's goal complete?" → yes/no
- If yes → early stop, break loop

**Step C — Extract conversation**
- Pull all messages from environment: `env.get_observation()`
- Format as: `[{"tutor": "..."}, {"student": "..."}, {"tutor": "..."}, {"student": "..."}]`

**Step D — Build posttest prompt** (deterministic, no LLM)
- Uses `prompt_student_posttest()` from `make_prompt.py`
- Template: "You are a college student... here is your discussion with a tutor... complete this function"
- Includes dialogue context up to current round

**Step E — Generate diagnostic code** (Llama-3.1-8B via HF API)
- N=1 completion (not N=10 — this is just for diagnosis, not evaluation)
- Temperature=0.4, top_p=0.95, max_tokens=1024
- Result: the function body that the student would produce given this dialogue

**Step F — Run McMiner** (Gemini 2.5 Flash)
- Prompt: "Analyze this code for programming MISCONCEPTIONS..."
- If misconception detected → returns description (e.g., "student believes dict.keys() returns a list")
- If no misconception → returns NONE

**Step G — Update tutor prompt (latest-only injection)**
- If misconception detected: **replace** any previous injection with ONLY this round's result
- Update `tutor.role_desc`:
  ```
  [MISCONCEPTION FEEDBACK]
  The student's latest code attempt (after round 3) shows the following misconception.
  Address this directly in your next response:
  
  - Student confuses numpy broadcasting rules
  [END MISCONCEPTION FEEDBACK]
  ```
- If McMiner returns NONE: **remove** the misconception block entirely, tutor operates normally
- This avoids repetition: if the student fixed a misconception, the tutor won't keep harping on it
- If a misconception persists, McMiner will re-detect it naturally in the next round
- The text is inserted BEFORE the last paragraph of the tutor desc
  (because KT replaces the last paragraph with the response generation prompt)
- The tutor reads `self.role_desc` fresh every turn, so the change takes effect immediately

#### 2c. Save Dialogue

After all rounds complete (or early stop), save to `simulated_dialogs.jsonl`:
```json
{
  "namespace": "easyvolcap.engine.build_network",
  "conversation": [
    {"tutor": "Let's work on build_network..."},
    {"student": "I think we need to..."},
    {"tutor": "I notice you might be confused about super().__init__()..."},
    {"student": "Oh I see, let me fix that..."}
  ],
  "tutor_thoughts": [...],
  "misconceptions_detected": [
    {"round": 1, "description": "believes torch.nn.Module.__init__() doesn't need super().__init__()"},
    {"round": 3, "description": "confuses tensor.view() with tensor.reshape()"}
  ]
}
```

### 3. Evaluation (Phase 2)

After all tasks for a project are done, run the SAME evaluation pipeline as baseline:

**Step 1: Generate posttest prompts** (`make_prompt.py --student_posttest`)
- For each round R1–R8: truncate dialogue to that round, build prompt
- Output: `prompt_round_1.jsonl`, ..., `prompt_round_8.jsonl`

**Step 2: Generate N=10 completions** (`LM_inference_hf.py`)
- Llama-3.1-8B-Instruct via HF API
- N=10 samples per prompt, T=0.4, top_p=0.95
- Output: `completion.jsonl` per round

**Step 3: Run tests** (`pass_k.py`)
- Inject each completion into the project source code
- Run pytest against the task's test suite
- Compute Pass@k using unbiased estimator

**Step 4: Print results**
- Pass@1, Pass@5, Pass@10 per round, per level
- Compare to baseline results

### 4. Compare: Baseline vs McMiner-Loop

The key comparison:

| Metric | Baseline | McMiner-Loop |
|--------|----------|--------------|
| Pass@1 | 27.5%    | ???          |
| Pass@10| 38.0%    | ???          |

If McMiner-Loop shows improvement, it validates the hypothesis:
**Real-time misconception feedback helps the tutor give better guidance.**

## File Structure

```
output/
├── dialogue_by_project/          # Baseline dialogues (existing)
│   └── easyvolcap/traver/Llama-3.1-70B-Instruct/low_level/
│       └── simulated_dialogs.jsonl
│
└── mcminer_loop/                 # McMiner-in-the-loop dialogues (NEW)
    └── easyvolcap/traver/Llama-3.1-70B-Instruct/low_level/
        └── simulated_dialogs.jsonl  (includes misconceptions_detected field)
```

## Implementation Files

- `traver/run_mcminer_loop.py` — round-by-round orchestrator (NEW)
- `colab_mcminer_loop.ipynb` — Colab notebook (copied from focused, cells updated)
- `update_mcminer_loop_notebook.py` — helper script to patch notebook cells

## Key Design Decisions

1. **N=1 for diagnostic codegen** — we don't need N=10 between rounds, just a quick diagnostic
2. **Latest-only injection (Option A)** — only the current round's misconception is shown to the tutor; if McMiner returns NONE, the block is removed entirely; prevents repetition and confusion
3. **Inserted before last paragraph** — because KT replaces the last paragraph with RG prompt
4. **Subprocess per verifier part** — same as baseline, ensures GPU memory cleanup
5. **Same evaluation pipeline** — only the dialogue changes; codegen + eval are identical
6. **All misconceptions still logged** — saved in `misconceptions_detected` field for analysis, even though only the latest is injected
