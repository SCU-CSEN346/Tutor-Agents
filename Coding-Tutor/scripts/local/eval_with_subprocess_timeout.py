import argparse
import json
import os
import shutil
import subprocess
import textwrap
from collections import Counter, defaultdict

import numpy as np


def load_jsonl(path):
    with open(path) as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def adjust_indent(code, new_indent):
    return textwrap.indent(textwrap.dedent(code), " " * new_indent)


def compute_pass_at_k(n, c, k):
    if n - c < k:
        return 1.0
    return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))


def setup_completion(source_root, item, completion):
    completion_path = os.path.join(source_root, item["completion_path"])
    tmp_path = completion_path + ".eval_tmp"
    shutil.copy2(completion_path, tmp_path)
    sos, eos = item["body_position"][0] - 1, item["body_position"][1]
    with open(completion_path) as f:
        lines = f.readlines()
    lines = lines[:sos] + ["\n", completion, "\n"] + lines[eos:]
    with open(completion_path, "w") as f:
        f.write("".join(lines))
    return completion_path, tmp_path


def teardown(completion_path, tmp_path):
    if os.path.exists(tmp_path):
        shutil.move(tmp_path, completion_path)


def run_tests(source_root, item, timeout):
    project = item["completion_path"].split("/")[0]
    project_path = os.path.join(source_root, project)
    for test in item.get("tests", []):
        try:
            result = subprocess.run(
                ["pytest", "-q", test],
                cwd=project_path,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return "Fail", f"Timeout after {timeout}s: {test}"
        if result.returncode != 0:
            return "Fail", (result.stdout + "\n" + result.stderr)[-4000:]
    return "Pass", ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_file", required=True)
    parser.add_argument("--log_file", required=True)
    parser.add_argument("--data_file", required=True)
    parser.add_argument("--source_code_root", required=True)
    parser.add_argument("--k", default="1,3")
    parser.add_argument("--n", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=25)
    args = parser.parse_args()

    metadata = {item["namespace"]: item for item in load_jsonl(args.data_file)}
    finished = defaultdict(set)
    if os.path.exists(args.log_file):
        for item in load_jsonl(args.log_file):
            finished[item["namespace"]].add(item["completion"])

    todo = []
    for item in load_jsonl(args.output_file):
        if item["namespace"] not in metadata:
            continue
        if item["completion"] in finished[item["namespace"]]:
            continue
        finished[item["namespace"]].add(item["completion"])
        todo.append(item)

    print("TODO Completions:", len(todo))
    os.makedirs(os.path.dirname(args.log_file), exist_ok=True)
    with open(args.log_file, "a") as out:
        for idx, completion_item in enumerate(todo, 1):
            ns = completion_item["namespace"]
            meta = metadata[ns]
            completion = adjust_indent(completion_item["completion"], meta["indent"])
            completion_path, tmp_path = setup_completion(args.source_code_root, meta, completion)
            try:
                result, error = run_tests(args.source_code_root, meta, args.timeout)
            finally:
                teardown(completion_path, tmp_path)
            record = dict(completion_item)
            record["Result"] = result
            if error:
                record["Error"] = error
            out.write(json.dumps(record) + "\n")
            out.flush()
            print(f"{idx}/{len(todo)} {ns}: {result}")

    passed = defaultdict(set)
    all_counts = Counter()
    for item in load_jsonl(args.output_file):
        if item["namespace"] in metadata:
            all_counts[item["namespace"]] += 1
    for item in load_jsonl(args.log_file):
        if item.get("Result") == "Pass":
            passed[item["namespace"]].add(item["completion"])

    print("\nEvaluation Summary:")
    solved = 0
    for ns in sorted(all_counts):
        c = len(passed[ns])
        solved += c > 0
        print(f"{ns}: {c}/{all_counts[ns]} pass")
    print(f"Tasks with >=1 pass: {solved}/{len(all_counts)}")
    for k in [int(x) for x in args.k.split(",")]:
        if k <= args.n:
            vals = [compute_pass_at_k(args.n, len(passed[ns]), k) for ns in all_counts]
            print(f"Pass@{k}: {np.mean(vals) * 100}%")


if __name__ == "__main__":
    main()
