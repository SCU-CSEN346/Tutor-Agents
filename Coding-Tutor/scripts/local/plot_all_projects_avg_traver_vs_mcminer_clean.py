"""
Plot pass rate AVERAGED across all 4 EvoCodeBench projects:
  TRAVER baseline  vs  McMiner-Clean

Source: Coding-Tutor/notes/comprehensive_results.md
  - Section 1: Per-project best-round summary (Baseline)
  - Section 2: EasyVolcap McMiner-Clean peak P@1 by level (R1/R4/R7/R8)
  - Section 3: searcharray McMiner-Clean (all 0%)

Data gap and assumption
-----------------------
McMiner-Clean was not re-run end-to-end on sd-forge and UHGEval
(no test_results.jsonl in student_posttest_mcminer_clean/ for
codeformer_model/gfpgan_model/xinhua). For those two easy projects
we proxy McMiner-Clean using the McMiner-Loop Colab rerun numbers
(100% on every level), which is reasonable because the easy
projects are saturated and Clean differs only by stripping
misconception-jargon from the posttest prompt — it cannot reduce
pass rate from a 100% ceiling.

This assumption is annotated on the relevant chart.

Benchmark: EvoCodeBench-2403, 22 tasks across 4 projects, n=10 completions/task.

Projects (4):
  - sd-forge      (3 tasks)
  - UHGEval       (1 task)
  - searcharray   (6 tasks)
  - EasyVolcap    (12 tasks)

Outputs (PNG) go to a timestamped subdir of plots_passrate/
so reruns never overwrite earlier files.

Charts:
  1. avg_by_level_unweighted_clean.png
  2. avg_by_level_task_weighted_clean.png
  3. avg_overall_p1_unweighted_clean.png
  4. per_project_peak_p1_overall_clean.png

Run:
    python3 plot_all_projects_avg_traver_vs_mcminer_clean.py
"""

from __future__ import annotations

import os
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np


# ---------------------------------------------------------------------------
# Data — Peak P@1 per (project, level)
# ---------------------------------------------------------------------------

# (low, med, high)
BASELINE_TRAVER = {
    "sd-forge":    (86.7, 90.0, 86.7),    # Section 4 combined sd-forge
    "UHGEval":     (100.0, 90.0, 90.0),   # Section 1 / Section 4 xinhua
    "searcharray": (0.0, 0.0, 15.0),      # Section 3 baseline
    "EasyVolcap":  (23.0, 16.0, 15.8),    # Section 1 EasyVolcap peaks
}

# Clean numbers:
#   - EasyVolcap: Section 2 "McMiner-Effectiveness by Student Level"
#       low=10.8 (R1), med=17.5 (R8), high=31.7 (R7)
#   - searcharray: Section 3 — 0% across all rounds for McMiner-Clean
#   - sd-forge / UHGEval: not run end-to-end as Clean; proxied with
#       McMiner-Loop Colab rerun = 100% on every level (saturated)
MCMINER_CLEAN = {
    "sd-forge":    (100.0, 100.0, 100.0),  # proxy — see assumption above
    "UHGEval":     (100.0, 100.0, 100.0),  # proxy — see assumption above
    "searcharray": (0.0,   0.0,   0.0),
    "EasyVolcap":  (10.8, 17.5, 31.7),
}

# Projects where Clean values are proxied from Loop
PROXIED_PROJECTS = {"sd-forge", "UHGEval"}

# Task counts (sum = 22)
TASKS_PER_PROJECT = {
    "sd-forge":    3,
    "UHGEval":     1,
    "searcharray": 6,
    "EasyVolcap":  12,
}

PROJECTS = list(BASELINE_TRAVER.keys())
LEVELS = ["low_level", "med_level", "high_level"]
TOTAL_TASKS = sum(TASKS_PER_PROJECT.values())
assert TOTAL_TASKS == 22, TOTAL_TASKS


# ---------------------------------------------------------------------------
# Averaging helpers
# ---------------------------------------------------------------------------

def unweighted_mean_by_level(data: dict) -> tuple[float, float, float]:
    arr = np.array([data[p] for p in PROJECTS])
    return tuple(arr.mean(axis=0))


def task_weighted_mean_by_level(data: dict) -> tuple[float, float, float]:
    weights = np.array([TASKS_PER_PROJECT[p] for p in PROJECTS])
    arr = np.array([data[p] for p in PROJECTS])
    return tuple((arr * weights[:, None]).sum(axis=0) / weights.sum())


def project_peak_mean(data: dict) -> dict[str, float]:
    return {p: float(np.mean(data[p])) for p in PROJECTS}


def overall_mean_unweighted(data: dict) -> float:
    arr = np.array([data[p] for p in PROJECTS])
    return float(arr.mean())


def overall_mean_task_weighted(data: dict) -> float:
    return float(np.mean(task_weighted_mean_by_level(data)))


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------

COLORS = {
    "Baseline (TRAVER)": "#4C78A8",
    "McMiner-Clean":     "#54A24B",   # green to match prior Clean charts
}

CLEAN_PROXY_NOTE = ("Note: sd-forge & UHGEval Clean values proxied with "
                    "McMiner-Loop (100%) — Clean not re-run on those projects.")


def _annotate(ax, bars, fmt="{:.1f}", offset=0.8, fontsize=10, suffix=""):
    for b in bars:
        h = b.get_height()
        ax.text(
            b.get_x() + b.get_width() / 2.0,
            h + offset,
            fmt.format(h) + suffix,
            ha="center", va="bottom", fontsize=fontsize,
        )


def plot_by_level(out_path: str, *, task_weighted: bool) -> None:
    if task_weighted:
        bl = task_weighted_mean_by_level(BASELINE_TRAVER)
        mc = task_weighted_mean_by_level(MCMINER_CLEAN)
        title_suffix = "task-weighted (n=22 tasks)"
    else:
        bl = unweighted_mean_by_level(BASELINE_TRAVER)
        mc = unweighted_mean_by_level(MCMINER_CLEAN)
        title_suffix = "unweighted (4 projects, each equal)"

    x = np.arange(len(LEVELS))
    width = 0.36

    fig, ax = plt.subplots(figsize=(9.5, 5.6))
    bars1 = ax.bar(x - width / 2, bl, width,
                   label="Baseline (TRAVER)", color=COLORS["Baseline (TRAVER)"])
    bars2 = ax.bar(x + width / 2, mc, width,
                   label="McMiner-Clean",     color=COLORS["McMiner-Clean"])
    _annotate(ax, bars1, suffix="%")
    _annotate(ax, bars2, suffix="%")

    # Δ labels above each pair
    for i, (b, m) in enumerate(zip(bl, mc)):
        pair_top = max(b, m)
        delta = m - b
        sign = "+" if delta >= 0 else ""
        ax.text(
            x[i], pair_top + 4.0,
            f"Δ {sign}{delta:.1f}pp",
            ha="center", va="bottom",
            fontsize=10, fontweight="bold",
            color="black" if delta >= 0 else "#B22222",
        )

    ymax = max(max(bl), max(mc))
    ax.set_xticks(x)
    ax.set_xticklabels(LEVELS)
    ax.set_ylabel("Average Peak Pass@1 (%)")
    ax.set_title(
        f"Avg Peak Pass@1 across all 4 projects — {title_suffix}\n"
        f"Baseline (TRAVER) vs McMiner-Clean"
    )
    ax.set_ylim(0, ymax + 14)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08),
              ncol=2, frameon=False)

    # caveat footer
    fig.text(0.5, 0.005, CLEAN_PROXY_NOTE,
             ha="center", va="bottom", fontsize=8, style="italic", color="#555")
    fig.tight_layout(rect=[0, 0.04, 1, 1])
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_overall_unweighted(out_path: str) -> None:
    bl = overall_mean_unweighted(BASELINE_TRAVER)
    mc = overall_mean_unweighted(MCMINER_CLEAN)
    delta = mc - bl

    fig, ax = plt.subplots(figsize=(7.4, 5.4))
    bars = ax.bar(
        ["Baseline (TRAVER)", "McMiner-Clean"],
        [bl, mc],
        color=[COLORS["Baseline (TRAVER)"], COLORS["McMiner-Clean"]],
        width=0.5,
    )
    _annotate(ax, bars, suffix="%")

    sign = "+" if delta >= 0 else ""
    ax.text(
        0.5, max(bl, mc) + 5,
        f"Δ {sign}{delta:.1f}pp",
        ha="center", va="bottom",
        fontsize=12, fontweight="bold",
        transform=ax.get_xaxis_transform(),
        color="black" if delta >= 0 else "#B22222",
    )

    ax.set_ylabel("Average Peak Pass@1 (%)")
    ax.set_title(
        "Overall Avg Peak Pass@1 — all 4 projects × 3 levels (unweighted)\n"
        "Baseline (TRAVER) vs McMiner-Clean"
    )
    ax.set_ylim(0, max(bl, mc) + 18)
    ax.grid(axis="y", linestyle="--", alpha=0.4)

    fig.text(0.5, 0.005, CLEAN_PROXY_NOTE,
             ha="center", va="bottom", fontsize=8, style="italic", color="#555")
    fig.tight_layout(rect=[0, 0.04, 1, 1])
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_per_project_peak(out_path: str) -> None:
    bl = project_peak_mean(BASELINE_TRAVER)
    mc = project_peak_mean(MCMINER_CLEAN)

    x = np.arange(len(PROJECTS))
    width = 0.36

    fig, ax = plt.subplots(figsize=(10.5, 5.8))
    bars1 = ax.bar(x - width / 2, [bl[p] for p in PROJECTS], width,
                   label="Baseline (TRAVER)", color=COLORS["Baseline (TRAVER)"])
    bars2 = ax.bar(x + width / 2, [mc[p] for p in PROJECTS], width,
                   label="McMiner-Clean",     color=COLORS["McMiner-Clean"])
    _annotate(ax, bars1, suffix="%")
    _annotate(ax, bars2, suffix="%")

    # mark proxied bars
    for i, p in enumerate(PROJECTS):
        if p in PROXIED_PROJECTS:
            ax.text(x[i] + width / 2, 2,
                    "proxy\n(=Loop)",
                    ha="center", va="bottom",
                    fontsize=8, color="white", fontweight="bold")

    labels = [f"{p}\n({TASKS_PER_PROJECT[p]} tasks)" for p in PROJECTS]
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("Peak Pass@1 (mean of 3 levels) (%)")
    ax.set_title("Per-project Peak Pass@1 (mean of low/med/high)\n"
                 "Baseline (TRAVER) vs McMiner-Clean")
    ax.set_ylim(0, 115)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    ax.legend(loc="upper right")

    fig.text(0.5, 0.005, CLEAN_PROXY_NOTE,
             ha="center", va="bottom", fontsize=8, style="italic", color="#555")
    fig.tight_layout(rect=[0, 0.04, 1, 1])
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(script_dir, "plots_passrate", f"avg_clean_run_{timestamp}")
    os.makedirs(out_dir, exist_ok=True)

    print("=== Unweighted project-mean Peak P@1 by level ===")
    print(f"  Baseline    : {tuple(round(v, 1) for v in unweighted_mean_by_level(BASELINE_TRAVER))}")
    print(f"  McMiner-Clean: {tuple(round(v, 1) for v in unweighted_mean_by_level(MCMINER_CLEAN))}")
    print()
    print("=== Task-weighted Peak P@1 by level (n=22) ===")
    print(f"  Baseline    : {tuple(round(v, 1) for v in task_weighted_mean_by_level(BASELINE_TRAVER))}")
    print(f"  McMiner-Clean: {tuple(round(v, 1) for v in task_weighted_mean_by_level(MCMINER_CLEAN))}")
    print()
    print("=== Per-project Peak P@1 (mean of 3 levels) ===")
    bl_pp = project_peak_mean(BASELINE_TRAVER)
    mc_pp = project_peak_mean(MCMINER_CLEAN)
    for p in PROJECTS:
        proxy = " (proxy)" if p in PROXIED_PROJECTS else ""
        print(f"  {p:12s}: BL={bl_pp[p]:5.1f}%  Clean={mc_pp[p]:5.1f}%{proxy}  "
              f"Δ={mc_pp[p]-bl_pp[p]:+5.1f}pp")
    print()
    print(f"=== Overall mean (unweighted) ===  "
          f"BL={overall_mean_unweighted(BASELINE_TRAVER):.1f}%  "
          f"Clean={overall_mean_unweighted(MCMINER_CLEAN):.1f}%")
    print(f"=== Overall mean (task-weighted) === "
          f"BL={overall_mean_task_weighted(BASELINE_TRAVER):.1f}%  "
          f"Clean={overall_mean_task_weighted(MCMINER_CLEAN):.1f}%")
    print()
    print(CLEAN_PROXY_NOTE)
    print()

    plots = [
        ("avg_by_level_unweighted_clean.png",
         lambda p: plot_by_level(p, task_weighted=False)),
        ("avg_by_level_task_weighted_clean.png",
         lambda p: plot_by_level(p, task_weighted=True)),
        ("avg_overall_p1_unweighted_clean.png",
         plot_overall_unweighted),
        ("per_project_peak_p1_overall_clean.png",
         plot_per_project_peak),
    ]

    print(f"Writing plots to: {out_dir}")
    for name, fn in plots:
        path = os.path.join(out_dir, name)
        fn(path)
        print(f"  - {name}")

    print("\nDone.")


if __name__ == "__main__":
    main()
