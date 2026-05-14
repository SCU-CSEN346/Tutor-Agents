# McMiner-in-the-Loop: Ablation Study Ideas

## Primary Comparison

| Run | Description | Output Dir |
|-----|-------------|------------|
| **Baseline** | Standard TRAVER (no McMiner) | `dialogue_by_project/` |
| **McMiner-Loop (A)** | Latest-only injection | `mcminer_loop/` |

This is our main experiment. Everything below is for follow-up ablation studies
if time permits.

---

## Ablation 1: Injection Strategy

Compare how misconceptions are presented to the tutor.

| Variant | What Tutor Sees | Hypothesis |
|---------|----------------|------------|
| **A. Latest only** (current) | Only current round's misconception; removed if NONE | Clean, focused feedback; avoids repetition |
| **B. Accumulate all** | Full history of all detected misconceptions | More context but may cause repetition and confusion |
| **C. Sliding window (last 2)** | Last 2 rounds' misconceptions | Balances context and focus |
| **D. Active tracking** | Only misconceptions still present in latest code | Most accurate but McMiner wording varies, hard to match |

**Prediction:** A > B because the tutor already has conversation history.
B might cause the tutor to fixate on resolved issues.

## Ablation 2: Diagnostic Codegen Sampling

Compare how many code samples we generate for diagnosis between rounds.

| Variant | N | Hypothesis |
|---------|---|------------|
| N=1 (current) | Single sample | Fast, cheap; may miss intermittent issues |
| N=3 majority vote | 3 samples, McMiner on majority pattern | More robust detection, 3x slower |

**Prediction:** N=1 is sufficient. Misconceptions are systematic, not random —
they'll show up consistently.

## Ablation 3: McMiner Frequency

Compare running McMiner every round vs. every other round.

| Variant | When McMiner Runs | Hypothesis |
|---------|-------------------|------------|
| Every round (current) | R1, R2, R3, R4, R5, R6, R7, R8 | Maximum feedback |
| Every 2 rounds | R2, R4, R6, R8 | Gives student time to process; 50% fewer API calls |
| First 4 only | R1, R2, R3, R4 | Early intervention matters most |

**Prediction:** Every round is best for low-level students.
Every-2 might be better for high-level (avoids over-tutoring).

## Ablation 4: McMiner Model

Compare different models for misconception detection.

| Variant | McMiner Model | Hypothesis |
|---------|---------------|------------|
| Gemini 2.5 Flash (current) | Fast, cheap | Good enough for detection |
| Gemini 2.5 Pro | Slower, more capable | Better at subtle misconceptions |
| GPT-4o | Different perspective | May catch different misconception types |

## Ablation 5: With vs. Without Verifier

Test if McMiner feedback reduces the need for the verifier.

| Variant | Verifier | McMiner | Hypothesis |
|---------|----------|---------|------------|
| Baseline | Yes | No | Original TRAVER |
| McMiner-Loop (current) | Yes | Yes | Both signals complement each other |
| McMiner-only | No | Yes | Does McMiner replace the verifier? |

**Prediction:** Both together is best. Verifier selects the best tutor response;
McMiner tells the tutor what to focus on. Different roles.

## Ablation 6: Level-Specific Analysis

Our baseline shows tutoring helps low-level but hurts high-level.
Does McMiner-Loop fix the high-level degradation?

| Level | Baseline Trend | McMiner-Loop Prediction |
|-------|---------------|------------------------|
| Low | Improves R1→R7 (+10.5pp) | Should improve more — misconceptions are addressed earlier |
| Med | Mixed | Should stabilize — fewer wasted rounds |
| High | Degrades R1→R8 (-9.8pp) | **Key test:** does targeted feedback prevent degradation? |

If McMiner-Loop prevents high-level degradation, that's the strongest evidence
for the approach.

## Ablation 7: Verifier Early-Stop Fixes

Our baseline shows a bimodal turn distribution: 31% of tasks stop after round 1,
69% go all 8 rounds, and NOTHING in between. The verifier triggers on the student's
text (not code), causing false positives when the student sounds knowledgeable.

| Variant | Change | Hypothesis |
|---------|--------|------------|
| **Baseline** (current) | No minimum rounds | 31% premature stops at R1 |
| **Min-rounds (N=3)** | Block early-stop before round 3 | Forces at least 3 rounds of tutoring |
| **Code-gated stop** | Only check verifier if student response contains code (`def`, `import`, triple-backtick) | Prevents false positives on conversational responses |
| **Higher threshold** | Raise verifier score cutoff | Fewer false positives, more rounds |

Implementation locations:
- Turn order: `chatarena/environments/conversation.py:43-47`
- Terminal check: `chatarena/environments/conversation.py:130-144`
- Verifier scoring: `chatarena/agent_tutor.py:101`

**Priority:** Code-gated stop is the easiest and most principled fix.

## Ablation 8: Token Budget for Codegen

Our baseline had 500-token completions that truncated mid-statement, causing
SyntaxErrors that poison the entire module import. We fixed this to 1024.

| Variant | max_tokens | Hypothesis |
|---------|-----------|------------|
| 500 (paper default) | Short | Truncation → SyntaxError → 0% on complex tasks |
| **1024 (current)** | Medium | Prevents most truncation |
| 1500 | Long | May help very complex functions (searcharray) |
| Adaptive | `max(500, len(ref_code) * 2)` | Optimal per-task budget |

## Ablation 9: Syntax Pre-Check Before Evaluation

Add `compile(source, filename, 'exec')` check before running pytest.
If a completion has a SyntaxError, mark as Fail immediately without
importing the module — prevents cross-contamination where a bad
completion for function A breaks tests for function B in the same file.

| Variant | Check | Hypothesis |
|---------|-------|------------|
| Baseline (current) | No pre-check | SyntaxError poisons entire module |
| **Syntax-gated** | compile() before pytest | Cleaner failure mode, no cross-contamination |

## Ablation 10: McMiner-Loop + Framework Fixes Combined

The most interesting comparison: combine McMiner-in-the-loop with the
verifier fixes. This tests whether the improvements stack.

| Variant | McMiner | Verifier Fix | Expected |
|---------|---------|-------------|----------|
| Baseline | No | No | 27.5% P@1 |
| McMiner-only (current run) | Yes | No | ??? |
| Framework-fix-only | No | Code-gated + min-rounds | ??? |
| **Combined** | Yes | Code-gated + min-rounds | Best performance? |

---

## Ablation 11: Retrain Verifier on Misconception-Aware Dialogues

The current verifier was trained on vanilla TRAVER dialogues. It scores
candidates based on "does this response lead to task completion?" — but
it has never seen misconception-addressing responses during training.

| Variant | Verifier | McMiner | Hypothesis |
|---------|----------|---------|------------|
| Current | Pretrained (vanilla) | Yes | Verifier still picks best phrasing; McMiner shapes content via prompt |
| **Retrained** | Trained on McMiner-loop dialogues | Yes | Verifier learns to prefer misconception-addressing responses |

**Requirements:** Need to complete the primary McMiner-loop run first,
get outcome labels (pass/fail), label each turn with process rewards,
then retrain LoRA head. Two-pass experiment — expensive.

**Why it's low priority:** McMiner injection operates at the prompt level,
before response generation. ALL N candidates will be misconception-aware.
The verifier just picks the best delivery. Retraining the verifier would
also change two variables at once, making it hard to isolate what helped.

---

## Ablation 12: Semantic Deduplication 🆕

**Status: IMPLEMENTED** — `colab_mcminer_dedup.ipynb`

Motivated by searcharray findings: McMiner detected a misconception in 42/43
rounds (98%), causing the tutor to constantly shift topics instead of building
a coherent lesson. Many were the same fundamental issue worded differently.

| What | Detail |
|------|--------|
| **Change** | Before injection, use Gemini to check if new misconception is semantically same as previous |
| **If DUPLICATE** | Skip injection, tutor keeps current teaching strategy |
| **If NOVEL** | Inject as usual |
| **Output** | `mcminer_loop_dedup/` → `student_posttest_mcminer_dedup/` |

**Hypothesis:** Reducing redundant injections will let the tutor maintain focus,
leading to better progressive teaching (especially for high-level students).

## Ablation 13: Thorough McMiner (Dedup + Dynamic Rounds + Full Context) 🆕

**Status: IMPLEMENTED** — `colab_mcminer_thorough.ipynb`

Combines four changes into a "thorough tutoring" strategy:

| # | Change | Detail |
|---|--------|--------|
| 1 | **Semantic Dedup** | Skip injection if same fundamental issue as before |
| 2 | **Dynamic Rounds (R8→R12)** | Keep tutoring until 2 consecutive clean rounds, hard cap R12 |
| 3 | **No Early Stop Override** | Moderator can't cut conversation if misconception still active |
| 4 | **Accumulated Context** | Tutor sees ALL unique misconceptions found so far, not just latest |

The accumulated context gives the tutor a message like:
```
[MISCONCEPTION HISTORY]
Over the tutoring session, the student has shown these distinct misconceptions:
  Round 1: Wrong dimension in reshape operation
  Round 3: Missing gradient detach in loss computation
  Round 5: Incorrect loss function choice
Focus on the most fundamental unresolved issue.
[END MISCONCEPTION HISTORY]
```

**Output:** `mcminer_loop_thorough/` → `student_posttest_mcminer_thorough/`

**Hypothesis:** Combined, these ensure students with real misconceptions get
enough focused tutoring to overcome them, while avoiding noise from duplicates.

---

## Priority Order

1. ~~**Primary run**~~ ✅ McMiner-Loop (A) vs Baseline — DONE (easyvolcap + searcharray)
2. ~~**Ablation 6**~~ ✅ Level-specific analysis — DONE (comes free with primary run)
3. 🔴 **Ablation 13** — Thorough McMiner (dedup + dynamic rounds)
   - ✅ searcharray: DONE (R1-R12, all levels). Result: 11.7% P@1 at high_level R1 (1/6 tasks), 0% elsewhere. Does NOT outperform baseline's 15% at R8.
   - ❌ **easyvolcap: NOT DONE** ← **TOP PRIORITY** — this is the key project (12 tasks)
4. 🟡 **Ablation 12** — Dedup only ← run after thorough to isolate dedup effect
5. **Ablation 7** — Verifier early-stop fixes ← addresses known framework weakness
6. **Ablation 3** — Frequency (every round vs every-2) ← easy to implement
7. **Ablation 10** — Combined McMiner + framework fixes ← best-case scenario
8. **Ablation 1** — A vs B (latest-only vs accumulate) ← partially covered by Ablation 13
9. **Ablation 2, 4, 5, 8, 9** — lower priority, only if time permits
10. **Ablation 11** — Retrain verifier ← requires two-pass, only if time permits

