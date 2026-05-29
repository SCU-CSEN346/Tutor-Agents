"""
Plot pass rate AVERAGED across all 4 EvoCodeBench projects:
  TRAVER baseline  vs  McMiner-Loop

Source: Coding-Tutor/notes/comprehensive_results.md
  - Section 1: Per-project best-round summary (Baseline)
  - Section 4: Combined sd-forge (3 tasks) + UHGEval Colab rerun (McMiner-Loop)
  - Section 2: EasyVolcap McMiner-Loop peak P@1 by level
  - Section 3: searcharray McMiner conditions (Peak P@1)

Benchmark: EvoCodeBench-2403, 22 tasks across 4 projects, n=10 completions/task.

Projects (4):
  - sd-forge      (3 tasks: codeformer setup_model + gfpgan fix_faces & setup_model)
  - UHGEval       (1 task:  xinhua statistics)
  - searcharray   (6 tasks)
  - EasyVolcap    (12 tasks)

Two averaging strategies are plotted:
  1. Unweighted project mean  — each project counts equally
  2. Task-weighted mean       — weighted by # tasks per project (sums to 22)

Outputs (PNG) go to a timestamped subdir of plots_passrate/ so reruns
never overwrite earlier files.

Charts:
  1. avg_by_level_unweighted.png     — by level, unweighted across 4 projects
  2. avg_by_level_task_weighted.png  — by level, task-weighted (n=22)
  3. avg_overall_p1_unweighted.png   — single-bar Baseline vs McMiner (mean of all levels & projects)
  4. per_project_peak_p1_overall.png — per-project peak P@1 (mean of 3 levels), side by side

Run:
    python3 plot_all_projects_avg_traver_vs_mcminer.py
"""

from __future__ import annotations

import os
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np


# ---------------------------------------------------------------------------
# Data — Peak P@1 per (project, level) for each condition
# Numbers are taken verbatim from comprehensive_results.md
# ---------------------------------------------------------------------------

# (low, med, high) Peak P@1 percentages
BASELINE_TRAVER = {
    # Section 4 "Combined sd-forge (3 tasks weighted average)"
    "sd-forge":    (86.7, 90.0, 86.7),
    # Section 1 / Section 4 (xinhua statistics single task)
    "UHGEval":     (100.0, 90.0, 90.0),
    # Section 3 baseline row
    "searcharray": (0.0, 0.0, 15.0),
    # Section 1 EasyVolcap peak rows
    "EasyVolcap":  (23.0, 16.0, 15.8),
}

MCMINER_LOOP = {
    # Section 4 "Combined sd-forge (3 tasks weighted average)" — Colab rerun
    "sd-forge":    (100.0, 100.0, 100.0),
    # Section 4 — Colab rerun on xinhua
    "UHGEval":     (100.0, 100.0, 100.0),
    # Section 3 — all McMiner-Loop searcharray rounds 0%
    "searcharray": (0.0, 0.0, 0.0),
    # Section 2 — EasyVolcap McMiner-Loop peak P@1 by level
    "EasyVolcap":  (11.0, 16.7, 24.2),
}

# Task counts per project (from comprehensive_results.md header)
TASKS_PER_PROJECT = {
    "sd-forge":    3,
    "UHGEval":     1,
    "searcharray": 6,
    "EasyVolcap":  12,
}

PROJECTS = list(BASELINE_TRAVER.keys())  # canonical order
LEVELS = ["low_level", "med_level", "high_level"]
TOTAL_TASKS = sum(TASKS_PER_PROJECT.values())  # 22
assert TOTAL_TASKS == 22, TOTAL_TASKS


# ---------------------------------------------------------------------------
# Averaging helpers
# ---------------------------------------------------------------------------

def unweighted_mean_by_level(data: dict) -> tuple[float, float, float]:
    """Average across projects for each level (each project counts equally)."""
    arr = np.array([data[p] for p in PROJECTS])  # shape (4, 3)
    return tuple(arr.mean(axis=0))


def task_weighted_mean_by_level(data: dict) -> tuple[float, float, float]:
    """Task-weighted average across projects for each level."""
    weights = np.array([TASKS_PER_PROJECT[p] for p in PROJECTS])  # (4,)
    arr = np.array([data[p] for p in PROJECTS])                   # (4, 3)
    return tuple((arr * weights[:, None]).sum(axis=0) / weights.sum())


def project_peak_mean(data: dict) -> dict[str, float]:
    """Per-project peak P@1 averaged across the 3 levels."""
    return {p: float(np.mean(data[p])) for p in PROJECTS}


def overall_mean_unweighted(data: dict) -> float:
    """Single scalar: mean across all 4 projects and 3 levels (12 cells)."""
    arr = np.array([data[p] for p in PROJECTS])
    return float(arr.mean())


def overall_mean_task_weighted(data: dict) -> float:
    """Single scalar: task-weighted mean across all projects, averaged over levels."""
    by_level = task_weighted_mean_by_level(data)
    return float(np.mean(by_level))


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------

COLORS = {
    "Baseline (TRAVER)": "#4C78A8",
    "McMiner-Loop":      "#F58518",
}


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
        mc = task_weighted_mean_by_level(MCMINER_LOOP)
        title_suffix = "task-weighted (n=22 tasks)"
        fname_suffix = "task-weighted"
    else:
        bl = unweighted_mean_by_level(BASELINE_TRAVER)
        mc = unweighted_mean_by_level(MCMINER_LOOP)
        title_suffix = "unweighted (4 projects, each equal)"
        fname_suffix = "unweighted"

    x = np.arange(len(LEVELS))
    width = 0.36

    fig, ax = plt.subplots(figsize=(9, 5.2))
    bars1 = ax.bar(x - width / 2, bl, width,
                   label="Baseline (TRAVER)", color=COLORS["Baseline (TRAVER)"])
    bars2 = ax.bar(x + width / 2, mc, width,
                   label="McMiner-Loop",      color=COLORS["McMiner-Loop"])
    _annotate(ax, bars1, suffix="%")
    _annotate(ax, bars2, suffix="%")

    # Δ labels placed just above each pair (above the taller of the two bars)
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
        f"Baseline (TRAVER) vs McMiner-Loop"
    )
    ax.set_ylim(0, ymax + 14)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    # legend below the plot so it never overlaps annotations
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08),
              ncol=2, frameon=False)
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_overall_unweighted(out_path: str) -> None:
    bl = overall_mean_unweighted(BASELINE_TRAVER)
    mc = overall_mean_unweighted(MCMINER_LOOP)
    delta = mc - bl

    fig, ax = plt.subplots(figsize=(7, 5))
    bars = ax.bar(
        ["Baseline (TRAVER)", "McMiner-Loop"],
        [bl, mc],
        color=[COLORS["Baseline (TRAVER)"], COLORS["McMiner-Loop"]],
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
        "Baseline (TRAVER) vs McMiner-Loop"
    )
    ax.set_ylim(0, max(bl, mc) + 18)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_per_project_peak(out_path: str) -> None:
    bl = project_peak_mean(BASELINE_TRAVER)
    mc = project_peak_mean(MCMINER_LOOP)

    x = np.arange(len(PROJECTS))
    width = 0.36

    fig, ax = plt.subplots(figsize=(10, 5.4))
    bars1 = ax.bar(x - width / 2, [bl[p] for p in PROJECTS], width,
                   label="Baseline (TRAVER)", color=COLORS["Baseline (TRAVER)"])
    bars2 = ax.bar(x + width / 2, [mc[p] for p in PROJECTS], width,
                   label="McMiner-Loop",      color=COLORS["McMiner-Loop"])
    _annotate(ax, bars1, suffix="%")
    _annotate(ax, bars2, suffix="%")

    labels = [f"{p}\n({TASKS_PER_PROJECT[p]} tasks)" for p in PROJECTS]
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("Peak Pass@1 (mean of 3 levels) (%)")
    ax.set_title("Per-project Peak Pass@1 (mean of low/med/high)\n"
                 "Baseline (TRAVER) vs McMiner-Loop")
    ax.set_ylim(0, 115)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    ax.legend(loc="upper right")
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(script_dir, "plots_passrate", f"avg_run_{timestamp}")
    os.makedirs(out_dir, exist_ok=True)

    # Print the numbers we're plotting (handy for the report)
    print("=== Unweighted project-mean Peak P@1 by level ===")
    print(f"  Baseline: {tuple(round(v, 1) for v in unweighted_mean_by_level(BASELINE_TRAVER))}")
    print(f"  McMiner : {tuple(round(v, 1) for v in unweighted_mean_by_level(MCMINER_LOOP))}")
    print()
    print("=== Task-weighted Peak P@1 by level (n=22) ===")
    print(f"  Baseline: {tuple(round(v, 1) for v in task_weighted_mean_by_level(BASELINE_TRAVER))}")
    print(f"  McMiner : {tuple(round(v, 1) for v in task_weighted_mean_by_level(MCMINER_LOOP))}")
    print()
    print("=== Per-project Peak P@1 (mean of 3 levels) ===")
    bl_pp = project_peak_mean(BASELINE_TRAVER)
    mc_pp = project_peak_mean(MCMINER_LOOP)
    for p in PROJECTS:
        print(f"  {p:12s}: BL={bl_pp[p]:5.1f}%  MC={mc_pp[p]:5.1f}%  Δ={mc_pp[p]-bl_pp[p]:+5.1f}pp")
    print()
    print(f"=== Overall mean (unweighted) ===  "
          f"BL={overall_mean_unweighted(BASELINE_TRAVER):.1f}%  "
          f"MC={overall_mean_unweighted(MCMINER_LOOP):.1f}%")
    print(f"=== Overall mean (task-weighted) === "
          f"BL={overall_mean_task_weighted(BASELINE_TRAVER):.1f}%  "
          f"MC={overall_mean_task_weighted(MCMINER_LOOP):.1f}%")
    print()

    plots = [
        ("avg_by_level_unweighted.png",     lambda p: plot_by_level(p, task_weighted=False)),
        ("avg_by_level_task_weighted.png",  lambda p: plot_by_level(p, task_weighted=True)),
        ("avg_overall_p1_unweighted.png",   plot_overall_unweighted),
        ("per_project_peak_p1_overall.png", plot_per_project_peak),
    ]

    print(f"Writing plots to: {out_dir}")
    for name, fn in plots:
        path = os.path.join(out_dir, name)
        fn(path)
        print(f"  - {name}")

    print("\nDone.")


if __name__ == "__main__":
    main()
