"""
Compare paper's original results with our results per project.
Uses HPC results (from Llama-3.1-70B-Instruct.zip) which contain the complete evaluation.
"""
import json
import os
import numpy as np
from collections import defaultdict

REPO_DIR = "/Users/catherine/PycharmProjects/Coding-Tutor"

def compute_pass_at_k(n, c, k):
    if n - c < k:
        return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))

def load_metadata(metadata_file):
    """Load metadata: namespace -> project mapping."""
    ns_to_project = {}
    with open(metadata_file) as f:
        for line in f:
            js = json.loads(line)
            ns = js['namespace']
            project = js['completion_path'].split('/')[0]
            ns_to_project[ns] = project
    return ns_to_project

def analyze_level(test_file, comp_file, dep_file, ns_to_project, n=10):
    """Analyze a single level's results. Returns per-project data."""
    if not os.path.exists(test_file) or not os.path.exists(comp_file):
        return None
    
    # Count passes per namespace
    passed = defaultdict(set)
    with open(test_file) as f:
        for line in f:
            js = json.loads(line)
            if js.get('Result') == 'Pass':
                passed[js['namespace']].add(js['completion'])
    
    # Count completions per namespace
    ns_comp_count = defaultdict(int)
    with open(comp_file) as f:
        for line in f:
            js = json.loads(line)
            ns_comp_count[js['namespace']] += 1
    
    # Load recalls
    ns_recalls = defaultdict(list)
    if dep_file and os.path.exists(dep_file):
        with open(dep_file) as f:
            for line in f:
                js = json.loads(line)
                ns_recalls[js['namespace']].append(js.get('recall', 0.0))
    
    # Group by project
    project_data = defaultdict(lambda: {'passes': {}, 'recalls': {}})
    for ns in ns_comp_count:
        proj = ns_to_project.get(ns, 'unknown')
        pass_count = len(passed.get(ns, set()))
        project_data[proj]['passes'][ns] = pass_count
        if ns in ns_recalls:
            project_data[proj]['recalls'][ns] = ns_recalls[ns]
    
    return project_data

def print_project_table(project_data, n=10, k_list=[1,3,5,10]):
    """Print a formatted table of per-project results."""
    print(f"  {'Project':<35} {'Tasks':>5}  {'Pass@1':>8}  {'Pass@3':>8}  {'Pass@5':>8}  {'Pass@10':>8}")
    print(f"  {'─'*35} {'─'*5}  {'─'*8}  {'─'*8}  {'─'*8}  {'─'*8}")
    
    all_pass_counts = []
    
    for proj in sorted(project_data.keys()):
        ns_passes = project_data[proj]['passes']
        task_count = len(ns_passes)
        
        pass_metrics = {}
        for k in k_list:
            if k > n:
                continue
            pak = np.mean([compute_pass_at_k(n, c, k) for c in ns_passes.values()])
            pass_metrics[k] = pak * 100
        
        passed_tasks = sum(1 for c in ns_passes.values() if c > 0)
        marker = "✓" if passed_tasks > 0 else " "
        
        print(f"  {marker} {proj:<33} {task_count:>5}  {pass_metrics.get(1,0):>7.1f}%  {pass_metrics.get(3,0):>7.1f}%  {pass_metrics.get(5,0):>7.1f}%  {pass_metrics.get(10,0):>7.1f}%")
        
        all_pass_counts.extend(ns_passes.values())
    
    if all_pass_counts:
        print(f"  {'─'*36} {'─'*5}  {'─'*8}  {'─'*8}  {'─'*8}  {'─'*8}")
        overall = {}
        for k in k_list:
            overall[k] = np.mean([compute_pass_at_k(n, c, k) for c in all_pass_counts]) * 100
        print(f"  {'OVERALL':<36} {len(all_pass_counts):>5}  {overall.get(1,0):>7.1f}%  {overall.get(3,0):>7.1f}%  {overall.get(5,0):>7.1f}%  {overall.get(10,0):>7.1f}%")
        return overall, len(all_pass_counts)
    return {}, 0


def main():
    # Use FULL metadata for namespace -> project mapping
    metadata_file = f"{REPO_DIR}/benchmark/EvoCodeBench-2403/metadata.jsonl"
    ns_to_project = load_metadata(metadata_file)
    
    # Filtered metadata to identify our 10 projects
    filtered_file = f"{REPO_DIR}/benchmark/EvoCodeBench-2403/metadata_filtered.jsonl"
    ns_to_proj_filtered = load_metadata(filtered_file)
    our_projects = set(ns_to_proj_filtered.values())
    
    levels = ['low_level', 'med_level', 'high_level']
    n = 10
    k_list = [1, 3, 5, 10]
    
    # Paths
    paper_base = f"{REPO_DIR}/output/paper_results/student_posttest/traver/Meta-Llama-3.1-70B-Instruct"
    hpc_base = f"{REPO_DIR}/output/hpc_results"  # extracted from Llama-3.1-70B-Instruct.zip
    
    # =========================================================================
    # PAPER RESULTS — OUR 10 PROJECTS ONLY
    # =========================================================================
    print("=" * 95)
    print("  PAPER ORIGINAL — OUR 10 PROJECTS ONLY (traver / Meta-Llama-3.1-70B-Instruct)")
    print("=" * 95)
    
    paper_overalls = {}
    for level in levels:
        test_f = f"{paper_base}/{level}/test_results.jsonl"
        comp_f = f"{paper_base}/{level}/completion.jsonl"
        dep_f = f"{paper_base}/{level}/dependency_results.jsonl"
        
        data = analyze_level(test_f, comp_f, dep_f, ns_to_project, n)
        if not data:
            continue
        
        # Filter to our 10 projects only
        filtered = {p: v for p, v in data.items() if p in our_projects}
        
        print(f"\n  ── {level.upper()} {'─' * 70}")
        overall, count = print_project_table(filtered, n, k_list)
        paper_overalls[level] = overall
    
    # =========================================================================
    # OUR RESULTS (HPC) — ALL ROUNDS
    # =========================================================================
    print(f"\n\n{'=' * 95}")
    print("  OUR RESULTS (HPC) — PER ROUND (traver / Llama-3.1-70B-Instruct)")
    print("=" * 95)
    
    our_overalls = {}
    for level in levels:
        print(f"\n  ── {level.upper()} {'─' * 70}")
        
        for rdx in range(1, 9):
            test_f = f"{hpc_base}/{level}/round_{rdx}/test_results.jsonl"
            comp_f = f"{hpc_base}/{level}/round_{rdx}/completion.jsonl"
            dep_f = f"{hpc_base}/{level}/round_{rdx}/dependency_results.jsonl"
            
            data = analyze_level(test_f, comp_f, dep_f, ns_to_project, n)
            if not data:
                continue
            
            # Compute per-project metrics for this round
            all_pass_counts = []
            passed_projects = []
            for proj in sorted(data.keys()):
                ns_passes = data[proj]['passes']
                for ns, c in ns_passes.items():
                    all_pass_counts.append(c)
                    if c > 0:
                        passed_projects.append(proj)
            
            if not all_pass_counts:
                continue
            
            metrics = {}
            for k in k_list:
                metrics[k] = np.mean([compute_pass_at_k(n, c, k) for c in all_pass_counts]) * 100
            
            passed_set = set(passed_projects)
            passed_str = ", ".join(sorted(passed_set)) if passed_set else "none"
            
            print(f"    round_{rdx}: P@1={metrics[1]:>5.1f}% | P@3={metrics[3]:>5.1f}% | P@5={metrics[5]:>5.1f}% | P@10={metrics[10]:>5.1f}%  ({len(all_pass_counts)} tasks, passed: {passed_str})")
            
            if rdx == 1:
                our_overalls[level] = metrics
    
    # =========================================================================
    # OUR RESULTS (HPC) — ROUND 1 DETAIL
    # =========================================================================
    print(f"\n\n{'=' * 95}")
    print("  OUR RESULTS (HPC) — ROUND 1 DETAIL")
    print("=" * 95)
    
    for level in levels:
        test_f = f"{hpc_base}/{level}/round_1/test_results.jsonl"
        comp_f = f"{hpc_base}/{level}/round_1/completion.jsonl"
        dep_f = f"{hpc_base}/{level}/round_1/dependency_results.jsonl"
        
        data = analyze_level(test_f, comp_f, dep_f, ns_to_project, n)
        if not data:
            continue
        
        print(f"\n  ── {level.upper()} {'─' * 70}")
        print_project_table(data, n, k_list)
    
    # =========================================================================
    # SIDE-BY-SIDE SUMMARY
    # =========================================================================
    print(f"\n\n{'=' * 95}")
    print("  SIDE-BY-SIDE SUMMARY (Pass@1)")
    print("=" * 95)
    print(f"  {'Level':<15} {'Paper':>10} {'Ours (R1)':>12} {'Delta':>10}")
    print(f"  {'─'*15} {'─'*10} {'─'*12} {'─'*10}")
    for level in levels:
        paper_p1 = paper_overalls.get(level, {}).get(1, 0)
        our_p1 = our_overalls.get(level, {}).get(1, 0)
        delta = our_p1 - paper_p1
        print(f"  {level:<15} {paper_p1:>9.1f}% {our_p1:>11.1f}% {delta:>+9.1f}%")


if __name__ == '__main__':
    main()
