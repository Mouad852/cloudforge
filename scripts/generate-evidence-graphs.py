#!/usr/bin/env python3
"""Generate portfolio graphs from the measured E1-E6 experiment values.

These are aggregate evidence summaries, not replacements for CloudWatch time-series
graphs. Each value is copied from the corresponding experiment report.
"""

from pathlib import Path

import matplotlib.pyplot as plt


OUT = Path(__file__).resolve().parents[1] / "docs" / "screenshots" / "14-portfolio"
OUT.mkdir(parents=True, exist_ok=True)

plt.rcParams.update(
    {
        "figure.dpi": 160,
        "savefig.dpi": 220,
        "font.size": 9,
        "axes.titlesize": 11,
        "axes.labelsize": 9,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
    }
)


def save_bar(name: str, labels: list[str], values: list[float], ylabel: str, title: str, note: str) -> None:
    fig, ax = plt.subplots(figsize=(8.2, 4.8))
    fig.subplots_adjust(left=0.11, right=0.98, top=0.86, bottom=0.29)
    bars = ax.bar(labels, values, color="#1f5a85", width=0.62)
    ax.set_ylabel(ylabel)
    ax.set_title(title, loc="left", weight="bold")
    ax.tick_params(axis="x", labelsize=8)
    ax.grid(axis="y", color="#d9e1e8", linewidth=0.8)
    ax.set_axisbelow(True)
    for bar, value in zip(bars, values):
        ax.annotate(
            f"{value:g}",
            (bar.get_x() + bar.get_width() / 2, bar.get_height()),
            xytext=(0, 5),
            textcoords="offset points",
            ha="center",
            va="bottom",
        )
    fig.text(0.01, 0.015, note, ha="left", va="bottom", fontsize=7, color="#4b5563")
    fig.savefig(OUT / name, bbox_inches="tight")
    plt.close(fig)


save_bar(
    "e1-instance-failure-comparison.png",
    ["E1: one instance", "E1: two instances"],
    [1.115, 0.0],
    "Failed requests (%)",
    "E1 — instance-loss availability trade-off",
    "Aggregate k6 samples: 269 requests vs 314 requests; one-instance run had 3 HTTP 503s.",
)

save_bar(
    "e2-e4-latency-summary.png",
    ["E1 one\ninstance", "E1 two\ninstances", "E2 Redis\nreboot", "E3 load\nlower bound", "E4 rolling\ndeploy"],
    [201.66, 623.23, 677.23, 51.09, 664.13],
    "Aggregate p95 latency (ms)",
    "E1-E4 — measured latency summaries",
    "Values are report-level p95 aggregates; workloads and durations differ, so this is not a single benchmark curve.",
)

save_bar(
    "e5-e6-recovery-timings.png",
    ["E5 RPO", "E5 restore\nready", "E6 prod-up\nphase"],
    [286, 1141, 1872],
    "Seconds",
    "E5-E6 — recovery timing evidence",
    "E5: 286s RPO and 1141s restore-ready; E6: approximately 1872s measured prod-up phase.",
)

print(f"Generated graphs in {OUT}")
