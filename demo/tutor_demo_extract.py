#!/usr/bin/env python3
"""
Extract a multi-level demo dataset comparing BASELINE tutor dialogues vs the
ACTUAL McMiner-Clean tutor dialogues that were produced by the McMiner-in-the-Loop
pipeline (with [MISCONCEPTION FEEDBACK] injected into the tutor's role description
between rounds).

NOTE (2026-06): This script references file paths from an original cloud session
  (/sessions/dazzling-zealous-davinci/mnt/Tutor-Agents/...) that is no longer
  accessible. The pre-extracted output (tutor_demo_data.json) is committed to the
  repo and is the preferred way to run the demo.

  The updated tutor_demo.html fetches tutor_demo_data.json dynamically from
  Google Drive or a local file — no need to re-run this extraction.

  If you need to re-extract, update the ROOT path below to point to a local
  copy of the output data, or download from the shared Google Drive folder:
  https://drive.google.com/drive/folders/1OrDsWpk2b4rIGJ8k61Nuc5wMU2cMpUI1

Sources:
  - Baseline dialogues: output_vanilla_4projects/dialogue_vanilla/{proj_dir}/
                         dialogue/vanilla/Llama-3.1-70B-Instruct/{level}/simulated_dialogs.jsonl
  - McMiner-Clean dialogues: embedded in the prompt field of
                             Coding-Tutor/output/student_posttest_mcminer_clean/{proj}/
                             traver/Llama-3.1-70B-Instruct/{level}/prompt_round_N.jsonl
                             (under "Below is your discussion with a tutor:")
  - McMiner misconception: mcminer/results/mcminer_60_completion_lm_tables/detailed_predictions_table.csv
  - Pass@k: comprehensive_results.md + README headline tables

Outputs demo_data.json consumed by tutor_demo.html.
"""

import ast
import csv
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path("/sessions/dazzling-zealous-davinci/mnt/Tutor-Agents")
VANILLA_DIR = ROOT / "output_vanilla_4projects/dialogue_vanilla"
MCMINER_CLEAN_DIR = ROOT / "Coding-Tutor/output/student_posttest_mcminer_clean"
MCMINER_CSV = ROOT / "mcminer/results/mcminer_60_completion_lm_tables/detailed_predictions_table.csv"

OUT = Path("/sessions/dazzling-zealous-davinci/mnt/outputs/demo_data.json")

LEVELS = ["low_level", "med_level", "high_level"]

# Which prompt_round_N to use as the "final" McMiner-Clean dialogue for each task.
# R7 is the headline round (where the +15.9pp EasyVolcap high_level peak lives,
# per comprehensive_results.md §2). The extractor walks back to find the latest
# non-empty round if the preferred one is missing.
DEFAULT_ROUND = 7

# Tasks to feature. For each, we pull:
#   - baseline dialogue from VANILLA_DIR/{baseline_project_dir}/
#   - McMiner-Clean dialogue from MCMINER_CLEAN_DIR/{mc_project_dir}/
#   - misconception from the CSV by namespace
DEMO_TASKS = [
    {
        "namespace": "easyvolcap.utils.loss_utils.lossfun_distortion",
        "project_label": "EasyVolcap (headline result)",
        "baseline_project_dir": "easyvolcap",
        "mc_project_dir": "easyvolcap",
        "title": "lossfun_distortion (EasyVolcap)",
        "summary": "PyTorch distortion loss with inter- + intra-interval components. This is the +15.9pp McMiner-Clean win on high_level students (EasyVolcap R7 — the headline result).",
        "round": DEFAULT_ROUND,
    },
    {
        "namespace": "searcharray.postings.SearchArray.phrase_freq",
        "project_label": "searcharray",
        "baseline_project_dir": "searcharray",
        "mc_project_dir": "searcharray",
        "title": "SearchArray.phrase_freq (searcharray)",
        "summary": "Compute phrase frequencies with slop / non-unique tokens. McMiner detects the slop=1 misconception but cannot fix it on this project (0% vs 15% baseline at high_level).",
        "round": DEFAULT_ROUND,
    },
    {
        "namespace": "searcharray.utils.bitcount.bit_count64",
        "project_label": "searcharray",
        "baseline_project_dir": "searcharray",
        "mc_project_dir": "searcharray",
        "title": "bit_count64 (searcharray)",
        "summary": "Bitwise popcount via SWAR masks. Baseline student invents fictional concepts (\"KL-N\"); McMiner-Clean tutor opens with concrete mask explanations.",
        "round": DEFAULT_ROUND,
    },
]

# Per-task per-level Pass@k. Numbers come from comprehensive_results.md.
# For lossfun_distortion specifically: high_level R7 has the full +15.9pp
# Pass@1/@5/@10 breakdown (the headline same-round comparison in §2).
# Low_level / med_level for EasyVolcap aggregate stats come from §1.
PASS_AT_K = {
    "easyvolcap.utils.loss_utils.lossfun_distortion": {
        "low_level":  {"baseline": {"p1": 23.0, "p5": 29.2, "p10": 30.0, "round": "R7"},
                       "mcminer_clean": {"p1": 10.8, "p5": None, "p10": None, "round": "R1"}},
        "med_level":  {"baseline": {"p1": 16.0, "p5": 27.5, "p10": 30.0, "round": "R4"},
                       "mcminer_clean": {"p1": 17.5, "p5": None, "p10": None, "round": "R8"}},
        "high_level": {"baseline": {"p1": 15.8, "p5": 28.5, "p10": 33.3, "round": "R1"},
                       "mcminer_clean": {"p1": 31.7, "p5": 41.6, "p10": 41.7, "round": "R7"}},
    },
    "searcharray.postings.SearchArray.phrase_freq": {
        "low_level":  {"baseline": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"}},
        "med_level":  {"baseline": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"}},
        "high_level": {"baseline": {"p1": 15.0, "p5": 25.0, "p10": 25.0, "round": "R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": None, "p10": None, "round": "R1-R8"}},
    },
    "searcharray.utils.bitcount.bit_count64": {
        "low_level":  {"baseline": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"}},
        "med_level":  {"baseline": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": 0.0, "p10": 0.0, "round": "R1-R8"}},
        "high_level": {"baseline": {"p1": 15.0, "p5": 25.0, "p10": 25.0, "round": "R8"},
                       "mcminer_clean": {"p1": 0.0, "p5": None, "p10": None, "round": "R1-R8"}},
    },
}


def compute_delta(b, m):
    if b is None or m is None:
        return None
    d = m - b
    sign = "+" if d >= 0 else ""
    return f"{sign}{d:.1f}pp"


def build_pass_at_k(ns):
    table = PASS_AT_K.get(ns, {})
    out = {}
    for lvl in LEVELS:
        row = table.get(lvl)
        if not row:
            out[lvl] = None
            continue
        bl = row["baseline"]
        mc = row["mcminer_clean"]
        out[lvl] = {
            "baseline": bl,
            "mcminer_clean": mc,
            "deltas": {
                "p1": compute_delta(bl["p1"], mc["p1"]),
                "p5": compute_delta(bl["p5"], mc["p5"]),
                "p10": compute_delta(bl["p10"], mc["p10"]),
            },
        }
    return out


# ───────────────────────── file IO (deadlock-resistant) ─────────────────────────
def rg_match_line(path, pattern):
    """Extract the first matching line. The macOS mount accumulates a Resource-
    deadlock state across multiple file reads in one process, so when rg fails
    we shell out to a fresh python3 subprocess per file (which has been the
    most reliable workaround)."""
    if not path.exists():
        return None
    # Fast path: rg in the current process
    for attempt in range(3):
        try:
            r = subprocess.run(
                ["rg", "-N", "-m1", "--no-heading", pattern, str(path)],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode in (0, 1):
                return r.stdout.strip() or None
        except subprocess.TimeoutExpired:
            pass
        time.sleep(0.3 * (attempt + 1))
    # Fallback: isolated python subprocess
    needle = pattern.lstrip("^").replace("\\.", ".")
    script = (
        "import sys\n"
        f"with open({str(path)!r}) as f:\n"
        "    for line in f:\n"
        f"        if {needle!r} in line:\n"
        "            sys.stdout.write(line); break\n"
    )
    for attempt in range(3):
        try:
            time.sleep(2.0 * (attempt + 1))
            r = subprocess.run(["python3", "-c", script], capture_output=True, text=True, timeout=15)
            if r.returncode == 0:
                return r.stdout.strip() or None
        except subprocess.TimeoutExpired:
            pass
    print(f"  ! read failed for {path.name}", file=sys.stderr)
    return None


# Hard-coded fallbacks for baseline dialogues that the macOS mount keeps deadlocking on.
# Sourced manually via the Read tool from the same simulated_dialogs.jsonl paths
# below. Used only if rg fails to read the file.
BASELINE_FALLBACKS = {
    ("sd-webui-forge", "codeformer_model.setup_model", "low_level"): [
        {"tutor": "Hello, how's your Python programming knowledge, especially with classes and functions?"},
        {"student": "Hi there, I'd say my Python programming knowledge is still developing, but I've learned about classes and functions as part of that. Could you please explain more about the `FaceRestorerCodeFormer` class and what it's used for in this context?"},
        {"tutor": "The `FaceRestorerCodeFormer` class is used for face restoration, inheriting from `CommonFaceRestoration`. It utilizes the CodeFormer model. Would you like to see its implementation details?"},
        {"student": "Yes, I'd appreciate it if you could share some details about the `FaceRestorerCodeFormer` class, such as its methods and attributes. Also, could you explain what you mean by \"utilizes the CodeFormer model\"? I'd like to understand the context better before attempting to implement the `setup_model` function."},
        {"tutor": "`FaceRestorerCodeFormer` has methods like `load_net` and `restore`. It uses the CodeFormer model, a pre-trained AI model for face restoration, loaded from a `.pth` file."},
        {"student": "Based on what you've shared, I assume that the `FaceRestorerCodeFormer` class is responsible for loading and using the CodeFormer model for face restoration. The `load_net` method likely handles loading the pre-trained model from the `.pth` file, while the `restore` method probably applies the face restoration using the loaded model.\n\nWith this understanding, I'll attempt to implement the `setup_model` function as follows:\n\n```Python\nimport os\n\ndef setup_model(dirname: str) -> None:\n    try:\n        face_restorer = FaceRestorerCodeFormer(dirname)\n        global face_restorers\n        face_restorers.append(face_restorer)\n        print(f\"Successfully initialized FaceRestorerCode"},
        {"tutor": "You're close, but `face_restorers` should be `shared.face_restorers`. Also, use `errors.report` for error handling, not `print`. Let's correct that."},
        {"student": "Thank you for the correction. Here's the updated `setup_model` function:\n\n```Python\nimport os\nfrom errors import ErrorReport\n\ndef setup_model(dirname: str) -> None:\n    try:\n        face_restorer = FaceRestorerCodeFormer(dirname)\n        global shared\n        shared.face_restorers.append(face_restorer)\n    except Exception as e:\n        error = ErrorReport(f\"Error occurred during setup_model: {str(e)}\")\n        shared.errors.report(error)\n```\n\nI've updated the global variable name to `shared.face_restorers` and used the `ErrorReport` class and `shared.errors.report` method for error handling."},
        {"tutor": "You're almost there. Declare `codeformer` as global and assign `face_restorer` to it. Also, use `errors.report` directly for error handling, as shown in the reference solution."},
        {"student": "I'll make the necessary changes:\n\n```Python\nimport os\nfrom errors import ErrorReport\n\ndef setup_model(dirname: str) -> None:\n    global codeformer\n\n    try:\n        codeformer = FaceRestorerCodeFormer(dirname)\n        shared.face_restorers.append(codeformer)\n    except Exception as e:\n        error = ErrorReport(f\"Error occurred during setup_model: {str(e)}\")\n        shared.errors.report(error)\n```\n\nI've declared `codeformer` as a global variable and assigned the `face_restorer` instance to it."},
    ],
    ("sd-webui-forge", "codeformer_model.setup_model", "med_level"): [
        {"tutor": "Hello, how's your Python knowledge, especially with classes and functions?"},
        {"student": "Hello! I'm a college student learning Python, and I've had some experience with classes and functions. Based on the given function signature, it seems like `setup_model` is intended to be a function that sets up a model for face restoration using the `FaceRestorerCodeFormer` class from the `codeformer_model` module. However, I'm not entirely sure how to proceed with implementing this function, as there are no explicit instructions provided on how to initialize the `FaceRestorerCodeFormer` instance or add it to a global list. Could you please provide some guidance on that?"},
    ],
}


def get_baseline_dialogue(baseline_project_dir, namespace, level):
    """Return the baseline conversation list, or None."""
    path = (VANILLA_DIR / baseline_project_dir / "dialogue/vanilla/Llama-3.1-70B-Instruct"
            / level / "simulated_dialogs.jsonl")
    pat = '^\\{"namespace": "' + namespace.replace(".", "\\.") + '",'
    line = rg_match_line(path, pat)
    if line:
        try:
            rec = json.loads(line)
            return rec["conversation"]
        except (json.JSONDecodeError, KeyError):
            pass
    # Fall back to manually-extracted dialogues
    fb = BASELINE_FALLBACKS.get((baseline_project_dir, namespace, level))
    if fb:
        print(f"  (using fallback for {baseline_project_dir}/{namespace}/{level})", file=sys.stderr)
        return fb
    return None


# ───────────────────────── McMiner posttest dialogue parser ─────────────────────────
DIALOG_START_MARKER = "Below is your discussion with a tutor:\n"
DIALOG_END_MARKERS = [
    "\n\nPlease directly complete",
    "\nPlease directly complete",
    "\n\n[Note]",
]

# Each turn line looks like:  {'tutor': "..."}  or  {'student': "..."}
# (Python-repr style — could use single or double outer quotes)
TURN_LINE_RE = re.compile(r"^\s*\{['\"](tutor|student)['\"]\s*:\s*(.+)\}\s*$")


def parse_posttest_dialogue(prompt_text):
    """Extract a list of {tutor|student: content} dicts from the embedded
    conversation in a posttest prompt."""
    start = prompt_text.find(DIALOG_START_MARKER)
    if start == -1:
        return None
    start += len(DIALOG_START_MARKER)

    end = len(prompt_text)
    for marker in DIALOG_END_MARKERS:
        idx = prompt_text.find(marker, start)
        if idx != -1 and idx < end:
            end = idx

    body = prompt_text[start:end].strip()
    if not body:
        return None

    conversation = []
    # Each turn is one line — but the line may contain literal '\n' that should
    # be unescaped. Each turn dict is a Python repr.
    for raw_line in body.split("\n"):
        line = raw_line.strip()
        if not line:
            continue
        # Try to parse the dict via ast.literal_eval (safe, no code exec).
        try:
            d = ast.literal_eval(line)
            if isinstance(d, dict) and len(d) == 1:
                role, content = next(iter(d.items()))
                if role in ("tutor", "student") and isinstance(content, str):
                    conversation.append({role: content})
                    continue
        except (ValueError, SyntaxError):
            pass
        # Fallback to regex if literal_eval fails
        m = TURN_LINE_RE.match(line)
        if m:
            role = m.group(1)
            content_raw = m.group(2).strip()
            # Try literal_eval on just the string part
            try:
                content = ast.literal_eval(content_raw)
                if isinstance(content, str):
                    conversation.append({role: content})
            except (ValueError, SyntaxError):
                pass
    return conversation if conversation else None


def get_mcminer_clean_dialogue(mc_project_dir, namespace, level, preferred_round):
    """Pull the McMiner-Clean dialogue from the embedded prompt. The pipeline
    sometimes terminates early, leaving later round files essentially empty (1
    byte). We try preferred_round, then walk down to find the latest non-empty
    round."""
    level_dir = (MCMINER_CLEAN_DIR / mc_project_dir / "traver/Llama-3.1-70B-Instruct" / level)
    if not level_dir.exists():
        return None, None
    candidates = []
    for r in range(preferred_round, 0, -1):
        f = level_dir / f"prompt_round_{r}.jsonl"
        try:
            if f.exists() and f.stat().st_size > 10:
                candidates.append((r, f))
        except OSError:
            pass
    pat = '"namespace": "' + namespace.replace(".", "\\.") + '"'
    for r, f in candidates:
        line = rg_match_line(f, pat)
        if not line:
            continue
        try:
            rec = json.loads(line)
            prompt = rec.get("prompt", "")
        except json.JSONDecodeError:
            continue
        conv = parse_posttest_dialogue(prompt)
        if conv:
            return conv, r
    return None, None


# ───────────────────────── McMiner misconception ─────────────────────────
def find_mcminer_misconception(ns):
    if not MCMINER_CSV.exists():
        return None
    with MCMINER_CSV.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        seen = []
        for row in reader:
            if row.get("namespace") == ns and row.get("parse_success") == "True":
                desc = (row.get("predicted_description") or "").strip()
                if not desc:
                    continue
                seen.append({
                    "description": desc,
                    "explanation": (row.get("predicted_explanation") or "").strip(),
                    "code": (row.get("generated_code") or "").strip(),
                })
    if not seen:
        return None
    counts = {}
    for s in seen:
        counts[s["description"]] = counts.get(s["description"], 0) + 1
    best_desc = max(counts.items(), key=lambda x: x[1])[0]
    for s in seen:
        if s["description"] == best_desc:
            return {**s, "count": counts[best_desc], "total_samples": len(seen)}


def find_first_student_code_turn(conv):
    if not conv:
        return 0
    for i, turn in enumerate(conv):
        if "student" in turn and "```" in turn["student"]:
            return i
    for i, turn in enumerate(conv):
        if "student" in turn:
            return i
    return 0


def build():
    out_tasks = []
    for spec in DEMO_TASKS:
        ns = spec["namespace"]
        baseline_dialogues = {}
        mc_dialogues = {}
        detect_after_baseline = {}
        detect_after_mc = {}
        mc_round_used = {}
        for lvl in LEVELS:
            bl_conv = get_baseline_dialogue(spec["baseline_project_dir"], ns, lvl)
            mc_conv, mc_round = get_mcminer_clean_dialogue(spec["mc_project_dir"], ns, lvl, spec["round"])
            if bl_conv:
                baseline_dialogues[lvl] = bl_conv
                detect_after_baseline[lvl] = find_first_student_code_turn(bl_conv)
            if mc_conv:
                mc_dialogues[lvl] = mc_conv
                detect_after_mc[lvl] = find_first_student_code_turn(mc_conv)
                mc_round_used[lvl] = mc_round
            if not bl_conv:
                print(f"  ! no baseline for {ns}/{lvl}", file=sys.stderr)
            if not mc_conv:
                print(f"  ! no McMiner-Clean for {ns}/{lvl}", file=sys.stderr)

        if not baseline_dialogues and not mc_dialogues:
            print(f"WARN: skipping {ns} (no data)", file=sys.stderr)
            continue

        mc_info = find_mcminer_misconception(ns) or {
            "description": "(no specific misconception extracted)", "explanation": "",
            "code": "", "count": 0, "total_samples": 0,
        }

        # default level = first one that has BOTH baseline and McMiner data,
        # preferring high_level
        default_level = None
        for cand in ["high_level", "med_level", "low_level"]:
            if cand in baseline_dialogues and cand in mc_dialogues:
                default_level = cand
                break
        if default_level is None:
            default_level = next(iter(baseline_dialogues.keys() or mc_dialogues.keys()))

        available_levels = sorted(
            set(baseline_dialogues.keys()) & set(mc_dialogues.keys()),
            key=LEVELS.index,
        )
        if not available_levels:
            # fall back to union if no level has both
            available_levels = sorted(
                set(baseline_dialogues.keys()) | set(mc_dialogues.keys()),
                key=LEVELS.index,
            )

        out_tasks.append({
            "namespace": ns,
            "title": spec["title"],
            "project": spec["project_label"],
            "summary": spec["summary"],
            "round_shown_preferred": spec["round"],
            "mc_round_used": mc_round_used,
            "default_level": default_level,
            "available_levels": available_levels,
            "baseline_dialogues": baseline_dialogues,
            "mcminer_dialogues": mc_dialogues,
            "detect_after_turn_baseline": detect_after_baseline,
            "detect_after_turn_mcminer": detect_after_mc,
            "mcminer": {
                "misconception": mc_info["description"],
                "explanation": mc_info["explanation"],
                "augmented_code": mc_info["code"],
                "support_count": mc_info["count"],
                "total_student_samples": mc_info["total_samples"],
            },
            "pass_at_k_by_level": build_pass_at_k(ns),
        })

    out = {
        "generated_at": "2026-05-25",
        "headline": {
            "title": "TRAVER + McMiner-in-the-Loop",
            "subtitle": "Side-by-side replay of BASELINE tutor vs the same tutor with McMiner-injected misconception feedback. Both dialogues are real outputs from the pipeline.",
            "best_result": {
                "label": "Headline: EasyVolcap high_level Pass@1 (R7 same-round)",
                "from": 15.8, "to": 31.7, "delta": "+15.9pp",
            },
        },
        "tasks": out_tasks,
    }
    OUT.write_text(json.dumps(out, indent=2))
    print(f"OK: wrote {OUT} -- {len(out_tasks)} tasks")
    for t in out_tasks:
        bl_lvls = ", ".join(t["baseline_dialogues"].keys())
        mc_lvls = ", ".join(t["mcminer_dialogues"].keys())
        n_bl_default = len(t["baseline_dialogues"].get(t["default_level"], []))
        n_mc_default = len(t["mcminer_dialogues"].get(t["default_level"], []))
        print(f"  - {t['namespace']:55s}")
        print(f"     baseline levels: [{bl_lvls}]  | default {t['default_level']}: {n_bl_default} turns")
        print(f"     mcminer  levels: [{mc_lvls}]  | default {t['default_level']}: {n_mc_default} turns")


if __name__ == "__main__":
    build()
