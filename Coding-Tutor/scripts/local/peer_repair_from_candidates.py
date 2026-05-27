import argparse
import json
import os
import subprocess
import textwrap
from collections import defaultdict

from openai import OpenAI


def load_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def adjust_indent(code, new_indent):
    dedented_code = textwrap.dedent(code).strip("\n")
    return textwrap.indent(dedented_code, " " * new_indent) + "\n"


def setup_completion(source_code_root, data, completion):
    completion_path = os.path.join(source_code_root, data["completion_path"])
    head, tail = os.path.split(completion_path)
    tmp_path = os.path.join(head, "tmp_" + tail)
    subprocess.run(["cp", completion_path, tmp_path], check=True)

    sos, eos = data["body_position"][0] - 1, data["body_position"][1]
    with open(completion_path, encoding="utf-8") as f:
        file_lines = f.readlines()
    file_lines = file_lines[:sos] + ["\n", completion, "\n"] + file_lines[eos:]
    with open(completion_path, "w", encoding="utf-8") as f:
        f.write("".join(file_lines))


def teardown_completion(source_code_root, data):
    completion_path = os.path.join(source_code_root, data["completion_path"])
    head, tail = os.path.split(completion_path)
    tmp_path = os.path.join(head, "tmp_" + tail)
    if os.path.exists(tmp_path):
        subprocess.run(["mv", tmp_path, completion_path], check=True)


def run_tests_capture(source_code_root, data, completion, timeout=30):
    project_name = data["completion_path"].split("/")[0]
    project_path = os.path.join(source_code_root, project_name)
    runner = "/WAVE/projects/CSEN-346-Sp26/Group2/hhedayati_runs/scaffold_eval_20260523/run_pytest_sanitized.py"
    body = adjust_indent(completion, data["indent"])
    setup_completion(source_code_root, data, body)
    try:
        for test in data["tests"]:
            proc = subprocess.run(
                ["python", runner, test],
                cwd=project_path,
                env={**os.environ, "PYTHONPATH": project_path},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout,
            )
            if proc.returncode != 0:
                return False, test, proc.stdout[-2500:]
    except subprocess.TimeoutExpired as exc:
        return False, "timeout", (exc.stdout or "")[-2500:]
    finally:
        teardown_completion(source_code_root, data)
    return True, "", ""


def extract_body(text):
    cleaned = text.strip()
    if "```" in cleaned:
        parts = cleaned.split("```")
        cleaned = parts[1] if len(parts) > 1 else cleaned
        if cleaned.lstrip().startswith("python"):
            cleaned = cleaned.lstrip()[len("python"):].lstrip("\n")

    lines = cleaned.strip("\n").splitlines()
    for i, line in enumerate(lines):
        if line.lstrip().startswith("def "):
            body = lines[i + 1 :]
            return textwrap.dedent("\n".join(body)).strip("\n") + "\n"
    return textwrap.dedent(cleaned).strip("\n") + "\n"


def build_prompt(namespace, posttest_prompt, candidate_reports):
    blocks = []
    for i, report in enumerate(candidate_reports, 1):
        blocks.append(
            f"""Candidate {i}:
```python
{report['completion']}
```
Failed test: {report['test']}
Error:
```text
{report['failure']}
```"""
        )

    candidates = "\n\n".join(blocks)
    return f"""You are a student with the same model ability as the previous student.

The previous student generated several candidate function bodies for the same task. They failed tests, but some may be close.

Your job:
1. Compare the candidates and their errors.
2. Choose the candidate that is closest to correct.
3. Make the smallest edit needed to fix it.

Do not write a new solution from scratch unless all candidates are unusable.
Return ONLY the corrected function body. Do not include markdown fences, explanation, or a full function definition.

Task namespace:
{namespace}

Original task prompt:
{posttest_prompt[-4500:]}

Previous failed candidates:
{candidates[-9000:]}

Corrected function body only:
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--completion_file", required=True)
    parser.add_argument("--test_results_file", required=True)
    parser.add_argument("--prompt_file", required=True)
    parser.add_argument("--metadata_file", required=True)
    parser.add_argument("--source_code_root", required=True)
    parser.add_argument("--output_file", required=True)
    parser.add_argument("--model", default="meta-llama/Llama-3.1-8B-Instruct")
    parser.add_argument("--api_base", default="https://router.huggingface.co/v1")
    parser.add_argument("--api_key", default=os.environ.get("HF_TOKEN", ""))
    parser.add_argument("--max_tasks", type=int, default=12)
    parser.add_argument("--candidates_per_namespace", type=int, default=10)
    parser.add_argument("--repairs_per_namespace", type=int, default=3)
    parser.add_argument("--zero_pass_only", action="store_true")
    args = parser.parse_args()

    metadata = {d["namespace"]: d for d in load_jsonl(args.metadata_file)}
    prompts = {d["namespace"]: d["prompt"] for d in load_jsonl(args.prompt_file)}
    completions = defaultdict(list)
    for d in load_jsonl(args.completion_file):
        completions[d["namespace"]].append(d)

    passed = defaultdict(set)
    if os.path.exists(args.test_results_file):
        for d in load_jsonl(args.test_results_file):
            if d.get("Result") == "Pass":
                passed[d["namespace"]].add(d["completion"])

    client = OpenAI(api_key=args.api_key, base_url=args.api_base)
    os.makedirs(os.path.dirname(args.output_file), exist_ok=True)

    repaired = []
    tasks_seen = 0
    for namespace in sorted(prompts):
        if tasks_seen >= args.max_tasks:
            break
        if namespace not in metadata:
            continue
        if args.zero_pass_only and passed[namespace]:
            continue

        failing = [
            c for c in completions.get(namespace, [])
            if c["completion"] not in passed[namespace]
        ][: args.candidates_per_namespace]
        if not failing:
            continue

        reports = []
        for candidate in failing:
            ok, test_name, failure = run_tests_capture(
                args.source_code_root,
                metadata[namespace],
                candidate["completion"],
            )
            if not ok:
                reports.append(
                    {
                        "idx": candidate.get("idx"),
                        "completion": candidate["completion"],
                        "test": test_name,
                        "failure": failure,
                    }
                )

        if not reports:
            continue

        tasks_seen += 1
        prompt = build_prompt(namespace, prompts[namespace], reports)
        for attempt in range(args.repairs_per_namespace):
            response = client.chat.completions.create(
                model=args.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.35,
                top_p=0.95,
                max_tokens=1024,
            )
            body = extract_body(response.choices[0].message.content)
            repaired.append(
                {
                    "namespace": namespace,
                    "completion": body,
                    "idx": attempt,
                    "peer_attempt": attempt,
                    "source_candidates": [r["idx"] for r in reports],
                }
            )
            print(f"peer repaired {len(repaired)}: {namespace} attempt={attempt}")
            with open(args.output_file, "w", encoding="utf-8") as f:
                for row in repaired:
                    f.write(json.dumps(row) + "\n")

    print(f"wrote {len(repaired)} repairs to {args.output_file}")


if __name__ == "__main__":
    main()
