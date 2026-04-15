"""
Analyze pass@k and recall@k results from the extracted output files.
Computes metrics from test_results.jsonl and dependency_results.jsonl.
"""
import json
import os
import numpy as np
from collections import defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
POSTTEST = os.path.join(BASE, "student_posttest", "vanilla", "Llama-3.3-70B-Instruct")

LEVELS = ["low_level", "med_level", "high_level"]
ROUNDS = list(range(1, 9))
K_LIST = [1, 3, 5, 10]
N = 10


def compute_pass_at_k(n, c, k):
    """Compute pass@k: probability at least one of k samples passes."""
    if n - c < k:
        return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))


def compute_recall(generated_dep, reference_dep):
    """Compute recall of dependencies."""
    reference = []
    for _type, _list in reference_dep.items():
        reference.extend(_list)
    if generated_dep is None:
        return 0.0
    prediction = []
    for _type, _list in generated_dep.items():
        prediction.extend(_list)
    reference = set(reference)
    prediction = set(prediction)
    if len(reference) == 0:
        return 1.0  # No dependencies to recall
    return len(reference.intersection(prediction)) / len(reference)


def analyze_pass_k(test_results_file, completion_file):
    """Compute pass@k from test_results.jsonl."""
    if not os.path.exists(test_results_file):
        return None

    # Collect unique passed completion strings per namespace
    passed_strings = defaultdict(set)
    total_entries = 0
    with open(test_results_file, 'r') as f:
        for line in f:
            js = json.loads(line)
            total_entries += 1
            if js.get('Result') == 'Pass':
                passed_strings[js['namespace']].add(js['completion'])

    # Count total and passed completions from the completion file (to account for duplicates)
    ns_completions = defaultdict(int)
    ns_passed_count = defaultdict(int)
    
    if os.path.exists(completion_file):
        with open(completion_file, 'r') as f:
            for line in f:
                js = json.loads(line)
                ns = js['namespace']
                comp = js['completion']
                ns_completions[ns] += 1
                if comp in passed_strings.get(ns, set()):
                    ns_passed_count[ns] += 1

    # Compute pass@k
    results = {}
    for ns, count in ns_completions.items():
        c = ns_passed_count.get(ns, 0)
        results[ns] = (count, c)

    metrics = {}
    for k in K_LIST:
        vals = []
        for ns, (n_actual, c) in results.items():
            if n_actual >= k:
                vals.append(compute_pass_at_k(n_actual, c, k))
        if vals:
            metrics[k] = np.mean(vals) * 100
        else:
            metrics[k] = 0.0

    # For reporting, just sum up values
    pass_count = sum(ns_passed_count.values())
    fail_count = sum(ns_completions.values()) - pass_count

    return {
        'metrics': metrics,
        'total_entries': total_entries,
        'pass_count': pass_count,
        'fail_count': fail_count,
        'num_tasks': len(ns_completions),
        'tasks_with_passes': len(passed_strings),
    }


def analyze_recall_k(dep_results_file, completion_file):
    """Compute recall@k from dependency_results.jsonl."""
    if not os.path.exists(dep_results_file):
        return None

    # Parse results grouped by namespace
    results_by_ns = defaultdict(list)
    total_entries = 0
    with open(dep_results_file, 'r') as f:
        for line in f:
            js = json.loads(line)
            total_entries += 1
            ns = js['namespace']
            gen_dep = js.get('generated_dependency')
            results_by_ns[ns].append(gen_dep)

    # We need an external reference for recall computation
    # The dependency_results.jsonl doesn't store the reference dependency.
    # However, we can compute "how many tasks had non-null dependencies generated"
    # For recall@k, we take max recall over top-k samples per namespace.
    # Since we don't have the reference here, let's report what we can.

    return {
        'total_entries': total_entries,
        'num_tasks': len(results_by_ns),
        'tasks_with_deps': sum(1 for ns, deps in results_by_ns.items() if any(d is not None for d in deps)),
    }


def main():
    print("=" * 80)
    print("  CODING-TUTOR VANILLA BASELINE RESULTS (100 Tasks)")
    print("  Tutor: Llama-3.3-70B-Instruct | Student: Meta-Llama-3-8B-Instruct")
    print("=" * 80)

    # Collect all pass@k data
    all_pass_data = {}  # {level: {round: {k: value}}}
    all_timing = {}

    for level in LEVELS:
        all_pass_data[level] = {}
        for rdx in ROUNDS:
            rdir = os.path.join(POSTTEST, level, f"round_{rdx}")
            test_file = os.path.join(rdir, "test_results.jsonl")
            comp_file = os.path.join(rdir, "completion.jsonl")

            if not os.path.exists(test_file):
                continue

            result = analyze_pass_k(test_file, comp_file)
            if result:
                all_pass_data[level][rdx] = result

    # Print Pass@k table
    print("\n" + "=" * 80)
    print("  PASS@K RESULTS")
    print("=" * 80)

    for level in LEVELS:
        print(f"\n--- {level.upper()} ---")
        header = f"{'Round':<8}"
        for k in K_LIST:
            header += f"{'Pass@'+str(k):<12}"
        header += f"{'Passed':<10}{'Total':<10}{'Tasks':<8}"
        print(header)
        print("-" * len(header))

        for rdx in ROUNDS:
            if rdx not in all_pass_data[level]:
                print(f"  round_{rdx}: (no data)")
                continue
            r = all_pass_data[level][rdx]
            row = f"  R{rdx:<5}"
            for k in K_LIST:
                row += f"{r['metrics'].get(k, 0):<12.2f}"
            row += f"{r['pass_count']:<10}{r['total_entries']:<10}{r['num_tasks']:<8}"
            print(row)

    # Summary table: Pass@1 across all levels and rounds
    print("\n" + "=" * 80)
    print("  PASS@1 SUMMARY TABLE")
    print("=" * 80)
    header = f"{'Round':<8}"
    for level in LEVELS:
        header += f"{level:<15}"
    print(header)
    print("-" * len(header))
    for rdx in ROUNDS:
        row = f"  R{rdx:<5}"
        for level in LEVELS:
            if rdx in all_pass_data[level]:
                val = all_pass_data[level][rdx]['metrics'].get(1, 0)
                row += f"{val:<15.2f}"
            else:
                row += f"{'N/A':<15}"
        print(row)

    # Pass@5 summary
    print("\n" + "=" * 80)
    print("  PASS@5 SUMMARY TABLE")
    print("=" * 80)
    header = f"{'Round':<8}"
    for level in LEVELS:
        header += f"{level:<15}"
    print(header)
    print("-" * len(header))
    for rdx in ROUNDS:
        row = f"  R{rdx:<5}"
        for level in LEVELS:
            if rdx in all_pass_data[level]:
                val = all_pass_data[level][rdx]['metrics'].get(5, 0)
                row += f"{val:<15.2f}"
            else:
                row += f"{'N/A':<15}"
        print(row)

    # Pass@10 summary
    print("\n" + "=" * 80)
    print("  PASS@10 SUMMARY TABLE")
    print("=" * 80)
    header = f"{'Round':<8}"
    for level in LEVELS:
        header += f"{level:<15}"
    print(header)
    print("-" * len(header))
    for rdx in ROUNDS:
        row = f"  R{rdx:<5}"
        for level in LEVELS:
            if rdx in all_pass_data[level]:
                val = all_pass_data[level][rdx]['metrics'].get(10, 0)
                row += f"{val:<15.2f}"
            else:
                row += f"{'N/A':<15}"
        print(row)

    # Recall analysis
    print("\n" + "=" * 80)
    print("  RECALL@K ANALYSIS (dependency_results.jsonl)")
    print("=" * 80)
    for level in LEVELS:
        print(f"\n--- {level.upper()} ---")
        for rdx in ROUNDS:
            rdir = os.path.join(POSTTEST, level, f"round_{rdx}")
            dep_file = os.path.join(rdir, "dependency_results.jsonl")
            comp_file = os.path.join(rdir, "completion.jsonl")
            result = analyze_recall_k(dep_file, comp_file)
            if result:
                print(f"  R{rdx}: {result['total_entries']} entries, "
                      f"{result['num_tasks']} tasks, "
                      f"{result['tasks_with_deps']} with generated deps")

    # Dialogue analysis
    print("\n" + "=" * 80)
    print("  DIALOGUE SIMULATION STATS")
    print("=" * 80)
    dialogue_dir = os.path.join(BASE, "dialogue", "vanilla", "Llama-3.3-70B-Instruct")
    for level in LEVELS:
        dialog_file = os.path.join(dialogue_dir, level, "simulated_dialogs.jsonl")
        if os.path.exists(dialog_file):
            with open(dialog_file, 'r') as f:
                dialogs = [json.loads(l) for l in f]
            avg_rounds = np.mean([len(d.get('dialog', [])) // 2 for d in dialogs]) if dialogs else 0
            print(f"  {level}: {len(dialogs)} dialogues, avg rounds: {avg_rounds:.1f}")

    # Timing from results files
    print("\n" + "=" * 80)
    print("  TIMING DATA")
    print("=" * 80)
    for fname in ["dialogue/dialogue_results.txt",
                   "student_posttest/codegen_results.txt",
                   "student_posttest/coding_test_results.txt"]:
        fpath = os.path.join(BASE, fname)
        if os.path.exists(fpath):
            print(f"\n--- {fname} ---")
            with open(fpath, 'r') as f:
                print(f.read())

    # Completion coverage per round (how many completions were incomplete)
    print("\n" + "=" * 80)
    print("  COMPLETION COVERAGE (test_results vs total completions)")
    print("=" * 80)
    for level in LEVELS:
        print(f"\n--- {level.upper()} ---")
        for rdx in ROUNDS:
            rdir = os.path.join(POSTTEST, level, f"round_{rdx}")
            test_file = os.path.join(rdir, "test_results.jsonl")
            comp_file = os.path.join(rdir, "completion.jsonl")
            if os.path.exists(comp_file) and os.path.exists(test_file):
                with open(comp_file) as f:
                    total_comp = sum(1 for _ in f)
                with open(test_file) as f:
                    total_tested = sum(1 for _ in f)
                coverage = (total_tested / total_comp * 100) if total_comp > 0 else 0
                print(f"  R{rdx}: {total_tested}/{total_comp} tested ({coverage:.1f}%)")


if __name__ == '__main__':
    main()
