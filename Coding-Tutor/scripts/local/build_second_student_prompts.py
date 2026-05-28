import argparse
import json
import os
import subprocess
import textwrap
from collections import defaultdict


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
                return False, test, clean_failure(proc.stdout)
    except subprocess.TimeoutExpired as exc:
        return False, "timeout", clean_failure(exc.stdout or "")
    finally:
        teardown_completion(source_code_root, data)
    return True, "", ""


def clean_failure(text):
    lines = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            continue
        if len(line) > 220:
            line = line[:220] + " ..."
        lines.append(line)
    return "\n".join(lines[-24:])


def compact_code(code, limit=900):
    code = textwrap.dedent(code).strip()
    if len(code) <= limit:
        return code
    return code[:limit] + "\n# ... truncated ..."


def build_prompt(namespace, base_prompt, metadata, reports, level):
    tests = "\n".join(f"- {test}" for test in metadata.get("tests", [])[:6])
    candidate_blocks = []
    for idx, report in enumerate(reports, 1):
        candidate_blocks.append(
            f"""Attempt {idx} failed at `{report['test']}`:
```python
{compact_code(report['completion'])}
```
Error summary:
```text
{report['failure']}
```"""
        )

    previous = "\n\n".join(candidate_blocks)
    style = "very concrete and implementation-focused" if level == "low_level" else "concise and code-focused"
    return f"""{base_prompt}

Additional second-student context:

You are another student with the same model ability as the first student. You do not get a stronger model and you do not get the reference solution. You only get task metadata and mistakes from previous attempts.

Metadata card:
- Namespace: {namespace}
- Target file: {metadata.get('completion_path')}
- Body line span: {metadata.get('body_position')}
- Function body indent: {metadata.get('indent')}
- Evaluation tests:
{tests}

Previous student attempts failed. Use these failures only to avoid repeating the same mistakes. Do not copy a failed attempt blindly.

{previous}

Instruction style for this {level} student: {style}.

Now write a correct completion for the target function. Return only Python code for the function body. Do not include explanations, markdown fences, or the full function definition.
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--completion_file", required=True)
    parser.add_argument("--test_results_file", required=True)
    parser.add_argument("--prompt_file", required=True)
    parser.add_argument("--metadata_file", required=True)
    parser.add_argument("--source_code_root", required=True)
    parser.add_argument("--output_file", required=True)
    parser.add_argument("--level", required=True)
    parser.add_argument("--max_failed_candidates", type=int, default=5)
    args = parser.parse_args()

    metadata = {d["namespace"]: d for d in load_jsonl(args.metadata_file)}
    prompts = {d["namespace"]: d["prompt"] for d in load_jsonl(args.prompt_file)}
    completions = defaultdict(list)
    for row in load_jsonl(args.completion_file):
        completions[row["namespace"]].append(row)

    passed = defaultdict(set)
    for row in load_jsonl(args.test_results_file):
        if row.get("Result") == "Pass":
            passed[row["namespace"]].add(row["completion"])

    os.makedirs(os.path.dirname(args.output_file), exist_ok=True)
    written = 0
    with open(args.output_file, "w", encoding="utf-8") as out:
        for namespace in sorted(prompts):
            if namespace not in metadata:
                continue
            reports = []
            for candidate in completions.get(namespace, []):
                if candidate["completion"] in passed[namespace]:
                    continue
                ok, test_name, failure = run_tests_capture(
                    args.source_code_root,
                    metadata[namespace],
                    candidate["completion"],
                )
                if ok:
                    continue
                reports.append(
                    {
                        "completion": candidate["completion"],
                        "test": test_name,
                        "failure": failure,
                    }
                )
                if len(reports) >= args.max_failed_candidates:
                    break

            prompt = build_prompt(
                namespace,
                prompts[namespace],
                metadata[namespace],
                reports,
                args.level,
            )
            out.write(json.dumps({"namespace": namespace, "prompt": prompt}) + "\n")
            written += 1
            print(f"built prompt {written}: {namespace} with {len(reports)} failed attempts")

    print(f"wrote {written} prompts to {args.output_file}")


if __name__ == "__main__":
    main()
