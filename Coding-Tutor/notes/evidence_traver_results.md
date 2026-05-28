# Evidence-Grounded TRAVER Results

**Date:** 2026-05-26
**Setting:** EasyVolcap low-level, TRAVER round 7
**Codegen model:** `meta-llama/Llama-3.1-70B-Instruct`

## Method

This experiment tested an evidence-grounded variant of TRAVER. Before final
code generation, a short evidence note was generated from source-code and test
excerpts. The note was inserted into the normal TRAVER posttest prompt.

The intended constraint was that the note should identify visible repository
evidence, such as relevant variables, methods, return types, and test
expectations, without directly giving the solution algorithm.

## Result

| Method | Setting | P@1 | P@3 | P@5 | P@10 |
|---|---|---:|---:|---:|---:|
| TRAVER baseline | EasyVolcap low R7 | 23.0 | 27.1 | 29.2 | 30.0 |
| Evidence-grounded TRAVER | EasyVolcap low R7 | 0.0 | 0.0 | 0.0 | 0.0 |

## Interpretation

This variant did not work. The evidence notes were too weak or noisy to prevent
wrong project-API guesses. Generated completions were usually syntactically
valid, but still failed EasyVolcap tests because they missed tensor details,
internal helper behavior, or exact repository conventions.

This result is similar to the scaffolded TRAVER failure: adding static context
or repository-reading notes did not solve the main bottleneck. Post-hoc repair
remains the stronger direction because it uses concrete pytest failure feedback.
