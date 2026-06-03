#!/usr/bin/env python3
"""Merge the 4 tasks from backup_demo/demo_data.json into tutor_demo_data.json.

Converts from the backup demo format (role/text turns, per-round passRates)
to the main demo format (tutor/student turns, pass_at_k_by_level).
"""

import json
from pathlib import Path

DEMO_DIR = Path(__file__).parent

def convert_turns(backup_turns):
    """Convert [{role, text}] → [{tutor: text}, {student: text}, ...]"""
    result = []
    for turn in backup_turns:
        role = turn["role"]
        text = turn["text"]
        if role in ("tutor", "student"):
            result.append({role: text})
        # Skip 'system' turns (vanilla placeholder)
    return result


def find_best_round(rates):
    """Find the round with the highest pass rate. Returns (round_num, rate)."""
    best_round = None
    best_rate = -1
    for rkey, rate in rates.items():
        if rate is not None and rate > best_rate:
            best_rate = rate
            best_round = int(rkey.replace("R", ""))
    return best_round, best_rate


def convert_task(backup_task):
    """Convert a backup demo task to the main demo format."""
    level = backup_task["level"]  # e.g. "high_level"

    # Convert dialogues: pick first entry from traver (→ baseline) and mcminer
    traver_entries = backup_task["dialogues"].get("traver", [])
    mcminer_entries = backup_task["dialogues"].get("mcminer", [])

    baseline_turns = convert_turns(traver_entries[0]["turns"]) if traver_entries else []
    mcminer_turns = convert_turns(mcminer_entries[0]["turns"]) if mcminer_entries else []

    namespace = ""
    if traver_entries:
        namespace = traver_entries[0].get("namespace", "")
    elif mcminer_entries:
        namespace = mcminer_entries[0].get("namespace", "")

    # McMiner misconception info
    misconceptions = []
    if mcminer_entries and "misconceptions" in mcminer_entries[0]:
        misconceptions = mcminer_entries[0]["misconceptions"]

    first_misconception = misconceptions[0]["description"] if misconceptions else ""
    detect_turn = 1  # default: misconception detected after turn 1

    # Pass rates
    rates = backup_task["passRates"]
    bl_best_round, bl_best_rate = find_best_round(rates.get("traver", {}))
    mc_best_round, mc_best_rate = find_best_round(rates.get("mcminer", {}))

    # Build delta string
    if bl_best_rate is not None and mc_best_rate is not None:
        delta = mc_best_rate - bl_best_rate
        delta_str = f"+{delta:.1f}pp" if delta >= 0 else f"{delta:.1f}pp"
    else:
        delta_str = None

    pass_at_k = {
        level: {
            "baseline": {
                "round": f"R{bl_best_round}" if bl_best_round else "—",
                "p1": bl_best_rate if bl_best_rate and bl_best_rate > 0 else (0.0 if bl_best_rate == 0 else None),
                "p5": None,
                "p10": None,
            },
            "mcminer_clean": {
                "round": f"R{mc_best_round}" if mc_best_round else "—",
                "p1": mc_best_rate if mc_best_rate and mc_best_rate > 0 else (0.0 if mc_best_rate == 0 else None),
                "p5": None,
                "p10": None,
            },
            "deltas": {
                "p1": delta_str,
                "p5": None,
                "p10": None,
            },
        }
    }

    return {
        "namespace": namespace,
        "title": backup_task["label"],
        "project": backup_task["project"],
        "summary": backup_task["description"]
                   + (f" ({backup_task['highlight']})" if backup_task.get("highlight") else ""),
        "round_shown_preferred": mc_best_round or bl_best_round or 1,
        "mc_round_used": {level: mc_best_round or 1},
        "default_level": level,
        "available_levels": [level],
        "baseline_dialogues": {level: baseline_turns},
        "mcminer_dialogues": {level: mcminer_turns},
        "detect_after_turn_baseline": {level: 0},
        "detect_after_turn_mcminer": {level: detect_turn},
        "mcminer": {
            "misconception": first_misconception,
            "support_count": len(misconceptions),
            "total_student_samples": len(misconceptions),
            "augmented_code": None,
        },
        "pass_at_k_by_level": pass_at_k,
    }


def main():
    # Load main demo data
    main_path = DEMO_DIR / "tutor_demo_data.json"
    with open(main_path) as f:
        main_data = json.load(f)

    # Load backup demo data
    backup_path = DEMO_DIR / "backup_demo" / "demo_data.json"
    with open(backup_path) as f:
        backup_data = json.load(f)

    # Check existing task namespaces to avoid duplicates
    existing = {t["namespace"] for t in main_data["tasks"]}

    added = 0
    for backup_task in backup_data["tasks"]:
        converted = convert_task(backup_task)
        if converted["namespace"] in existing:
            print(f"  SKIP (already exists): {converted['title']} — {converted['namespace']}")
            continue
        main_data["tasks"].append(converted)
        existing.add(converted["namespace"])
        added += 1
        print(f"  ADDED: {converted['title']} — {converted['namespace']}")

    # Write updated data
    with open(main_path, "w") as f:
        json.dump(main_data, f, indent=2, ensure_ascii=False)

    total = len(main_data["tasks"])
    size_kb = main_path.stat().st_size / 1024
    print(f"\n✅ Done! {total} tasks total ({added} new). File: {main_path} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
