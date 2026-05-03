#!/usr/bin/env python3
"""Convert a completion_lm JSONL file into McMiner inference inputs."""

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from typing import Any, Dict, Iterable, List


def iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


def stable_id(namespace: str) -> int:
    digest = hashlib.sha1(namespace.encode("utf-8")).hexdigest()
    return int(digest[:8], 16)


def extract_code(completion: str) -> str:
    """Prefer the first fenced Python block; otherwise use the raw completion."""
    match = re.search(r"```(?:python|Python)?\s*(.*?)```", completion, re.DOTALL)
    if match:
        return match.group(1).strip()
    return completion.strip()


def build_problem_description(namespace: str, prompt_record: Dict[str, Any] | None) -> str:
    if not prompt_record:
        return f"Analyze this generated completion for task namespace: {namespace}"

    pieces: List[str] = [f"Namespace: {namespace}"]
    for key in ("input_code", "instruction", "prompt", "function_name", "class_name", "type"):
        value = prompt_record.get(key)
        if value:
            pieces.append(f"{key}: {value}")
    return "\n\n".join(pieces)


def select_latest_completion_files(root: Path) -> List[Path]:
    """Select non-duplicate completion_lm files, keeping highest round_N per run."""
    round_re = re.compile(r"^(.*)/round_(\d+)/completion_lm[^/]*\.jsonl$")
    latest_by_group: Dict[str, tuple[int, float, Path]] = {}
    non_round: List[Path] = []

    for path in root.rglob("completion_lm*.jsonl"):
        rel = path.relative_to(root)
        rel_str = str(rel)

        if "/mcminer/dataset/" in f"/{rel_str}" or "/mcminer/results/" in f"/{rel_str}":
            continue

        # The repository contains a mirrored Coding-Tutor/Coding-Tutor tree.
        if rel_str.startswith("Coding-Tutor/Coding-Tutor/"):
            twin = root / "Coding-Tutor" / Path(rel_str).relative_to("Coding-Tutor/Coding-Tutor")
            if twin.exists():
                continue

        match = round_re.match(rel_str)
        if match:
            group = match.group(1)
            round_number = int(match.group(2))
            mtime = path.stat().st_mtime
            old = latest_by_group.get(group)
            if old is None or round_number > old[0] or (
                round_number == old[0] and mtime > old[1]
            ):
                latest_by_group[group] = (round_number, mtime, path)
        else:
            non_round.append(path)

    selected = [item[2] for item in latest_by_group.values()] + non_round
    return sorted(selected, key=lambda p: str(p))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare completion_lm JSONL completions as McMiner input files."
    )
    parser.add_argument(
        "--completion-file",
        action="append",
        default=None,
        help="Input completion_lm JSONL file.",
    )
    parser.add_argument(
        "--completion-file-list",
        default=None,
        help="Text file containing completion_lm JSONL paths, one per line.",
    )
    parser.add_argument(
        "--discover-all-latest",
        action="store_true",
        help="Find all completion_lm JSONL files and keep only the latest/highest round per run.",
    )
    parser.add_argument(
        "--prompt-elements",
        default="prompt/prompt_elements.jsonl",
        help="Prompt elements JSONL used to recover task descriptions by namespace.",
    )
    parser.add_argument(
        "--output-dir",
        default="mcminer/dataset/completion_lm_student_codes",
        help="Directory to write McMiner input JSON files.",
    )
    parser.add_argument(
        "--problems-file",
        default="mcminer/dataset/completion_lm_problems_processed.json",
        help="Problems/context JSON file to write for McMiner.",
    )
    parser.add_argument("--max-records", type=int, default=None)
    parser.add_argument("--max-completions-per-record", type=int, default=None)
    parser.add_argument(
        "--clean-output-dir",
        action="store_true",
        help="Remove existing converted input files before writing.",
    )
    args = parser.parse_args()

    if args.discover_all_latest:
        completion_paths = select_latest_completion_files(Path("."))
    else:
        raw_paths = args.completion_file or []
        if args.completion_file_list:
            list_path = Path(args.completion_file_list)
            raw_paths.extend(
                line.strip()
                for line in list_path.read_text(encoding="utf-8").splitlines()
                if line.strip() and not line.lstrip().startswith("#")
            )
        if not raw_paths:
            raw_paths = ["completion_lm (2).jsonl"]
        completion_paths = [Path(path) for path in raw_paths]

    prompt_path = Path(args.prompt_elements)
    output_dir = Path(args.output_dir)
    problems_path = Path(args.problems_file)

    prompt_by_namespace: Dict[str, Dict[str, Any]] = {}
    if prompt_path.exists():
        for item in iter_jsonl(prompt_path):
            namespace = item.get("namespace")
            if namespace and namespace not in prompt_by_namespace:
                prompt_by_namespace[namespace] = item

    if args.clean_output_dir and output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    problems_path.parent.mkdir(parents=True, exist_ok=True)

    problems: Dict[str, Dict[str, Any]] = {}
    written = 0
    skipped_empty = 0

    total_records = 0
    for file_index, completion_path in enumerate(completion_paths):
        records = list(iter_jsonl(completion_path))
        if args.max_records is not None:
            records = records[: args.max_records]

        for record_index, record in enumerate(records):
            total_records += 1
            namespace = record.get("namespace") or f"file_{file_index}_record_{record_index}"
            problem_id = stable_id(namespace)
            completions = record.get("completion") or []
            if not isinstance(completions, list):
                completions = [completions]
            if args.max_completions_per_record is not None:
                completions = completions[: args.max_completions_per_record]

            if str(problem_id) not in problems:
                prompt_record = prompt_by_namespace.get(namespace)
                problems[str(problem_id)] = {
                    "id": problem_id,
                    "title": namespace,
                    "description": build_problem_description(namespace, prompt_record),
                    "solutions": [],
                }

            for completion_index, completion in enumerate(completions):
                code = extract_code(str(completion))
                if not code:
                    skipped_empty += 1
                    continue

                filename = (
                    f"completion_lm_file_{file_index:04d}_record_{record_index:05d}_"
                    f"completion_{completion_index:03d}.json"
                )
                out = {
                    "problem_id": problem_id,
                    "problem_title": namespace,
                    "misconception_id": f"completion_lm:{namespace}:{completion_index}",
                    "misconception_description": "Generated completion from completion_lm file",
                    "completion_lm_metadata": {
                        "namespace": namespace,
                        "file_index": file_index,
                        "record_index": record_index,
                        "completion_index": completion_index,
                        "source_file": str(completion_path),
                        "raw_completion": completion,
                    },
                    "solutions": [
                        {
                            "solution_index": 0,
                            "generated_code": code,
                            "reasoning": "",
                            "metadata": {
                                "source": str(completion_path),
                                "namespace": namespace,
                                "completion_index": str(completion_index),
                            },
                            "raw_response": completion,
                            "parse_success": True,
                        }
                    ],
                    "source_file": filename,
                }
                (output_dir / filename).write_text(
                    json.dumps(out, indent=2, ensure_ascii=False),
                    encoding="utf-8",
                )
                written += 1

    problems_path.write_text(
        json.dumps(problems, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    print(f"Selected {len(completion_paths)} completion_lm files")
    print(f"Read {total_records} JSONL records")
    print(f"Wrote {written} McMiner input files to {output_dir}")
    print(f"Wrote {len(problems)} problem contexts to {problems_path}")
    if skipped_empty:
        print(f"Skipped {skipped_empty} empty completions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
