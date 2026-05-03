#!/usr/bin/env python3
"""Export compact CSV tables for the 9-file completion_lm McMiner runs."""

import csv
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SINGLE_DIR = ROOT / "results" / "mcminer_9_completion_lm_mistral"
MULTI_DIR = ROOT / "results" / "mcminer_m_9_completion_lm_mistral_ctx8192"
TABLE_DIR = ROOT / "results" / "mcminer_9_completion_lm_tables"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def first_misc(prediction: dict[str, Any]) -> tuple[str, str]:
    items = prediction.get("predicted_misconceptions") or []
    if not items:
        return "NONE", ""
    first = items[0]
    return first.get("description", ""), first.get("explanation", "")


def write_summary_table() -> None:
    rows = []
    for label, path in [
        ("McMiner-S", SINGLE_DIR / "summary.json"),
        ("McMiner-M", MULTI_DIR / "multi_summary.json"),
    ]:
        summary = load_json(path)
        stats = summary.get("statistics", {})
        rows.append(
            {
                "run": label,
                "model": summary.get("llm_model", ""),
                "template": summary.get("template_type", ""),
                "processing_mode": summary.get("processing_mode", ""),
                "items_analyzed": stats.get("new_codes_analyzed", stats.get("total_groups", "")),
                "codes_analyzed": stats.get("total_codes_in_file", stats.get("total_codes_analyzed", "")),
                "successful_parses": stats.get("successful_parses", ""),
                "parse_success_rate": stats.get("parse_success_rate", ""),
                "misconceptions_found": stats.get("total_misconceptions_found", ""),
                "avg_misconceptions": stats.get(
                    "average_misconceptions_per_code",
                    stats.get("average_misconceptions_per_group", ""),
                ),
                "no_misconception_items": stats.get(
                    "codes_with_no_misconceptions",
                    stats.get("groups_with_no_predicted_misconceptions", ""),
                ),
            }
        )

    with (TABLE_DIR / "summary_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_single_predictions_table() -> None:
    rows = []
    for prediction in load_json(SINGLE_DIR / "predictions.json"):
        desc, explanation = first_misc(prediction)
        rows.append(
            {
                "prediction_id": prediction.get("prediction_id", ""),
                "source_file": prediction.get("source_file", ""),
                "problem_id": prediction.get("problem_id", ""),
                "solution_index": prediction.get("solution_index", ""),
                "ground_truth_id": (prediction.get("ground_truth_misconception") or {}).get("id", ""),
                "parse_success": prediction.get("parse_success", ""),
                "no_predicted_misconceptions": prediction.get("no_predicted_misconceptions", ""),
                "predicted_description": desc,
                "predicted_explanation": explanation,
            }
        )

    with (TABLE_DIR / "single_predictions_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_multi_predictions_table() -> None:
    rows = []
    for prediction in load_json(MULTI_DIR / "multi_predictions.json"):
        desc, explanation = first_misc(prediction)
        group_info = prediction.get("group_info") or {}
        rows.append(
            {
                "prediction_id": prediction.get("prediction_id", ""),
                "misconception_id": prediction.get("misconception_id", ""),
                "problem_id": prediction.get("problem_id", ""),
                "num_codes": group_info.get("num_codes", ""),
                "num_problems": group_info.get("num_problems", ""),
                "source_files": ";".join(group_info.get("source_files") or []),
                "parse_success": prediction.get("parse_success", ""),
                "no_predicted_misconceptions": prediction.get("no_predicted_misconceptions", ""),
                "predicted_description": desc,
                "predicted_explanation": explanation,
            }
        )

    with (TABLE_DIR / "multi_predictions_table.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    TABLE_DIR.mkdir(parents=True, exist_ok=True)
    write_summary_table()
    write_single_predictions_table()
    write_multi_predictions_table()
    print(f"Wrote tables to {TABLE_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
