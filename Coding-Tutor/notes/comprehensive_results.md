# 📊 Comprehensive Results — McMiner-TRAVER

**Updated:** 2026-05-15  
**Benchmark:** EvoCodeBench-2403, 22 tasks across 4 projects, n=10 completions/task

---

## 1. Our Baseline Results (4 Focus Projects)

### Per-Project Best-Round Summary

| Project | Tasks | Level | Best Round | P@1 | P@3 | P@5 | P@10 |
|---|---|---|---|---|---|---|---|
| **sd-forge (codeformer)** | 1 | low | R1 | 90.0% | 100% | 100% | 100% |
| **sd-forge (codeformer)** | 1 | med | R1 | 100% | 100% | 100% | 100% |
| **sd-forge (codeformer)** | 1 | high | R1 | 90.0% | 100% | 100% | 100% |
| **sd-forge (gfpgan)** | 2 | low | R2 | 100% | 100% | 100% | 100% |
| **sd-forge (gfpgan)** | 2 | med | R1 | 85.0% | 100% | 100% | 100% |
| **sd-forge (gfpgan)** | 2 | high | R1 | 85.0% | 100% | 100% | 100% |
| **UHGEval** | 1 | low | R1 | 100% | 100% | 100% | 100% |
| **UHGEval** | 1 | med | R1 | 90.0% | 100% | 100% | 100% |
| **UHGEval** | 1 | high | R1 | 90.0% | 100% | 100% | 100% |
| **searcharray** | 6 | low | R1-R8 | 0.0% | 0.0% | 0.0% | 0.0% |
| **searcharray** | 6 | med | R1-R8 | 0.0% | 0.0% | 0.0% | 0.0% |
| **searcharray** | 6 | high | R8 | 15.0% | 24.2% | 25.0% | 25.0% |
| **EasyVolcap** | 12 | low | R7 | 23.0% | 27.1% | 29.2% | 30.0% |
| **EasyVolcap** | 12 | med | R4 | 16.0% | 23.7% | 27.5% | 30.0% |
| **EasyVolcap** | 12 | high | R1 | 15.8% | 25.0% | 28.5% | 33.3% |

### Baseline Peak P@1 by Project × Level

| Project | Tasks | low_level | med_level | high_level |
|---------|-------|-----------|-----------|------------|
| sd-forge | 3 | 90-100% (R1-R2) | 85-100% (R1) | 85-90% (R1) |
| UHGEval | 1 | 100% (R1) | 90% (R1) | 90% (R1) |
| searcharray | 6 | 0% | 0% | 15.0% (R8) |
| EasyVolcap | 12 | 23.0% (R7) | 16.0% (R4) | 15.8% (R1) |

---

## 2. McMiner Conditions — EasyVolcap (12 tasks)

### EasyVolcap Round-by-Round: Baseline vs McMiner-Loop vs McMiner-Clean

#### Pass@1

| Round | Baseline | McMiner | Clean | BL→MC | BL→CL |
|-------|----------|---------|-------|-------|--------|
| R1 | 12.5% / 3.3% / **15.8%** | 10.8% / 2.5% / 15.8% | 10.8% / **7.5%** / **19.2%** | −1.7 / −0.8 / 0.0 | −1.7 / **+4.2** / **+3.3** |
| R4 | 0.0% / **16.0%** / 9.0% | 2.0% / 0.0% / 15.0% | 2.0% / 1.7% / **16.7%** | +2.0 / −16.0 / +6.0 | +2.0 / −14.3 / **+7.7** |
| R7 | **23.0%** / 10.0% / 6.0% | 10.0% / 15.0% / 24.2% | 8.0% / **16.7%** / **31.7%** | −13.0 / +5.0 / **+18.2** | −15.0 / **+6.7** / **+25.7** |
| R8 | 21.0% / 10.0% / 6.0% | 5.0% / **16.7%** / 21.7% | 4.0% / **17.5%** / 15.0% | −16.0 / +6.7 / **+15.7** | −17.0 / **+7.5** / +9.0 |

*Format: low / med / high*

### 🏆 Headline Result: EasyVolcap high_level

**Best-vs-best comparison:**
- Baseline best: 15.8% P@1 (R1)
- McMiner-Clean best: 31.7% P@1 (R7)
- **Δ = +15.9pp**

**Same-round (R7) comparison:**

| Metric | Baseline | McMiner | Clean | Δ BL→CL (same-round) |
|--------|----------|---------|-------|----------|
| P@1 | 6.0% | 24.2% | **31.7%** | **+25.7pp** |
| P@3 | 12.2% | 35.7% | **40.8%** | **+28.6pp** |
| P@5 | 15.0% | 39.6% | **41.6%** | **+26.6pp** |
| P@10 | 20.0% | 41.7% | **41.7%** | **+21.7pp** |

> [!NOTE]
> The +25.7pp same-round delta is inflated because baseline degrades at R7. The fairer best-vs-best comparison is **+15.9pp**.

### McMiner Effectiveness by Student Level (EasyVolcap)

| Student Level | Baseline Best P@1 | McMiner Best P@1 | Clean Best P@1 | Winner |
|---|---|---|---|---|
| **low_level** | **23.0% (R7)** | 11.0% (R6) | 10.8% (R1) | ❌ Baseline |
| **med_level** | **16.0% (R4)** | 16.7% (R8) | **17.5% (R8)** | ≈ Tie (Clean edge) |
| **high_level** | 15.8% (R1) | 24.2% (R7) | **31.7% (R7)** | ✅ **Clean** |

> [!IMPORTANT]
> McMiner-Clean is the best configuration for high_level students (+15.9pp best-vs-best), roughly neutral for med_level, and harmful for low_level (−12pp). The damage at low_level comes from tutoring dialogue content, not prompt contamination.

---

## 3. McMiner Conditions — searcharray (6 tasks)

### All McMiner Conditions (Peak P@1)

| Condition | Rounds | low | med | high |
|-----------|--------|-----|-----|------|
| **Baseline** | R1-R8 | 0% | 0% | **15.0% (R8)** |
| McMiner-Loop | R1-R8 | 0% | 0% | 0% |
| McMiner-Clean | R1-R8 | 0% | 0% | 0% |
| McMiner-Clean-Ctx | R1-R8 | 0% | 0% | 0% |
| McMiner-Dedup | R1-R8 | 0% | 0% | 0% |
| **McMiner-Thorough** 🆕 | R1-R12 | 0% | 0% | **11.7% (R1)** |

### McMiner-Thorough searcharray Detail (🆕 from latest zip)

| Level | R1 | R2 | R3-R12 |
|-------|----|----|--------|
| low_level | 0% | 0% | 0% |
| med_level | 0% | 0% | 0% |
| **high_level** | **11.7%** (P@10=16.7%) | 5.0% (P@10=16.7%) | 0% |

> [!NOTE]
> McMiner-Thorough is the only McMiner condition with non-zero results for searcharray, but its 11.7% P@1 at high_level R1 is **lower than baseline's 15.0% at R8**. Extended rounds (R9-R12) provide no benefit.

---

## 4. McMiner Conditions — sd-forge, UHGEval (4 tasks)

### McMiner-Loop Results (Colab Rerun — corrected eval)

| Project | Task | Level | Best Round | BL P@1 | MC P@1 |
|---------|------|-------|-----------|--------|--------|
| **codeformer** | setup_model | low | R1 | 90.0% | **100%** |
| **codeformer** | setup_model | med | R1 | 100% | **100%** |
| **codeformer** | setup_model | high | R1 | 90.0% | **100%** |
| **gfpgan** | gfpgan_fix_faces + setup_model | low | R1 | 100% | **100%** |
| **gfpgan** | gfpgan_fix_faces + setup_model | med | R1 | 85.0% | **100%** |
| **gfpgan** | gfpgan_fix_faces + setup_model | high | R1 | 85.0% | **100%** |
| **xinhua** | statistics | low | R1 | 100% | **100%** |
| **xinhua** | statistics | med | R1 | 90.0% | **100%** |
| **xinhua** | statistics | high | R1 | 90.0% | **100%** |

### Combined sd-forge (3 tasks weighted average)

| Level | BL P@1 | MC P@1 |
|-------|--------|--------|
| low | 86.7% | **100%** |
| med | 90.0% | **100%** |
| high | 86.7% | **100%** |

> [!TIP]
> McMiner **maintains or exceeds** baseline performance on all easy projects. The previous 0% results were due to an evaluation pipeline bug in the HPC/Drive runs. The Colab rerun with corrected evaluation confirms no degradation.

*Source: `colab_mcminer_loop copy.ipynb` cell outputs (cells 38, 40, 42)*

---

## 5. mcminer_focused — Misconception Analysis (🆕 from latest zip)

| File | Content |
|------|---------|
| `mcminer_focused/extracted_code.json` (159 KB) | Student code samples extracted from dialogues |
| `mcminer_focused/misconception_results.json` (636 KB) | 175 misconception detection results |

Each entry contains: `namespace`, `project`, `level`, `turn_index`, `code_index`, `student_code`, `misconception_detected`, `misconception_description`, `misconception_explanation`, `confidence`, `raw_response`.

> [!TIP]
> This data enables qualitative analysis — which misconceptions are detected most frequently, how confidence varies by level, and whether detected misconceptions correlate with pass/fail outcomes.

---

## 6. Delta Summary — All McMiner Conditions vs Baseline

### EasyVolcap (Peak P@1)

| Level | Baseline | Δ McMiner-Loop | Δ McMiner-Clean |
|-------|----------|----------------|-----------------|
| low_level | 23.0% (R7) | **−12.0pp** (R6) | **−12.2pp** (R1) |
| med_level | 16.0% (R4) | +0.7pp (R8) | **+1.5pp** (R8) |
| high_level | 15.8% (R1) | **+8.4pp** (R7) | **+15.9pp** (R7) best-vs-best |

### searcharray (Peak P@1)

| Level | Baseline | Δ McMiner-Loop | Δ McMiner-Thorough |
|-------|----------|----------------|---------------------|
| low_level | 0% | 0pp | 0pp |
| med_level | 0% | 0pp | 0pp |
| high_level | 15.0% (R8) | −15.0pp | −3.3pp (R1) |

---

## 7. What's Still Needed

### ❌ Missing Evaluations

| Item | Priority | Notes |
|------|----------|-------|
| **EasyVolcap McMiner-Thorough** (R1-R12) | 🔴 HIGH | Key project, 12 tasks — thorough only done for searcharray so far |
| **EasyVolcap McMiner-Dedup** | 🟡 MED | Isolate dedup effect vs Thorough |
| **EasyVolcap McMiner-Clean-Ctx** | 🟡 MED | Test context window variant |
| **EasyVolcap McMiner-Th-Clean** | 🟡 MED | Thorough + clean prompts combined |

### ✅ Completed

| Item | Status |
|------|--------|
| EasyVolcap baseline (R1-R8, all levels) | ✅ |
| EasyVolcap McMiner-Loop (R1-R8, all levels) | ✅ |
| EasyVolcap McMiner-Clean (R1-R8, all levels) | ✅ |
| searcharray baseline (R1-R8, all levels) | ✅ |
| searcharray McMiner-Loop/Clean/Dedup/Clean-Ctx (R1-R8) | ✅ |
| searcharray McMiner-Thorough (R1-R12, all levels) | ✅ 🆕 |
| sd-forge baseline | ✅ |
| UHGEval baseline | ✅ |
| sd-forge McMiner-Loop (Colab rerun, all levels) | ✅ 🆕 |
| UHGEval McMiner-Loop (Colab rerun, all levels) | ✅ 🆕 |
| mcminer_focused misconception data (175 entries) | ✅ |

### 📝 Analysis Items

| Item | Priority |
|------|----------|
| Analyze `mcminer_focused/misconception_results.json` qualitatively | 🟡 |
| Cross-reference misconceptions with pass/fail outcomes | 🟡 |
| ~~Investigate McMiner 0% bug on easy projects~~ | ✅ Resolved — Colab rerun shows 100% |
| Document which searcharray task passes at high_level | 🟢 |

---

## 8. Key Conclusions

1. **McMiner-Clean is the best configuration for high-level students** — +15.9pp P@1 best-vs-best over baseline on EasyVolcap (31.7% vs 15.8%)
2. **McMiner maintains performance on easy tasks** — 100% P@1 on sd-forge and UHGEval (matching or exceeding baseline)
3. **McMiner hurts low-level students** — misconception detection on broken diagnostic code introduces noise (−12pp on EasyVolcap)
4. **McMiner-Thorough doesn't help searcharray** — 11.7% at R1 is lower than baseline's 15.0% at R8; extended rounds provide no benefit
5. **Level-adaptive McMiner is the way forward** — skip McMiner for low_level, use McMiner-Clean for high_level
6. **The 60-word budget matters** — clean-prompt improvement confirms misconception meta-text crowds out useful code hints
7. **EasyVolcap McMiner-Thorough is the top remaining experiment** — could combine the Thorough strategy with the proven Clean approach
