#!/usr/bin/env python3
"""Create a McMiner-M input subset using McMiner-S predictions as a filter.

The filter keeps a misconception group when the McMiner-S predictions for that
group either repeat an exact predicted misconception, or contain suspicious
outputs such as parse failures, NONE/no-misconception results, or empty parses.
"""

from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def first_description(prediction: dict[str, Any]) -> str:
    items = prediction.get("predicted_misconceptions") or []
    if not items:
        return "NONE"
    return (items[0].get("description") or "").strip() or "NONE"


def is_suspicious(prediction: dict[str, Any]) -> bool:
    items = prediction.get("predicted_misconceptions") or []
    return (
        not prediction.get("parse_success")
        or prediction.get("no_predicted_misconceptions")
        or not items
        or first_description(prediction) == "NONE"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--single-predictions", required=True, type=Path)
    parser.add_argument("--source-input-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--filter-report", required=True, type=Path)
    parser.add_argument("--min-repeat-count", type=int, default=2)
    parser.add_argument("--clean-output-dir", action="store_true")
    args = parser.parse_args()

    predictions = load_json(args.single_predictions)
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for prediction in predictions:
        gt_id = (prediction.get("ground_truth_misconception") or {}).get("id")
        if gt_id:
            groups[gt_id].append(prediction)

    selected_groups: dict[str, dict[str, Any]] = {}
    for group_id, group_predictions in sorted(groups.items()):
        descriptions = [first_description(pred) for pred in group_predictions]
        repeated = {
            desc: count
            for desc, count in Counter(
                desc for desc in descriptions if desc and desc != "NONE"
            ).items()
            if count >= args.min_repeat_count
        }
        suspicious = [pred for pred in group_predictions if is_suspicious(pred)]
        if repeated or suspicious:
            reasons = []
            if repeated:
                reasons.append("repeated_single_prediction")
            if suspicious:
                reasons.append("suspicious_single_prediction")
            selected_groups[group_id] = {
                "reasons": reasons,
                "total_single_predictions": len(group_predictions),
                "repeated_descriptions": repeated,
                "suspicious_predictions": [
                    {
                        "prediction_id": pred.get("prediction_id"),
                        "source_file": pred.get("source_file"),
                        "parse_success": pred.get("parse_success"),
                        "no_predicted_misconceptions": pred.get("no_predicted_misconceptions"),
                        "description": first_description(pred),
                    }
                    for pred in suspicious
                ],
                "source_files": [pred.get("source_file") for pred in group_predictions],
            }

    if args.clean_output_dir and args.output_dir.exists():
        shutil.rmtree(args.output_dir)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.filter_report.parent.mkdir(parents=True, exist_ok=True)

    copied_files = []
    missing_files = []
    for group in selected_groups.values():
        for source_file in group["source_files"]:
            src = args.source_input_dir / source_file
            dst = args.output_dir / source_file
            if src.exists():
                shutil.copy2(src, dst)
                copied_files.append(source_file)
            else:
                missing_files.append(source_file)

    report = {
        "filter_name": "mcminer_s_repeated_or_suspicious",
        "filter_reason": (
            "Use McMiner-S as a cheap first pass, then run McMiner-M only on "
            "groups where single-code predictions repeat or look suspicious."
        ),
        "single_predictions_file": str(args.single_predictions),
        "source_input_dir": str(args.source_input_dir),
        "output_dir": str(args.output_dir),
        "min_repeat_count": args.min_repeat_count,
        "total_single_groups": len(groups),
        "selected_groups": len(selected_groups),
        "selected_source_files": len(set(copied_files)),
        "missing_source_files": missing_files,
        "selected_group_details": selected_groups,
    }
    args.filter_report.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Selected {len(selected_groups)} of {len(groups)} groups")
    print(f"Copied {len(set(copied_files))} source files to {args.output_dir}")
    print(f"Wrote filter report to {args.filter_report}")
    if missing_files:
        print(f"Warning: {len(missing_files)} source files were missing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
