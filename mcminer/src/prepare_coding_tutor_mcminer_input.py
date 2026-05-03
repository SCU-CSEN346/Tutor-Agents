#!/usr/bin/env python3
"""Convert Coding-Tutor McMiner output into McMiner inference inputs."""

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, Iterable


def iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


def clean_student_code(code: str) -> str:
    code = code.strip()
    if code.startswith("```"):
        code = code.strip("`").strip()
    if code.startswith("Python\n"):
        code = code[len("Python\n") :]
    if code.startswith("python\n"):
        code = code[len("python\n") :]
    return code.strip()


def stable_id(namespace: str) -> int:
    digest = hashlib.sha1(namespace.encode("utf-8")).hexdigest()
    return int(digest[:8], 16)


def build_problem_description(namespace: str, prompt_record: Dict[str, Any] | None) -> str:
    if not prompt_record:
        return f"Analyze student code for Coding-Tutor task namespace: {namespace}"

    pieces = [f"Namespace: {namespace}"]
    for key in ("input_code", "instruction", "prompt", "function_name", "class_name", "type"):
        value = prompt_record.get(key)
        if value:
            pieces.append(f"{key}: {value}")
    return "\n\n".join(pieces)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare Coding-Tutor output as McMiner corrupted-code JSON files."
    )
    parser.add_argument(
        "--coding-tutor-results",
        default="Coding-Tutor/output/mcminer/misconception_results.json",
        help="Coding-Tutor misconception_results.json file.",
    )
    parser.add_argument(
        "--prompt-elements",
        default="prompt/prompt_elements.jsonl",
        help="Prompt elements JSONL used to recover task context by namespace.",
    )
    parser.add_argument(
        "--output-dir",
        default="mcminer/dataset/coding_tutor_student_codes",
        help="Directory to write McMiner input files.",
    )
    parser.add_argument(
        "--problems-file",
        default="mcminer/dataset/coding_tutor_problems_processed.json",
        help="Problems file to write for McMiner.",
    )
    parser.add_argument(
        "--max-records",
        type=int,
        default=None,
        help="Optional limit for debugging.",
    )
    args = parser.parse_args()

    results_path = Path(args.coding_tutor_results)
    prompt_path = Path(args.prompt_elements)
    output_dir = Path(args.output_dir)
    problems_path = Path(args.problems_file)

    records = json.loads(results_path.read_text(encoding="utf-8"))
    if args.max_records:
        records = records[: args.max_records]

    prompt_by_namespace = {}
    if prompt_path.exists():
        for item in iter_jsonl(prompt_path):
            namespace = item.get("namespace")
            if namespace and namespace not in prompt_by_namespace:
                prompt_by_namespace[namespace] = item

    output_dir.mkdir(parents=True, exist_ok=True)
    problems_path.parent.mkdir(parents=True, exist_ok=True)

    problems: Dict[str, Dict[str, Any]] = {}
    written = 0

    for index, record in enumerate(records):
        namespace = record.get("namespace") or "unknown"
        problem_id = stable_id(namespace)
        code = clean_student_code(record.get("student_code", ""))
        if not code:
            continue

        if str(problem_id) not in problems:
            prompt_record = prompt_by_namespace.get(namespace)
            problems[str(problem_id)] = {
                "id": problem_id,
                "title": namespace,
                "description": build_problem_description(namespace, prompt_record),
                "solutions": [],
            }

        detected = bool(record.get("misconception_detected"))
        desc = record.get("misconception_description") if detected else "NONE"
        misc_id = f"coding_tutor:{namespace}:{record.get('turn_index')}:{record.get('code_index')}"

        out = {
            "problem_id": problem_id,
            "problem_title": namespace,
            "misconception_id": misc_id if detected else "NONE",
            "misconception_description": desc,
            "coding_tutor_metadata": {
                "namespace": namespace,
                "turn_index": record.get("turn_index"),
                "code_index": record.get("code_index"),
                "source_file": record.get("source_file"),
                "previous_misconception_detected": detected,
                "previous_confidence": record.get("confidence"),
                "previous_explanation": record.get("misconception_explanation"),
            },
            "solutions": [
                {
                    "solution_index": 0,
                    "generated_code": code,
                    "reasoning": "",
                    "metadata": {
                        "source": "Coding-Tutor/output/mcminer/misconception_results.json",
                        "previous_misconception_detected": str(detected).lower(),
                        "previous_confidence": record.get("confidence") or "",
                    },
                    "raw_response": record.get("raw_response"),
                    "parse_success": True,
                }
            ],
            "source_file": (
                f"coding_tutor_{index:04d}_turn_{record.get('turn_index')}_"
                f"code_{record.get('code_index')}.json"
            ),
        }

        output_path = output_dir / out["source_file"]
        output_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
        written += 1

    problems_path.write_text(json.dumps(problems, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Wrote {written} McMiner input files to {output_dir}")
    print(f"Wrote {len(problems)} problem contexts to {problems_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
