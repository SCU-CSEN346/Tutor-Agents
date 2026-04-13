# Coding-Tutor: WAVE HPC Setup Guide

> **API Mode** — Using Groq API (free, no model download needed).  
> **Tutor:** Llama 3.3 70B | **Student:** Llama 3 8B  
> **Storage:** ~6-8GB total (well under the 30GB limit).

---

## Quick Start

```bash
# 1. Transfer project to HPC
rsync -avz --progress \
    --exclude='.venv' --exclude='.git' --exclude='.idea' \
    --exclude='__pycache__' --exclude='build/' \
    /Users/catherine/PycharmProjects/Coding-Tutor/ \
    cawad@login.wave.scu.edu:"/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor/"

# 2. Setup environment (no model download)
bash scripts/hpc/setup_env.sh

# 3. Create data subset (2 folds, 40 tasks)
python scripts/hpc/create_subset.py --folds 0 1 --output_dir hpc_subset

# 4. Download EvoCodeBench (10/25 projects)
bash scripts/hpc/setup_evocodebench.sh

# 5. Set Groq API key and run
export GROQ_API_KEY="gsk_YOUR_KEY"
bash scripts/hpc/run_dialogue_hpc.sh
bash scripts/hpc/run_codegen_hpc.sh
bash scripts/hpc/run_coding_test_hpc.sh
```

---

## Model Setup

We use **Groq API** (free, no credit card) with separate models per role:

| Role | Model | Groq ID | Why |
|------|-------|---------|-----|
| **Tutor** | Llama 3.3 70B | `llama-3.3-70b-versatile` | Stronger model = better tutor |
| **Student** | Llama 3 8B | `llama3-8b-8192` | Weaker model = realistic student |
| **Moderator** | Llama 3 8B | `llama3-8b-8192` | Lightweight role |

> This mirrors the original paper's design (GPT-4 tutor, Mixtral student) — a more capable model guides a less capable one.

### Get Your API Key

1. Go to [console.groq.com](https://console.groq.com)
2. Sign up (no credit card needed)
3. Create an API key
4. Set it on the HPC:

```bash
export GROQ_API_KEY="gsk_YOUR_KEY_HERE"
```

> **Tip:** Add to `~/.bashrc` so it persists across sessions.

---

## Step-by-Step Setup

### 1. Transfer Project

From your local machine:

```bash
rsync -avz --progress \
    --exclude='.venv' --exclude='.git' --exclude='.idea' \
    --exclude='output/*.zip' --exclude='build/' --exclude='__pycache__' \
    /Users/catherine/PycharmProjects/Coding-Tutor/ \
    cawad@login.wave.scu.edu:"/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor/"
```

### 2. Environment Setup

```bash
cd "/WAVE/projects/CSEN-346-Sp26/Group2/Coding-Tutor"
bash scripts/hpc/setup_env.sh
```

Installs conda env + deps. No model download.

### 3. Create Data Subset

```bash
conda activate coding-tutor
python scripts/hpc/create_subset.py --folds 0 1 --output_dir hpc_subset
```

### 4. Download EvoCodeBench

```bash
bash scripts/hpc/setup_evocodebench.sh
```

Downloads from HuggingFace, extracts 10/25 projects, installs deps into shared env.

---

## Running Experiments

```bash
conda activate coding-tutor
export GROQ_API_KEY="gsk_YOUR_KEY"
```

### Step 1: Dialogue Simulation (no GPU needed)

```bash
bash scripts/hpc/run_dialogue_hpc.sh
```

70B tutor teaches 8B student across 3 levels × 40 tasks.

### Step 2: Code Generation (no GPU needed)

```bash
bash scripts/hpc/run_codegen_hpc.sh
```

### Step 3: Coding Tests

```bash
bash scripts/hpc/run_coding_test_hpc.sh
```

### Step 4: Verifier Training (Optional — needs GPU + model download)

```bash
HF_TOKEN=hf_YOUR_TOKEN bash scripts/hpc/run_verifier_hpc.sh
rm -rf models/  # free space after training
```

### Step 5: Evaluate

```bash
python scripts/eval/eval_pretest.py
python scripts/eval/eval_TOR.py \
    --pretest_dir output/student_pretest \
    --posttest_dir output/student_posttest
```

---

## Storage Budget

| Component | Size |
|-----------|------|
| Conda env (in user home) | ~5GB |
| `EvoCodeBench-2403/` (10 projects, shared env) | ~2-3GB |
| `hpc_subset/` + project code | ~5MB |
| Output (generated during experiments) | ~1-2GB |
| **Total** | **~8-10GB** |

---

## Script Reference

| Script | Purpose | GPU? | Time |
|--------|---------|------|------|
| `setup_env.sh` | Conda env + deps | No | 10-15 min |
| `setup_evocodebench.sh` | Download EvoCodeBench subset | No | 15-30 min |
| `create_subset.py` | Create 2-fold data subset | No | < 1 min |
| `run_dialogue_hpc.sh` | Tutor-student dialogues (Groq) | No | 2-4 hrs |
| `run_codegen_hpc.sh` | Code generation (Groq) | No | 1-2 hrs |
| `run_coding_test_hpc.sh` | pass@k, recall@k tests | No | 30-60 min |
| `run_verifier_hpc.sh` | Train verifier (optional) | **Yes** | 1-3 hrs |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `conda activate` fails | Add `eval "$(conda shell.bash hook)"` first |
| Groq 429 (rate limit) | Wait 1 min, or increase `--rate_limit_delay` |
| Groq 401 (auth) | Check `GROQ_API_KEY` is exported correctly |
| `data.jsonl` not found | Check for nested `EvoCodeBench-2403/EvoCodeBench-2403/` dir |
| Space issues | `du -sh */ \| sort -rh`, remove old output/checkpoints |
| Test dep conflicts | Create per-project venv for that project only |
