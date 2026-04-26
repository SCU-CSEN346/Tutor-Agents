#!/usr/bin/env python3
"""
Compile TRAVER evaluation results across all projects, levels, and rounds.
Produces per-project, per-level, per-round, and aggregate Pass@k tables.
"""
import json
import os
import sys
from collections import defaultdict

import numpy as np

# ──────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────
BASE = "/Users/catherine/PycharmProjects/Coding-Tutor/output/student_posttest"
METADATA = "/Users/catherine/PycharmProjects/Coding-Tutor/benchmark/EvoCodeBench-2403/metadata_filtered.jsonl"
TUTOR = "traver"
MODEL = "Llama-3.1-70B-Instruct"
LEVELS = ["low_level", "med_level", "high_level"]
ROUNDS = list(range(1, 9))
N = 10  # completions per task
K_LIST = [1, 3, 5, 10]


def compute_pass_at_k(n, c, k):
    """Unbiased estimator for Pass@k."""
    if n - c < k:
        return 1.0
    return 1.0 - float(np.prod(1.0 - k / np.arange(n - c + 1, n + 1)))


# ──────────────────────────────────────────────────────
# Load metadata: namespace → project
# ──────────────────────────────────────────────────────
benchmark = {}
ns_to_project = {}
with open(METADATA) as f:
    for line in f:
        js = json.loads(line)
        ns = js["namespace"]
        benchmark[ns] = js
        ns_to_project[ns] = js.get("completion_path", "").split("/")[0]

all_projects = sorted(set(ns_to_project.values()))
project_tasks = defaultdict(set)
for ns, proj in ns_to_project.items():
    project_tasks[proj].add(ns)


# ──────────────────────────────────────────────────────
# Parse all test_results.jsonl files
# ──────────────────────────────────────────────────────
# results[level][round][project][namespace] = num_passes (out of N)
results = {}

for level in LEVELS:
    results[level] = {}
    for rdx in ROUNDS:
        log_path = os.path.join(BASE, TUTOR, MODEL, level, f"round_{rdx}", "test_results.jsonl")
        comp_path = os.path.join(BASE, TUTOR, MODEL, level, f"round_{rdx}", "completion.jsonl")

        if not os.path.exists(log_path) or not os.path.exists(comp_path):
            continue

        # Collect passes
        passed = defaultdict(set)
        with open(log_path) as f:
            for line in f:
                js = json.loads(line)
                if js.get("Result") == "Pass":
                    passed[js["namespace"]].add(js["completion"])

        # Count per-namespace from completion file
        ns_passes = {}
        with open(comp_path) as f:
            for line in f:
                js = json.loads(line)
                ns = js["namespace"]
                if ns in benchmark:
                    if ns not in ns_passes:
                        ns_passes[ns] = 0
                    if ns in passed and js["completion"] in passed[ns]:
                        ns_passes[ns] += 1

        # Organize by project
        round_data = defaultdict(dict)
        for ns, c in ns_passes.items():
            proj = ns_to_project.get(ns, "unknown")
            round_data[proj][ns] = c

        results[level][rdx] = dict(round_data)


# ──────────────────────────────────────────────────────
# Helper: compute Pass@k from a dict {namespace: count}
# ──────────────────────────────────────────────────────
def pass_at_k_from_dict(ns_dict, k):
    if not ns_dict:
        return None
    values = list(ns_dict.values())
    return np.mean([compute_pass_at_k(N, c, k) for c in values]) * 100


def format_pak(val):
    if val is None:
        return "  —  "
    return f"{val:5.1f}%"


# ──────────────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────────────
sep = "=" * 90

print(sep)
print("  TRAVER Evaluation Results — Llama-3.1-70B-Instruct")
print(f"  10 Projects, {len(benchmark)} total tasks, n={N} completions per task")
print(sep)

# ════════════════════════════════════════════════════════
# 1. PER-PROJECT BREAKDOWN (all levels × all rounds)
# ════════════════════════════════════════════════════════
print(f"\n{'─' * 90}")
print("  SECTION 1: Per-Project Results")
print(f"{'─' * 90}")

for proj in all_projects:
    task_count = len(project_tasks[proj])
    print(f"\n  ┌── {proj} ({task_count} tasks) ──")

    for level in LEVELS:
        has_data = False
        for rdx in ROUNDS:
            if rdx in results.get(level, {}) and proj in results[level][rdx]:
                has_data = True
                break
        if not has_data:
            continue

        print(f"  │  {level}:")
        header = f"  │    {'Round':<10}"
        for k in K_LIST:
            header += f"  Pass@{k:<3}"
        header += f"  {'Tasks':>6}  {'Passed':>6}"
        print(header)

        for rdx in ROUNDS:
            rd = results.get(level, {}).get(rdx, {})
            ns_dict = rd.get(proj, {})
            if not ns_dict:
                continue
            tasks = len(ns_dict)
            passed_count = sum(1 for v in ns_dict.values() if v > 0)
            row = f"  │    round_{rdx:<4}"
            for k in K_LIST:
                row += f"  {format_pak(pass_at_k_from_dict(ns_dict, k))}"
            row += f"  {tasks:>6}  {passed_count:>6}"
            print(row)
    print(f"  └{'─' * 50}")

# ════════════════════════════════════════════════════════
# 2. PER-LEVEL, PER-ROUND (all projects combined)
# ════════════════════════════════════════════════════════
print(f"\n{'─' * 90}")
print("  SECTION 2: Aggregate Results (All Projects Combined)")
print(f"{'─' * 90}")

for level in LEVELS:
    print(f"\n  === {level} ===")
    header = f"    {'Round':<10}"
    for k in K_LIST:
        header += f"  Pass@{k:<3}"
    header += f"  {'Tasks':>6}  {'Passed':>6}"
    print(header)

    for rdx in ROUNDS:
        rd = results.get(level, {}).get(rdx, {})
        # Combine all projects
        combined = {}
        for proj, ns_dict in rd.items():
            combined.update(ns_dict)
        if not combined:
            continue
        tasks = len(combined)
        passed_count = sum(1 for v in combined.values() if v > 0)
        row = f"    round_{rdx:<4}"
        for k in K_LIST:
            row += f"  {format_pak(pass_at_k_from_dict(combined, k))}"
        row += f"  {tasks:>6}  {passed_count:>6}"
        print(row)

# ════════════════════════════════════════════════════════
# 3. CROSS-LEVEL COMPARISON (average across rounds)
# ════════════════════════════════════════════════════════
print(f"\n{'─' * 90}")
print("  SECTION 3: Cross-Level Comparison (Average Across All Rounds)")
print(f"{'─' * 90}")

header = f"  {'Level':<15}"
for k in K_LIST:
    header += f"  Pass@{k:<3}"
header += f"  {'Rounds':>7}"
print(header)

for level in LEVELS:
    all_pak = {k: [] for k in K_LIST}
    round_count = 0
    for rdx in ROUNDS:
        rd = results.get(level, {}).get(rdx, {})
        combined = {}
        for proj, ns_dict in rd.items():
            combined.update(ns_dict)
        if not combined:
            continue
        round_count += 1
        for k in K_LIST:
            all_pak[k].append(pass_at_k_from_dict(combined, k))

    row = f"  {level:<15}"
    for k in K_LIST:
        if all_pak[k]:
            avg = np.mean([v for v in all_pak[k] if v is not None])
            row += f"  {avg:5.1f}%"
        else:
            row += f"  {'—':>6}"
    row += f"  {round_count:>7}"
    print(row)

# ════════════════════════════════════════════════════════
# 4. PER-PROJECT SUMMARY (average across all levels & rounds)
# ════════════════════════════════════════════════════════
print(f"\n{'─' * 90}")
print("  SECTION 4: Per-Project Summary (Average Pass@k Across All Levels & Rounds)")
print(f"{'─' * 90}")

header = f"  {'Project':<35} {'Tasks':>5}"
for k in K_LIST:
    header += f"  Pass@{k:<3}"
header += f"  {'DataPts':>8}"
print(header)

grand_pak = {k: [] for k in K_LIST}

for proj in all_projects:
    task_count = len(project_tasks[proj])
    all_pak = {k: [] for k in K_LIST}
    data_points = 0
    for level in LEVELS:
        for rdx in ROUNDS:
            rd = results.get(level, {}).get(rdx, {})
            ns_dict = rd.get(proj, {})
            if not ns_dict:
                continue
            data_points += 1
            for k in K_LIST:
                val = pass_at_k_from_dict(ns_dict, k)
                if val is not None:
                    all_pak[k].append(val)

    row = f"  {proj:<35} {task_count:>5}"
    for k in K_LIST:
        if all_pak[k]:
            avg = np.mean(all_pak[k])
            row += f"  {avg:5.1f}%"
            grand_pak[k].append(avg)
        else:
            row += f"  {'—':>6}"
    row += f"  {data_points:>8}"
    print(row)

print(f"  {'─' * 85}")
row = f"  {'GRAND AVERAGE':<35} {'':>5}"
for k in K_LIST:
    if grand_pak[k]:
        row += f"  {np.mean(grand_pak[k]):5.1f}%"
    else:
        row += f"  {'—':>6}"
print(row)

print(f"\n{sep}")
print("  END OF REPORT")
print(sep)
