"""Summarize the 2026-11-03 image correction and enhancement captures."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from measure_hdmi_sfr import measure_grid_straightness

OUT = HERE / "analysis_20261103"
CORRECTION_OUT = OUT / "image_correction"
ENHANCEMENT_OUT = OUT / "image_enhancement"


def read_image(path: Path):
    frame = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError(f"Cannot read {path}")
    return frame


def write_csv(path: Path, rows: list[dict]):
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def luma_metrics(path: Path):
    gray = cv2.cvtColor(read_image(path), cv2.COLOR_BGR2GRAY)
    return {
        "mean_y": round(float(gray.mean()), 3),
        "p10_y": round(float(np.percentile(gray, 10)), 3),
        "p90_y": round(float(np.percentile(gray, 90)), 3),
        "dark_le32_percent": round(100 * float((gray <= 32).mean()), 3),
        "bright_ge250_percent": round(100 * float((gray >= 250).mean()), 3),
    }


def main():
    CORRECTION_OUT.mkdir(parents=True, exist_ok=True)
    ENHANCEMENT_OUT.mkdir(parents=True, exist_ok=True)
    correction_log = HERE / "capture_results" / "measurements.jsonl"
    records = [json.loads(line) for line in correction_log.read_text(encoding="utf-8").splitlines()]
    latest = {}
    for record in records:
        latest[record["image_id"]] = record
    if set(range(8)) - latest.keys():
        raise ValueError("Missing image correction captures 0..7")

    correction = []
    for image_id in range(8):
        record = latest[image_id]
        grid = record["grid_straightness"]
        source_grid = None
        if grid.get("coverage") == "full":
            source_grid = measure_grid_straightness(read_image(HERE / f"{image_id}.png"))
            if source_grid["coverage"] != "full":
                raise ValueError(f"Original image {image_id} lacks full checkerboard")
        input_p95 = source_grid["p95_px"] if source_grid else None
        output_p95 = grid.get("p95_px") if grid.get("coverage") == "full" else None
        sfr = record["sfr"]
        correction.append({
            "image_id": image_id,
            "capture_time": record["timestamp"],
            "capture_width": record["capture_size"][0],
            "capture_height": record["capture_size"][1],
            "grid_coverage": grid.get("coverage", "unavailable"),
            "input_grid_p95_px": round(input_p95, 4) if input_p95 is not None else None,
            "output_grid_p95_px": round(output_p95, 4) if output_p95 is not None else None,
            "grid_p95_change_percent": (round(100 * (output_p95 / input_p95 - 1), 2)
                                         if input_p95 and output_p95 is not None else None),
            "output_grid_mean_px": round(grid["mean_px"], 4) if output_p95 is not None else None,
            "output_grid_max_px": round(grid["max_px"], 4) if output_p95 is not None else None,
            "output_border_percent": round(record["black_border"]["percent"], 4),
            "sfr_status": sfr["status"],
            "mtf50_cycles_per_pixel": (round(sfr["mtf50_cycles_per_captured_pixel"], 4)
                                       if sfr.get("mtf50_cycles_per_captured_pixel") is not None else None),
            "sfr_0_10": round(sfr["samples"]["0.10"], 4) if sfr["status"] == "ok" else None,
            "sfr_0_20": round(sfr["samples"]["0.20"], 4) if sfr["status"] == "ok" else None,
            "sfr_0_30": round(sfr["samples"]["0.30"], 4) if sfr["status"] == "ok" else None,
            "sfr_0_40": round(sfr["samples"]["0.40"], 4) if sfr["status"] == "ok" else None,
            "sfr_0_50": round(sfr["samples"]["0.50"], 4) if sfr["status"] == "ok" else None,
            "sfr_csv": record.get("sfr_csv"),
            "capture_png": record["capture_png"],
        })
    write_csv(CORRECTION_OUT / "metrics.csv", correction)
    (CORRECTION_OUT / "metrics.json").write_text(
        json.dumps(correction, ensure_ascii=False, indent=2), encoding="utf-8")

    enhancement_log = HERE / "enhancement_profiles" / "captures.jsonl"
    captures = [json.loads(line) for line in enhancement_log.read_text(encoding="utf-8").splitlines()]
    profiles = {}
    for capture in captures:
        profiles[capture["profile_id"]] = capture
    if set(range(5)) - profiles.keys():
        raise ValueError("Missing enhancement profiles 0..4")
    enhancement = []
    for profile_id in range(5):
        capture = profiles[profile_id]
        # Device indices were reversed when these five files were named:
        # index 3 is OBS input, index 2 is FPGA HDMI output.
        input_path = Path(capture["hdmi_png"])
        output_path = Path(capture["obs_png"])
        input_stats = luma_metrics(input_path)
        output_stats = luma_metrics(output_path)
        enhancement.append({
            "profile_id": profile_id,
            "sequence": capture["sequence"],
            "capture_time": capture["time"],
            "input_mean_y": input_stats["mean_y"],
            "output_mean_y": output_stats["mean_y"],
            "output_delta_from_profile0_y": None,
            "input_p10_y": input_stats["p10_y"],
            "output_p10_y": output_stats["p10_y"],
            "input_p90_y": input_stats["p90_y"],
            "output_p90_y": output_stats["p90_y"],
            "output_dark_le32_percent": output_stats["dark_le32_percent"],
            "output_bright_ge250_percent": output_stats["bright_ge250_percent"],
            "input_png_actual": str(input_path),
            "output_png_actual": str(output_path),
            "capture_skew_ms": capture["capture_skew_ms"],
        })
    baseline = enhancement[0]["output_mean_y"]
    for row in enhancement:
        row["output_delta_from_profile0_y"] = round(row["output_mean_y"] - baseline, 3)
    write_csv(ENHANCEMENT_OUT / "metrics.csv", enhancement)
    (ENHANCEMENT_OUT / "metrics.json").write_text(json.dumps({
        "rows": enhancement,
        "provenance": "Captures 0..4 used reversed device labels: index 3 OBS input, index 2 FPGA output."
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {CORRECTION_OUT / 'metrics.csv'}")
    print(f"Wrote {ENHANCEMENT_OUT / 'metrics.csv'}")


if __name__ == "__main__":
    main()
