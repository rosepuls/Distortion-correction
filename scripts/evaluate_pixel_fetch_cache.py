"""Evaluate deterministic cache policies on sampled 720P distortion traces."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOFTWARE_DIR = PROJECT_ROOT / "software"
sys.path.insert(0, str(SOFTWARE_DIR))

from address_trace_model import generate_address_trace
from bitaccurate_distortion import (
    FixedPointCameraModel,
    source_coordinates_fixed,
    split_source_coordinates,
)
from cache_model import NO_CACHE, ROW_WINDOW, TILE_16X4, CacheConfig, simulate_cache


WIDTH = 1280
HEIGHT = 720
RASTER_STRIDE = 8
POLICIES: tuple[CacheConfig, ...] = (NO_CACHE, ROW_WINDOW, TILE_16X4)


def sampled_output_coordinates(
    width: int = WIDTH,
    height: int = HEIGHT,
    stride: int = RASTER_STRIDE,
) -> tuple[np.ndarray, np.ndarray]:
    """Return a deterministic raster sample plus every border coordinate."""

    if width <= 0 or height <= 0 or stride <= 0:
        raise ValueError("width, height, and stride must be positive")

    sample_y, sample_x = np.indices(
        ((height + stride - 1) // stride, (width + stride - 1) // stride),
        dtype=np.int64,
    )
    sample_x = np.clip(sample_x * stride, 0, width - 1).ravel()
    sample_y = np.clip(sample_y * stride, 0, height - 1).ravel()

    border_x = np.concatenate(
        (
            np.arange(width, dtype=np.int64),
            np.arange(width, dtype=np.int64),
            np.zeros(height, dtype=np.int64),
            np.full(height, width - 1, dtype=np.int64),
        )
    )
    border_y = np.concatenate(
        (
            np.zeros(width, dtype=np.int64),
            np.full(width, height - 1, dtype=np.int64),
            np.arange(height, dtype=np.int64),
            np.arange(height, dtype=np.int64),
        )
    )

    coordinates = np.unique(
        np.column_stack(
            (
                np.concatenate((sample_x, border_x)),
                np.concatenate((sample_y, border_y)),
            )
        ),
        axis=0,
    )
    return coordinates[:, 0], coordinates[:, 1]


def evaluate_camera(
    name: str,
    camera: FixedPointCameraModel,
    *,
    width: int = WIDTH,
    height: int = HEIGHT,
    stride: int = RASTER_STRIDE,
) -> list[tuple[str, object, object]]:
    output_x, output_y = sampled_output_coordinates(width, height, stride)
    source_x, source_y = source_coordinates_fixed(output_x, output_y, camera)
    x0, y0, _dx, _dy, coord_valid = split_source_coordinates(
        source_x, source_y, width=width, height=height
    )
    requests, trace_metrics = generate_address_trace(
        x0,
        y0,
        coord_valid,
        width,
        height,
    )
    return [
        (
            name,
            trace_metrics,
            simulate_cache(requests, width, height, policy),
        )
        for policy in POLICIES
    ]


def build_report(width: int = WIDTH, height: int = HEIGHT, stride: int = RASTER_STRIDE) -> str:
    cameras = (
        (
            "identity",
            FixedPointCameraModel.from_parameters(
                fx=900.0,
                fy=900.0,
                cx=(width - 1) / 2.0,
                cy=(height - 1) / 2.0,
            ),
        ),
        (
            "barrel",
            FixedPointCameraModel.from_parameters(
                fx=900.0,
                fy=900.0,
                cx=(width - 1) / 2.0,
                cy=(height - 1) / 2.0,
                k1=-0.25,
                k2=0.05,
                p1=0.001,
                p2=-0.001,
            ),
        ),
        (
            "pincushion",
            FixedPointCameraModel.from_parameters(
                fx=900.0,
                fy=900.0,
                cx=(width - 1) / 2.0,
                cy=(height - 1) / 2.0,
                k1=0.15,
                k2=0.02,
                p1=-0.001,
                p2=0.001,
            ),
        ),
    )

    rows: list[tuple[str, object, object]] = []
    for name, camera in cameras:
        rows.extend(evaluate_camera(name, camera, width=width, height=height, stride=stride))

    sampled_count = len(sampled_output_coordinates(width, height, stride)[0])
    identity_row_window = next(
        metrics
        for camera_name, _trace_metrics, metrics in rows
        if camera_name == "identity" and metrics.policy == "row_window"
    )
    full_valid_outputs = max(0, (width - 1) * (height - 1))
    estimated_frame_bytes = round(
        identity_row_window.ddr_read_bytes
        / identity_row_window.output_requests
        * full_valid_outputs
    )
    estimated_bandwidth_bps = estimated_frame_bytes * 60
    lines = [
        "# Pixel Fetch Cache Summary",
        "",
        "This report is a deterministic logical-pixel model estimate, not a board measurement.",
        "It uses RGB888 (3 bytes per logical source pixel), a 1280×720 frame, raster stride 8,",
        "and every border coordinate. DDR byte packing, controller scheduling, and PHY overhead",
        "are intentionally outside this pre-study.",
        "",
        f"- sampled output coordinates: `{sampled_count}`",
        f"- image size: `{width}×{height}`",
        f"- raster stride: `{stride}`",
        "- valid source coordinates use the four-neighbor policy `0 <= x0 < width-1` and `0 <= y0 < height-1`.",
        "",
        "## First RTL cache candidate",
        "",
        "The first candidate for RTL prototyping is `row_window`: an aligned 4×2 pixel region,",
        "burst length 4, and 8 logical RGB888 pixels of modeled capacity. Based on the sampled",
        f"identity trace, the proportional full-frame estimate is `{estimated_frame_bytes}` bytes/frame",
        f"or `{estimated_bandwidth_bps}` bytes/s at 60 fps. This is an extrapolated model estimate,",
        "not a board measurement; the sparse trace and one-region policy must be re-evaluated with",
        "a full raster trace before freezing DDR bandwidth claims.",
        "",
        "| camera | policy | output requests | source pixel requests | cache hit rate | DDR read bytes | DDR bursts | average burst length | cache capacity (pixels) |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for camera_name, _trace_metrics, metrics in rows:
        lines.append(
            "| "
            f"{camera_name} | {metrics.policy} | {metrics.output_requests} | "
            f"{metrics.source_pixel_requests} | {metrics.cache_hit_rate:.6f} | "
            f"{metrics.ddr_read_bytes} | {metrics.ddr_bursts} | "
            f"{metrics.average_burst_length:.6f} | {metrics.cache_capacity_pixels} |"
        )

    lines.extend(
        (
            "",
            "## Interpretation",
            "",
            "`no_cache` is a lower-complexity traffic baseline with no reuse. `row_window` and",
            "`tile_16x4` load one aligned in-bounds region on a miss and retain only that region.",
            "The estimates are intended to choose a first cache architecture before DDR3 and",
            "board measurements are available.",
            "",
        )
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(build_report() + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
