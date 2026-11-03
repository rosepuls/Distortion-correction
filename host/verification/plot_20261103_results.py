"""Render separate image correction and enhancement figures from saved CSVs."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
BASE = HERE / "analysis_20261103"
CORR = BASE / "image_correction"
ENH = BASE / "image_enhancement"


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def save(fig, path):
    fig.tight_layout()
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main():
    plt.rcParams.update({"font.size": 10, "axes.spines.top": False,
                         "axes.spines.right": False, "figure.facecolor": "white"})
    correction = rows(CORR / "metrics.csv")
    grid = correction[:4]
    x = np.arange(4)
    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    ax.bar(x - 0.18, [float(r["input_grid_p95_px"]) for r in grid], 0.36,
           label="Original image", color="#64748b")
    ax.bar(x + 0.18, [float(r["output_grid_p95_px"]) for r in grid], 0.36,
           label="FPGA HDMI capture", color="#0b7285")
    ax.set(xticks=x, xticklabels=[r["image_id"] for r in grid],
           xlabel="Verification image ID", ylabel="P95 point-to-line residual (px)",
           title="Checkerboard straightness: full 9 x 6 corner grids")
    ax.legend(frameon=False)
    ax.grid(axis="y", alpha=0.18)
    save(fig, CORR / "01_grid_straightness.png")

    fig, ax = plt.subplots(figsize=(7.8, 4.2))
    bars = ax.bar([r["image_id"] for r in correction],
                  [float(r["output_border_percent"]) for r in correction], color="#247ba0")
    ax.bar_label(bars, fmt="%.2f%%", padding=3, fontsize=8)
    ax.set(xlabel="Verification image ID", ylabel="Estimated black border area (%)",
           title="FPGA output: boundary-connected near-black area")
    ax.set_ylim(0, 3.35)
    ax.grid(axis="y", alpha=0.18)
    save(fig, CORR / "02_black_border.png")

    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    colors = {"4": "#a1483a", "6": "#0b7285", "7": "#6750a4"}
    for row in correction:
        if not row["sfr_csv"]:
            continue
        curve = rows(Path(row["sfr_csv"]))
        frequency = [float(r["frequency_cycles_per_captured_pixel"]) for r in curve]
        sfr = [float(r["sfr_normalized"]) for r in curve]
        ax.plot(frequency, sfr, label=f"Image {row['image_id']} (MTF50 {float(row['mtf50_cycles_per_pixel']):.3f})",
                color=colors[row["image_id"]], linewidth=1.8)
    ax.axhline(0.5, color="#555", linestyle="--", linewidth=1)
    ax.set(xlim=(0, 0.5), ylim=(0, 1.2), xlabel="Spatial frequency (cycles/captured pixel)",
           ylabel="Normalized SFR", title="Engineering slanted-edge SFR on accepted image regions")
    ax.legend(frameon=False)
    ax.grid(alpha=0.18)
    save(fig, CORR / "03_sfr_curves.png")

    enhancement = rows(ENH / "metrics.csv")
    x = np.arange(5)
    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    ax.bar(x - 0.18, [float(r["input_mean_y"]) for r in enhancement], 0.36,
           label="OBS input", color="#64748b")
    ax.bar(x + 0.18, [float(r["output_mean_y"]) for r in enhancement], 0.36,
           label="FPGA output", color="#db7c26")
    ax.set(xticks=x, xticklabels=[r["profile_id"] for r in enhancement],
           xlabel="Enhancement profile ID", ylabel="Mean 8-bit grayscale value",
           title="Measured brightness by enhancement profile", ylim=(0, 265))
    ax.legend(frameon=False)
    ax.grid(axis="y", alpha=0.18)
    save(fig, ENH / "01_mean_brightness.png")

    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    values = [float(r["output_delta_from_profile0_y"]) for r in enhancement]
    bars = ax.bar(x, values, color=["#64748b" if v == 0 else "#0b7285" if v > 0 else "#a1483a" for v in values])
    ax.bar_label(bars, labels=[f"{v:+.1f}" for v in values], padding=3, fontsize=9)
    ax.axhline(0, color="#333", linewidth=1)
    ax.set(xticks=x, xticklabels=[r["profile_id"] for r in enhancement],
           xlabel="Enhancement profile ID", ylabel="Output mean minus profile 0 (8-bit levels)",
           title="FPGA output brightness change relative to bypass", ylim=(-60, 75))
    ax.grid(axis="y", alpha=0.18)
    save(fig, ENH / "02_output_change_vs_bypass.png")

    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    ax.plot(x, [float(r["input_p90_y"]) for r in enhancement], "o-", label="OBS input P90", color="#64748b")
    ax.plot(x, [float(r["output_p90_y"]) for r in enhancement], "o-", label="FPGA output P90", color="#db7c26")
    ax.set(xticks=x, xticklabels=[r["profile_id"] for r in enhancement],
           xlabel="Enhancement profile ID", ylabel="90th percentile grayscale value",
           title="Bright-region response by enhancement profile", ylim=(150, 260))
    ax.legend(frameon=False)
    ax.grid(alpha=0.18)
    save(fig, ENH / "03_highlight_p90.png")

    print(f"Figures saved under {CORR} and {ENH}")


if __name__ == "__main__":
    main()
