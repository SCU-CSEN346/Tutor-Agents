"""
Plot EasyVolcap McMiner + TRAVER pass rate results.

Source: Coding-Tutor/notes/comprehensive_results.md (Sections 1 and 2)
Benchmark: EvoCodeBench-2403, EasyVolcap project, 12 tasks, n=10 completions/task

Outputs (PNG) are written to a timestamped subdirectory of
Coding-Tutor/scripts/local/plots_passrate/ so reruns never overwrite
each other.

Charts produced:
  1. easyvolcap_peak_p1_by_level.png
     Peak P@1 per level: TRAVER baseline vs McMiner-Loop vs McMiner-Clean
  2. easyvolcap_high_level_r7_pk.png
     Same-round R7 high_level: P@1/P@3/P@5/P@10 across conditions
  3. easyvolcap_high_level_round_by_round_p1.png
     Round-by-round P@1 on high_level: Baseline vs McMiner vs Clean
  4. easyvolcap_bestvsbest_high_level.png
     Best-vs-best high_level summary (15.8% -> 31.7%, +15.9pp)

Run:
    python3 plot_easyvolcap_mcminer_traver_passrate.py
"""

from __future__ import annotations

import os
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np


# ---------------------------------------------------------------------------
# Data (from comprehensive_results.md)
# ---------------------------------------------------------------------------

# Section 2: EasyVolcap Round-by-Round Pass@1 (P@1, percentages)
#   Format in the source markdown: "low / med / high" per cell
# Rounds reported in the table: R1, R4, R7, R8
ROUNDS = ["R1", "R4", "R7", "R8"]

# (low, med, high) for each round
P1_BY_ROUND = {
    "Baseline (TRAVER)": {
        "R1": (12.5, 3.3, 15.8),
        "R4": (0.0, 16.0, 9.0),
        "R7": (23.0, 10.0, 6.0),
        "R8": (21.0, 10.0, 6.0),
    },
    "McMiner-Loop": {
        "R1": (10.8, 2.5, 15.8),
        "R4": (2.0, 0.0, 15.0),
        "R7": (10.0, 15.0, 24.2),
        "R8": (5.0, 16.7, 21.7),
    },
    "McMiner-Clean": {
        "R1": (10.8, 7.5, 19.2),
        "R4": (2.0, 1.7, 16.7),
        "R7": (8.0, 16.7, 31.7),
        "R8": (4.0, 17.5, 15.0),
    },
}

# Section 2 "McMiner Effectiveness by Student Level" — Peak P@1 with best-round label
PEAK_P1_BY_LEVEL = {
    # level: (baseline_val, baseline_round, mcminer_val, mcminer_round, clean_val, clean_round)
    "low_level":  (23.0, "R7", 11.0, "R6", 10.8, "R1"),
    "med_level":  (16.0, "R4", 16.7, "R8", 17.5, "R8"),
    "high_level": (15.8, "R1", 24.2, "R7", 31.7, "R7"),
}

# Section 2 "Headline Result" — same-round (R7) high_level P@k comparison
R7_HIGH_LEVEL_PK = {
    "P@1":  {"Baseline (TRAVER)":  6.0, "McMiner-Loop": 24.2, "McMiner-Clean": 31.7},
    "P@3":  {"Baseline (TRAVER)": 12.2, "McMiner-Loop": 35.7, "McMiner-Clean": 40.8},
    "P@5":  {"Baseline (TRAVER)": 15.0, "McMiner-Loop": 39.6, "McMiner-Clean": 41.6},
    "P@10": {"Baseline (TRAVER)": 20.0, "McMiner-Loop": 41.7, "McMiner-Clean": 41.7},
}


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------

# Consistent colors per condition across all charts
COLORS = {
    "Baseline (TRAVER)": "#4C78A8",  # blue
    "McMiner-Loop":      "#F58518",  # orange
    "McMiner-Clean":     "#54A24B",  # green
}


def _annotate_bars(ax, bars, fmt="{:.1f}", offset=0.6, fontsize=9):
    for b in bars:
        h = b.get_height()
        ax.text(
            b.get_x() + b.get_width() / 2.0,
            h + offset,
            fmt.format(h),
            ha="center",
            va="bottom",
            fontsize=fontsize,
        )


def plot_peak_p1_by_level(out_path: str) -> None:
    levels = list(PEAK_P1_BY_LEVEL.keys())
    conditions = ["Baseline (TRAVER)", "McMiner-Loop", "McMiner-Clean"]

    # Values per condition across levels
    vals = {
        "Baseline (TRAVER)": [PEAK_P1_BY_LEVEL[l][0] for l in levels],
        "McMiner-Loop":      [PEAK_P1_BY_LEVEL[l][2] for l in levels],
        "McMiner-Clean":     [PEAK_P1_BY_LEVEL[l][4] for l in levels],
    }
    rounds = {
        "Baseline (TRAVER)": [PEAK_P1_BY_LEVEL[l][1] for l in levels],
        "McMiner-Loop":      [PEAK_P1_BY_LEVEL[l][3] for l in levels],
        "McMiner-Clean":     [PEAK_P1_BY_LEVEL[l][5] for l in levels],
    }

    x = np.arange(len(levels))
    width = 0.26

    fig, ax = plt.subplots(figsize=(9, 5.2))
    for i, cond in enumerate(conditions):
        offset = (i - 1) * width
        bars = ax.bar(x + offset, vals[cond], width, label=cond, color=COLORS[cond])
        # annotate value + best-round label
        for b, r in zip(bars, rounds[cond]):
            h = b.get_height()
            ax.text(
                b.get_x() + b.get_width() / 2.0,
                h + 0.6,
                f"{h:.1f}%\n({r})",
                ha="center",
                va="bottom",
                fontsize=8,
            )

    ax.set_xticks(x)
    ax.set_xticklabels(levels)
    ax.set_ylabel("Peak Pass@1 (%)")
    ax.set_title("EasyVolcap — Peak Pass@1 by Student Level\n"
                 "TRAVER baseline vs McMiner-Loop vs McMiner-Clean (12 tasks, n=10)")
    ax.set_ylim(0, max(max(v) for v in vals.values()) + 8)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_r7_high_level_pk(out_path: str) -> None:
    metrics = ["P@1", "P@3", "P@5", "P@10"]
    conditions = ["Baseline (TRAVER)", "McMiner-Loop", "McMiner-Clean"]

    x = np.arange(len(metrics))
    width = 0.26

    fig, ax = plt.subplots(figsize=(9, 5.2))
    for i, cond in enumerate(conditions):
        offset = (i - 1) * width
        vals = [R7_HIGH_LEVEL_PK[m][cond] for m in metrics]
        bars = ax.bar(x + offset, vals, width, label=cond, color=COLORS[cond])
        _annotate_bars(ax, bars, fmt="{:.1f}", offset=0.6, fontsize=9)

    ax.set_xticks(x)
    ax.set_xticklabels(metrics)
    ax.set_ylabel("Pass@k (%)")
    ax.set_title("EasyVolcap high_level @ Round 7 — same-round Pass@k comparison\n"
                 "McMiner-Clean +25.7pp P@1 over TRAVER baseline (same-round)")
    ax.set_ylim(0, 50)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_high_level_round_by_round(out_path: str) -> None:
    """Round-by-round P@1 on high_level for each condition."""
    conditions = ["Baseline (TRAVER)", "McMiner-Loop", "McMiner-Clean"]

    fig, ax = plt.subplots(figsize=(9, 5.2))
    for cond in conditions:
        vals = [P1_BY_ROUND[cond][r][2] for r in ROUNDS]  # index 2 = high_level
        ax.plot(ROUNDS, vals, marker="o", linewidth=2,
                label=cond, color=COLORS[cond])
        for r, v in zip(ROUNDS, vals):
            ax.annotate(f"{v:.1f}", (r, v),
                        textcoords="offset points", xytext=(0, 6),
                        ha="center", fontsize=8, color=COLORS[cond])

    ax.set_ylabel("Pass@1 (%)")
    ax.set_xlabel("TRAVER Round")
    ax.set_title("EasyVolcap high_level — Pass@1 by Round\n"
                 "Reported rounds from comprehensive_results.md: R1, R4, R7, R8")
    ax.set_ylim(0, 40)
    ax.grid(True, linestyle="--", alpha=0.4)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


def plot_bestvsbest_high_level(out_path: str) -> None:
    """Best-vs-best summary for high_level: 15.8% -> 31.7%, +15.9pp."""
    labels = ["TRAVER baseline\n(best round: R1)", "McMiner-Clean\n(best round: R7)"]
    values = [15.8, 31.7]
    colors = [COLORS["Baseline (TRAVER)"], COLORS["McMiner-Clean"]]

    fig, ax = plt.subplots(figsize=(7.5, 5))
    bars = ax.bar(labels, values, color=colors, width=0.55)
    _annotate_bars(ax, bars, fmt="{:.1f}%", offset=0.6, fontsize=11)

    # Draw delta annotation
    ax.annotate(
        "",
        xy=(1, values[1]), xytext=(1, values[0]),
        arrowprops=dict(arrowstyle="<->", color="black", lw=1.5),
    )
    ax.text(
        1.18, (values[0] + values[1]) / 2,
        "Δ = +15.9pp",
        fontsize=12, fontweight="bold", color="black", va="center",
    )

    ax.set_ylabel("Peak Pass@1 (%)")
    ax.set_title("EasyVolcap high_level — Best-vs-best Pass@1\n"
                 "McMiner-Clean improves +15.9pp over TRAVER baseline")
    ax.set_ylim(0, 40)
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    fig.tight_layout()
    fig.savefig(out_path, dpi=160)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(script_dir, "plots_passrate", f"run_{timestamp}")
    os.makedirs(out_dir, exist_ok=True)

    plots = [
        ("easyvolcap_peak_p1_by_level.png",          plot_peak_p1_by_level),
        ("easyvolcap_high_level_r7_pk.png",          plot_r7_high_level_pk),
        ("easyvolcap_high_level_round_by_round_p1.png", plot_high_level_round_by_round),
        ("easyvolcap_bestvsbest_high_level.png",     plot_bestvsbest_high_level),
    ]

    print(f"Writing plots to: {out_dir}")
    for name, fn in plots:
        path = os.path.join(out_dir, name)
        fn(path)
        print(f"  - {name}")

    print("\nDone.")


if __name__ == "__main__":
    main()
