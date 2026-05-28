# Post-hoc Repair Results

**Date:** 2026-05-25
**Setting:** TRAVER completions followed by a repair pass on failed outputs
**Repair model:** `meta-llama/Llama-3.3-70B-Instruct`

## Method

Repair is a second-stage debugger applied after TRAVER generation. It does not
change the TRAVER tutoring loop.

For each failed completion, the repair prompt includes:

- the original task prompt
- source-code context from the target repository
- the failed TRAVER completion
- pytest failure output

The model rewrites only the target function body, and the repaired completion is
then re-evaluated with the same test suite.

## Summary

| Project | Level | TRAVER P@1 | TRAVER P@10 | TRAVER + Repair P@1 | TRAVER + Repair P@k | Result |
|---|---:|---:|---:|---:|---:|---|
| EasyVolcap | low | 23.0 | 30.0 | 25.3 | 40.0 P@10 | small improvement |
| EasyVolcap | med | 16.0 | 30.0 | 16.8 | 37.7 P@10 | small improvement |
| searcharray | low | 0.0 | 0.0 | 0.0 | 0.0 P@3 | no rescue |
| searcharray | med | 0.0 | 0.0 | 22.2 | 33.3 P@3 | rescued 2/6 tasks |

For searcharray med-level, repair generated three candidates per task, so the
reported repaired metric is P@3 rather than P@10.

## Low-level Repair Model Checks

We also ran smaller low-level checks to separate the effect of repair feedback
from the effect of model strength.

| Project group | TRAVER baseline | 8B repair | 8B peer repair | 70B repair | Strong repair | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| EasyVolcap low-level | 3/12 | 0/12 | 0/12 | 5/12 | 4/12 | repair helped only with a 70B-class model |
| gfpgan/xinhua low-level | 2/3 | not run | not run | 3/3 | 3/3 | both 70B repair variants rescued xinhua |
| searcharray low-level | 0/6 | not run | not run | 0/6 | 0/6 | neither 70B repair variant helped |
| codeformer_model low-level | 10/10 | not run | not run | not run | not run | baseline was already solved |

The EasyVolcap 8B checks are the fairest comparison with the original code
generator. They did not improve results. This means the 70B repair gain should
not be described as evidence that pytest feedback alone helps; it also depends
on stronger model capacity.

## Second-student Prompt Check

We tested a fair second-student setup on EasyVolcap using the same 8B code
generator. The prompt included task metadata and previous failed student
attempts with their failure summaries, but no source-code answer or reference
solution.

| Project | Level | Baseline TRAVER | Second-student 8B prompt | Result |
| --- | ---: | ---: | ---: | --- |
| EasyVolcap | low | 3/12 | 0/12 | worse |
| EasyVolcap | med | about 3/10 | 0/10 | worse |

The failed attempts and errors appear to pollute the prompt for the 8B model.
Instead of learning from the previous student, the model often repeats or
overreacts to broken patterns.

## Per-Project Notes

### EasyVolcap low-level

Repair was run across the standard TRAVER rounds. The largest useful gain was
around the best baseline rounds, where repaired candidates improved the number
of solved tasks and increased P@10 from 30.0% to about 40.0%.

### EasyVolcap med-level

A small check showed one additional task rescued:
`easyvolcap.utils.prop_utils.query`. This raised P@10 from 30.0% to about 37.7%.

### searcharray low-level

Baseline TRAVER was 0/6 solved and repair also rescued 0/6 tasks. The repaired
outputs usually still missed internal API details or produced incomplete
implementations.

### searcharray med-level

Baseline TRAVER was 0/6 solved. Repair@3 rescued:

- `searcharray.postings.SearchArray.positions`
- `searcharray.utils.bitcount.bit_count64`

The remaining failed tasks were:

- `searcharray.postings.SearchArray.index`
- `searcharray.postings.SearchArray.phrase_freq`
- `searcharray.solr.edismax`
- `searcharray.solr.parse_min_should_match`

## Interpretation

Repair is most useful when TRAVER produces a completion that is close enough for
execution feedback to guide correction. It is less effective when the initial
completion lacks the project-specific API knowledge needed for the task.

The strongest result is searcharray med-level, where both TRAVER and McMiner
were at 0%, but post-hoc repair rescued 2 out of 6 tasks. The method should be
described as `TRAVER + repair`, not as a modification to TRAVER itself.
