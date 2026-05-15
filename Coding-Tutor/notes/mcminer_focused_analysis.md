# McMiner Focused Results Analysis

**Source:** `output_latest/output/mcminer_focused/`
**What this is:** McMiner was run on student code extracted from the baseline TRAVER dialogues across all 4 projects. This shows what misconceptions McMiner *detects* before we use them to condition the tutor.

---

## 1. Dataset Overview

| Metric | Value |
|--------|-------|
| Total code samples analyzed | 175 |
| Unique tasks covered | 17 (of 22) |
| Misconceptions detected | 142 (81.1%) |
| No misconception found (NONE) | 33 (18.9%) |
| Unique descriptions | 142 (every detected misconception is unique) |
| Avg code length | 539 chars |

### Distribution by Project

| Project | Samples | Detected | Rate |
|---------|---------|----------|------|
| **easyvolcap** | 117 | 102 | **87.2%** |
| **searcharray** | 51 | 36 | **70.6%** |
| xinhua | 4 | 2 | 50.0% |
| codeformer_model | 2 | 2 | 100% |
| gfpgan_model | 1 | 0 | 0% |

### Distribution by Level

| Level | Samples | Detected | Rate |
|-------|---------|----------|------|
| low_level | 54 | 44 | 81.5% |
| med_level | 68 | 56 | 82.4% |
| high_level | 53 | 42 | 79.2% |

> [!NOTE]
> Detection rate is remarkably uniform across levels (~80-82%), meaning McMiner finds misconceptions regardless of how much context the student has. The question is whether those detections are *accurate and useful*—our re-tutoring results show they're useful for high_level but harmful for low_level.

---

## 2. Confidence Distribution

| Confidence | Count | % of Detected |
|------------|-------|---------------|
| **high** | 131 | **92.3%** |
| medium | 11 | 7.7% |
| low | 0 | 0% |

McMiner is overwhelmingly confident in its detections. This is a double-edged sword: high confidence means the tutor will strongly act on the misconception, which is great when the detection is correct (high_level) but problematic when it's noise (low_level).

---

## 3. Detection Rate by Dialogue Turn

| Turn | Samples | Detected | Rate |
|------|---------|----------|------|
| 1 | 17 | 7 | **41.2%** |
| 3 | 11 | 6 | **54.5%** |
| 5 | 23 | 20 | **87.0%** |
| 7 | 23 | 21 | **91.3%** |
| 9 | 21 | 17 | 81.0% |
| 11 | 27 | 21 | 77.8% |
| 13 | 28 | 26 | **92.9%** |
| 15 | 25 | 24 | **96.0%** |

> [!IMPORTANT]
> **Detection rate increases with dialogue turn:** 41% at Turn 1 → 96% at Turn 15. This makes sense—early turns produce vague/short code (harder to diagnose), while later turns produce more substantial code with clearer misconception patterns. This aligns with our finding that McMiner-conditioned tutoring becomes more effective in later rounds.

### Early vs Late

| Phase | Turns | Detected/Total | Rate |
|-------|-------|---------------|------|
| **Early** | 1–5 | 33/51 | **64.7%** |
| **Late** | 7–15 | 109/124 | **87.9%** |

---

## 4. Misconception Themes

| Theme | Count | % | Dominant Project |
|-------|-------|---|-----------------|
| **Tensor/Array operations** | 76 | **53.5%** | easyvolcap (61) |
| **OOP/Classes** | 43 | **30.3%** | easyvolcap (27) + searcharray (12) |
| **Control flow** | 23 | **16.2%** | easyvolcap (14) + searcharray (9) |

### By Project

**EasyVolcap** — dominated by tensor/broadcasting errors:
- Tensor shape compatibility for element-wise operations
- PyTorch broadcasting rules with `None` dimension expansion
- Vectorized conditional evaluation (`torch.where` eager evaluation)
- Confusion about annealing/scheduling functions

**searcharray** — dominated by OOP and API confusion:
- Redundant manual attribute assignment after constructor calls
- Misunderstanding constructors for state initialization
- Class method vs instance method behavior
- Incorrect criteria for query classification

---

## 5. Per-Task Coverage

| Task | Samples | Detected | Rate |
|------|---------|----------|------|
| `easyvolcap.utils.viewer_utils.Camera.to_batch` | 19 | 18 | 94.7% |
| `easyvolcap.utils.data_utils.add_batch` | 17 | 14 | 82.4% |
| `searcharray.postings.SearchArray.index` | 16 | 11 | 68.8% |
| `easyvolcap.utils.data_utils.to_cuda` | 14 | 10 | 71.4% |
| `easyvolcap.utils.fcds_utils.get_pytorch3d_camera_params` | 14 | 13 | 92.9% |
| `searcharray.postings.SearchArray.positions` | 13 | 9 | 69.2% |
| `easyvolcap.utils.fcds_utils.get_pulsar_camera_params` | 12 | 9 | 75.0% |
| `easyvolcap.utils.prop_utils.anneal_weights` | 12 | 11 | 91.7% |
| `searcharray.postings.SearchArray.phrase_freq` | 12 | 9 | 75.0% |
| `searcharray.solr.edismax` | 10 | 7 | 70.0% |
| `easyvolcap.utils.prop_utils.query` | 9 | 9 | 100% |
| `easyvolcap.utils.gl_utils.Quad.upload_to_texture` | 8 | 7 | 87.5% |
| `easyvolcap.utils.loss_utils.lossfun_distortion` | 8 | 7 | 87.5% |
| `easyvolcap.utils.prop_utils.max_dilate` | 4 | 4 | 100% |
| `xinhua.XinhuaHallucinations.statistics` | 4 | 2 | 50.0% |
| `codeformer_model.setup_model` | 2 | 2 | 100% |
| `gfpgan_model.setup_model` | 1 | 0 | 0% |

> [!TIP]
> Tasks with 90%+ detection rates are good candidates for McMiner-conditioned tutoring. The easyvolcap tasks with tensor operations consistently trigger misconception detection, which explains why McMiner helps high-level EasyVolcap students.

---

## 6. Sample Misconceptions

### EasyVolcap high_level (where McMiner helps)

**Task:** `lossfun_distortion` — Turn 13, high confidence
> **"Misunderstanding of broadcasting rules with `...` when tensor ranks differ"**
> Student believes `ut[..., None, :]` and `ut[..., None, :, None]` will align correctly. The actual broadcasting semantics differ.

**Task:** `anneal_weights` — Turn 15, high confidence
> **"Misidentification of Schlick's bias function"**
> Student calls an exponential annealing formula "Schlick's bias function"—a completely different mathematical concept.

**Task:** `query` — Turn 7, high confidence
> **"Misunderstanding the nature of step functions and interpolation"**
> Student assumes step functions require interpolation between steps, when they should return the most recent step value.

### searcharray (where McMiner doesn't help)

**Task:** `SearchArray.index` — Turn 15, high confidence
> **"Misunderstanding the primary role of constructors for object state initialization"**
> Student creates `SearchArray([])` then manually assigns each attribute. Accurate detection, but the real problem is not knowing the API.

**Task:** `SearchArray.positions` — Turn 11, high confidence
> **"Redundant conditional logic due to misunderstanding Python's default None handling"**
> Correct detection of a real misconception, but the task still fails because the student doesn't know which attributes exist.

---

## 7. Key Takeaways

1. **McMiner detects misconceptions in 81% of student code samples**, with 92% at high confidence. Detection itself is not the bottleneck.

2. **Detection rate increases with turns** (41% at T1 → 96% at T15). More dialogue produces more diagnosable code.

3. **All 142 detected misconceptions are unique**—McMiner generates novel, context-specific descriptions rather than repeating a fixed taxonomy. This validates the "mining" approach over rule-based detection.

4. **The dominant theme is tensor/array operations (54%)**, driven by EasyVolcap. This aligns with the high_level improvement: high-level students know enough PyTorch to write code with tensor errors, and McMiner correctly identifies the specific broadcasting/indexing misconception.

5. **searcharray misconceptions are accurately detected but insufficient**—the real barrier is unknown API surface (roaring bitmaps, custom postings lists), not conceptual misunderstanding. McMiner correctly identifies OOP confusion, but fixing that confusion doesn't help pass the tests.

6. **The 19% NONE rate is valuable**—these are cases where McMiner correctly identifies that the code doesn't exhibit a clear misconception (e.g., the code is just incomplete, not wrong). This prevents the tutor from fabricating misconceptions.

### Connection to Re-tutoring Results

| Finding | Explains |
|---------|----------|
| 87% detection on easyvolcap + tensor theme dominance | Why McMiner helps high_level EasyVolcap (+25.7pp) |
| Same 80%+ detection rate at all levels | Why McMiner hurts low_level: it detects "misconceptions" in broken code that are really just syntax gaps |
| 71% detection on searcharray + API-focused misconceptions | Why McMiner doesn't help searcharray: correct diagnosis, wrong remedy |
| Detection rate ↑ with turns | Why later rounds (R5-R7) show bigger McMiner effects |
