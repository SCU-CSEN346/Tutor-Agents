#!/usr/bin/env python3
"""Export CSV tables and Markdown report for the 60-file completion_lm run."""

import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RESULT_DIR = ROOT / "results" / "mcminer_60_completion_lm_mistral"
TABLE_DIR = ROOT / "results" / "mcminer_60_completion_lm_tables"
INPUT_LIST = ROOT / "selected_completion_lm_60_paths.txt"
DATASET_DIR = ROOT / "dataset" / "mcminer_60_completion_lm_student_codes"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def first_misc(prediction: dict[str, Any]) -> tuple[str, str]:
    items = prediction.get("predicted_misconceptions") or []
    if not items:
        return "NONE", ""
    first = items[0]
    return first.get("description", ""), first.get("explanation", "")


def source_category(source_path: str) -> str:
    if "easyvolcap/" in source_path:
        return "easyvolcap"
    if "codeformer_model/" in source_path:
        return "codeformer_model"
    if "gfpgan_model/" in source_path:
        return "gfpgan_model"
    if "searcharray/" in source_path:
        return "searcharray"
    if "xinhua/" in source_path:
        return "xinhua"
    return "unknown"


def count_records(path: Path) -> int:
    return sum(1 for line in path.open(encoding="utf-8") if line.strip())


def load_dataset_metadata() -> dict[str, dict[str, Any]]:
    metadata = {}
    for path in DATASET_DIR.glob("*.json"):
        item = load_json(path)
        metadata[path.name] = {
            "problem_title": item.get("problem_title", ""),
            "generated_code": (item.get("solutions") or [{}])[0].get("generated_code", ""),
            **(item.get("completion_lm_metadata") or {}),
        }
    return metadata


def write_input_files_table() -> list[dict[str, Any]]:
    rows = []
    for raw_path in INPUT_LIST.read_text(encoding="utf-8").splitlines():
        if not raw_path.strip():
            continue
        path = ROOT.parent / raw_path
        rows.append(
            {
                "source_group": source_category(raw_path),
                "completion_lm_file": raw_path,
                "jsonl_records": count_records(path),
                "completion_samples_estimate": count_records(path) * 10,
            }
        )

    with (TABLE_DIR / "input_files_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_summary_table(summary: dict[str, Any]) -> None:
    stats = summary["statistics"]
    row = {
        "run": "McMiner-S 60 completion_lm files",
        "model": summary.get("llm_model", ""),
        "template": summary.get("template_type", ""),
        "processing_mode": summary.get("processing_mode", ""),
        "reasoning_enabled": summary.get("reasoning_enabled", ""),
        "codes_analyzed": stats.get("total_codes_in_file", ""),
        "successful_parses": stats.get("successful_parses", ""),
        "parse_success_rate": stats.get("parse_success_rate", ""),
        "misconceptions_found": stats.get("total_misconceptions_found", ""),
        "avg_misconceptions_per_code": stats.get("average_misconceptions_per_code", ""),
        "codes_with_no_misconceptions": stats.get("codes_with_no_misconceptions", ""),
    }
    with (TABLE_DIR / "summary_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)


def write_predictions_table(
    predictions: list[dict[str, Any]],
    dataset_metadata: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    rows = []
    for prediction in predictions:
        desc, explanation = first_misc(prediction)
        gt_id = (prediction.get("ground_truth_misconception") or {}).get("id", "")
        meta = dataset_metadata.get(prediction.get("source_file", ""), {})
        rows.append(
            {
                "prediction_id": prediction.get("prediction_id", ""),
                "source_file": prediction.get("source_file", ""),
                "source_completion_lm_file": meta.get("source_file", ""),
                "source_group": source_category(meta.get("source_file", "")),
                "namespace": meta.get("namespace", ""),
                "file_index": meta.get("file_index", ""),
                "record_index": meta.get("record_index", ""),
                "completion_index": meta.get("completion_index", ""),
                "problem_id": prediction.get("problem_id", ""),
                "problem_title": meta.get("problem_title", ""),
                "solution_index": prediction.get("solution_index", ""),
                "ground_truth_id": gt_id,
                "parse_success": prediction.get("parse_success", ""),
                "no_predicted_misconceptions": prediction.get("no_predicted_misconceptions", ""),
                "predicted_description": desc,
                "predicted_explanation": explanation,
            }
        )

    with (TABLE_DIR / "predictions_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_detailed_predictions_table(rows: list[dict[str, Any]], dataset_metadata: dict[str, dict[str, Any]]) -> None:
    detailed_rows = []
    for row in rows:
        meta = dataset_metadata.get(row["source_file"], {})
        detailed_rows.append(
            {
                **row,
                "generated_code": meta.get("generated_code", ""),
                "raw_completion": meta.get("raw_completion", ""),
            }
        )

    with (TABLE_DIR / "detailed_predictions_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(detailed_rows[0]))
        writer.writeheader()
        writer.writerows(detailed_rows)


def write_top_misconceptions_table(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counter = Counter(row["predicted_description"] for row in rows if row["predicted_description"] != "NONE")
    top_rows = [
        {"rank": i, "count": count, "predicted_description": description}
        for i, (description, count) in enumerate(counter.most_common(50), start=1)
    ]
    with (TABLE_DIR / "top_misconceptions_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(top_rows[0]))
        writer.writeheader()
        writer.writerows(top_rows)
    return top_rows


def write_problem_summary_table(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row["namespace"], []).append(row)

    out_rows = []
    for namespace, items in sorted(grouped.items()):
        parses = sum(str(item["parse_success"]) == "True" for item in items)
        no_misc = sum(str(item["no_predicted_misconceptions"]) == "True" for item in items)
        sources = sorted(set(item["source_completion_lm_file"] for item in items))
        out_rows.append(
            {
                "namespace": namespace,
                "source_group": items[0]["source_group"],
                "code_samples": len(items),
                "successful_parses": parses,
                "parse_success_rate": parses / len(items),
                "no_misconception_predictions": no_misc,
                "completion_lm_files": len(sources),
            }
        )

    with (TABLE_DIR / "problem_summary_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(out_rows[0]))
        writer.writeheader()
        writer.writerows(out_rows)
    return out_rows


def write_review_tables(rows: list[dict[str, Any]]) -> None:
    no_misc_rows = [row for row in rows if str(row["no_predicted_misconceptions"]) == "True"]
    failed_rows = [row for row in rows if str(row["parse_success"]) != "True"]
    fields = [
        "prediction_id",
        "source_completion_lm_file",
        "namespace",
        "completion_index",
        "parse_success",
        "no_predicted_misconceptions",
        "predicted_description",
    ]
    for filename, selected in [
        ("no_misconception_predictions_table.csv", no_misc_rows),
        ("parse_failures_table.csv", failed_rows),
    ]:
        with (TABLE_DIR / filename).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows({key: row[key] for key in fields} for row in selected)


def write_group_summary_table(input_rows: list[dict[str, Any]], predictions: list[dict[str, Any]]) -> None:
    file_counter = Counter(row["source_group"] for row in input_rows)
    record_counter = Counter()
    for row in input_rows:
        record_counter[row["source_group"]] += int(row["jsonl_records"])

    pred_counter = Counter()
    parse_counter = Counter()
    none_counter = Counter()
    for prediction in predictions:
        gt_id = (prediction.get("ground_truth_misconception") or {}).get("id", "")
        group = gt_id.split(":", 1)[1].split(".", 1)[0] if ":" in gt_id else "unknown"
        pred_counter[group] += 1
        if prediction.get("parse_success"):
            parse_counter[group] += 1
        if prediction.get("no_predicted_misconceptions"):
            none_counter[group] += 1

    groups = sorted(set(file_counter) | set(pred_counter))
    rows = []
    for group in groups:
        total = pred_counter[group]
        rows.append(
            {
                "source_group": group,
                "completion_lm_files": file_counter[group],
                "jsonl_records": record_counter[group],
                "code_samples": total,
                "successful_parses": parse_counter[group],
                "parse_success_rate": (parse_counter[group] / total) if total else "",
                "no_misconception_predictions": none_counter[group],
            }
        )

    with (TABLE_DIR / "group_summary_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_markdown_report(
    summary: dict[str, Any],
    input_rows: list[dict[str, Any]],
    prediction_rows: list[dict[str, Any]],
    top_rows: list[dict[str, Any]],
    problem_rows: list[dict[str, Any]],
) -> None:
    stats = summary["statistics"]
    group_counts = Counter(row["source_group"] for row in input_rows)
    record_counts = Counter()
    for row in input_rows:
        record_counts[row["source_group"]] += int(row["jsonl_records"])

    group_lines = "\n".join(
        f"| {group} | {group_counts[group]} | {record_counts[group]} | {record_counts[group] * 10} |"
        for group in sorted(group_counts)
    )
    top_lines = "\n".join(
        f"| {row['rank']} | {row['count']} | {row['predicted_description']} |"
        for row in top_rows[:15]
    )
    problem_lines = "\n".join(
        f"| {row['namespace']} | {row['source_group']} | {row['code_samples']} | {row['successful_parses']} | {row['no_misconception_predictions']} |"
        for row in sorted(problem_rows, key=lambda item: (-item["code_samples"], item["namespace"]))[:25]
    )
    sample_lines = "\n".join(
        f"| {row['source_group']} | {row['namespace']} | {row['completion_index']} | {row['predicted_description']} |"
        for row in prediction_rows[:12]
    )
    no_misc_count = sum(str(row["no_predicted_misconceptions"]) == "True" for row in prediction_rows)
    failed_count = sum(str(row["parse_success"]) != "True" for row in prediction_rows)

    report = f"""# McMiner 60 Completion LM Results

This report summarizes the McMiner run using all 60 `completion_lm.jsonl` files found under `mcminer/` plus `Coding-Tutor/output/student_posttest/easyvolcap`.

## Inputs

| Source group | Files | JSONL records | Code samples |
| --- | ---: | ---: | ---: |
{group_lines}

Total files: **{len(input_rows)}**

Total JSONL records: **{sum(int(row["jsonl_records"]) for row in input_rows)}**

Total converted code samples: **{stats["total_codes_in_file"]}**

Problem contexts: **22**

## Run Settings

| Setting | Value |
| --- | --- |
| Tool | McMiner-S |
| LLM provider | `{summary["llm_provider"]}` |
| Model | `{summary["llm_model"]}` |
| Template | `{summary["template_type"]}` |
| Reasoning enabled | `{summary["reasoning_enabled"]}` |
| Processing mode | `{summary["processing_mode"]}` |
| Input directory | `{summary["input_directory"]}` |
| Output directory | `{summary["output_directory"]}` |

## Summary Metrics

| Metric | Value |
| --- | ---: |
| Codes analyzed | {stats["total_codes_in_file"]} |
| Successful parses | {stats["successful_parses"]} |
| Parse success rate | {stats["parse_success_rate"]:.4%} |
| Total misconceptions found | {stats["total_misconceptions_found"]} |
| Average misconceptions per code | {stats["average_misconceptions_per_code"]:.4f} |
| Codes with no misconceptions | {stats["codes_with_no_misconceptions"]} |
| NONE substitutions | {stats["none_substitutions"]} |

## Breakdown By Namespace

This table shows the largest namespaces by number of analyzed completions. The full version is in `problem_summary_table.csv`.

| Namespace | Source group | Code samples | Successful parses | No-misconception predictions |
| --- | --- | ---: | ---: | ---: |
{problem_lines}

## Most Repeated Predicted Misconceptions

This table lists repeated exact descriptions. Repetition does not mean the misconception is correct; it only shows what Mistral produced most often. The full top-50 table is in `top_misconceptions_table.csv`.

| Rank | Count | Predicted misconception |
| ---: | ---: | --- |
{top_lines}

## Sample Predictions

These are the first 12 predictions from the detailed table. Use `detailed_predictions_table.csv` for source paths, generated code, and raw completions.

| Source group | Namespace | Completion index | Predicted misconception |
| --- | --- | ---: | --- |
{sample_lines}

## Review/Quality Flags

| Flag | Count | Table |
| --- | ---: | --- |
| Parse failures | {failed_count} | `parse_failures_table.csv` |
| No-misconception predictions | {no_misc_count} | `no_misconception_predictions_table.csv` |

## Generated Tables

- `summary_table.csv`
- `group_summary_table.csv`
- `input_files_table.csv`
- `predictions_table.csv`
- `detailed_predictions_table.csv`
- `problem_summary_table.csv`
- `top_misconceptions_table.csv`
- `parse_failures_table.csv`
- `no_misconception_predictions_table.csv`

## Raw Results

- `../mcminer_60_completion_lm_mistral/summary.json`
- `../mcminer_60_completion_lm_mistral/predictions.json`

## Notes

- This is a local WAVE baseline using Mistral, not the best McMiner paper-style model setting.
- Reasoning was disabled because the run used local Mistral via vLLM.
- The predictions are model outputs, not verified ground truth. The high misconception rate should be manually reviewed before making research claims.
- Previous result folders were not overwritten; this run writes to `mcminer/results/mcminer_60_completion_lm_mistral`.
"""
    (TABLE_DIR / "results_report.md").write_text(report, encoding="utf-8")


def main() -> int:
    TABLE_DIR.mkdir(parents=True, exist_ok=True)
    summary = load_json(RESULT_DIR / "summary.json")
    predictions = load_json(RESULT_DIR / "predictions.json")
    dataset_metadata = load_dataset_metadata()

    input_rows = write_input_files_table()
    write_summary_table(summary)
    prediction_rows = write_predictions_table(predictions, dataset_metadata)
    write_detailed_predictions_table(prediction_rows, dataset_metadata)
    top_rows = write_top_misconceptions_table(prediction_rows)
    problem_rows = write_problem_summary_table(prediction_rows)
    write_review_tables(prediction_rows)
    write_group_summary_table(input_rows, predictions)
    write_markdown_report(summary, input_rows, prediction_rows, top_rows, problem_rows)

    print(f"Wrote report tables to {TABLE_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
