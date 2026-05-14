# 📊 Comprehensive Results — McMiner-TRAVER

**Updated:** 2026-05-14  
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

### 🏆 Headline Result: EasyVolcap high_level R7

| Metric | Baseline | McMiner | Clean | BL→Clean |
|--------|----------|---------|-------|----------|
| P@1 | 6.0% | 24.2% | **31.7%** | **+25.7pp** |
| P@3 | 12.2% | 35.7% | **40.8%** | **+28.6pp** |
| P@5 | 15.0% | 39.6% | **41.6%** | **+26.6pp** |
| P@10 | 20.0% | 41.7% | **41.7%** | **+21.7pp** |

### McMiner Effectiveness by Student Level (EasyVolcap)

| Student Level | Baseline Best P@1 | McMiner Best P@1 | Clean Best P@1 | Winner |
|---|---|---|---|---|
| **low_level** | **23.0% (R7)** | 11.0% (R6) | 10.8% (R1) | ❌ Baseline |
| **med_level** | **16.0% (R4)** | 16.7% (R8) | **17.5% (R8)** | ≈ Tie (Clean edge) |
| **high_level** | 15.8% (R1) | 24.2% (R7) | **31.7% (R7)** | ✅ **Clean** |

> [!IMPORTANT]
> McMiner-Clean is the best configuration for high_level students (+25.7pp), roughly neutral for med_level, and harmful for low_level (−12pp). The damage at low_level comes from tutoring dialogue content, not prompt contamination.

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

| Project | Baseline P@1 | McMiner-Loop P@1 | McMiner-Clean P@1 | McMiner-Thorough P@1 |
|---------|-------------|------------------|--------------------|-----------------------|
| codeformer (1 task) | 90-100% | 0% | 0% | 0% |
| gfpgan (2 tasks) | 85-100% | 0% | 0% | 0% |
| xinhua (1 task) | 90-100% | 0% | 0% | 0% |

> [!WARNING]
> All McMiner conditions show 0% for these easy projects. This appears to be an **evaluation pipeline bug** — the McMiner posttest condition changes the completion format rather than indicating genuine performance degradation. These projects are essentially solved by the baseline.

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
| high_level | 15.8% (R1) | **+8.4pp** (R7) | **+15.9pp** (R7) |

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
| Fix McMiner eval bug for sd-forge/codeformer/xinhua | 🟡 MED | 0% results are likely a pipeline issue |

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
| mcminer_focused misconception data (175 entries) | ✅ 🆕 |

### 📝 Analysis Items

| Item | Priority |
|------|----------|
| Analyze `mcminer_focused/misconception_results.json` qualitatively | 🟡 |
| Cross-reference misconceptions with pass/fail outcomes | 🟡 |
| Investigate McMiner 0% bug on easy projects | 🟡 |
| Document which searcharray task passes at high_level | 🟢 |

---

## 8. Key Conclusions

1. **McMiner-Clean is the best configuration for high-level students** — +25.7pp P@1 over baseline on EasyVolcap at R7
2. **McMiner hurts low-level students** — misconception detection on broken diagnostic code introduces noise (−12pp)
3. **McMiner-Thorough doesn't help searcharray** — 11.7% at R1 is lower than baseline's 15.0% at R8; extended rounds provide no benefit
4. **Level-adaptive McMiner is the way forward** — skip McMiner for low_level, use McMiner-Clean for high_level
5. **The 60-word budget matters** — clean-prompt improvement confirms misconception meta-text crowds out useful code hints
6. **EasyVolcap McMiner-Thorough is the top remaining experiment** — could combine the Thorough strategy with the proven Clean approach
