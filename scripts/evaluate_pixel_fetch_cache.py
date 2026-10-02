"""Evaluate deterministic cache policies on a 1080P30 distortion raster."""

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
from cache_model import (
    NO_CACHE,
    ROW_WINDOW,
    TILE_16X4,
    CacheConfig,
    simulate_cache,
)


WIDTH = 1920
HEIGHT = 1080
FPS = 30
RASTER_STRIDE = 8
TILE_32X4_128_8WAY_SKEWED = CacheConfig(
    "tile_32x4_128_8way_skewed",
    tile_width=32,
    tile_height=4,
    burst_length=32,
    set_count=16,
    ways=8,
    pixel_bytes=4,
    burst_beats=4,
    set_hash="skewed_x_minus_y",
)
POLICIES: tuple[CacheConfig, ...] = (
    NO_CACHE,
    ROW_WINDOW,
    TILE_16X4,
    TILE_32X4_128_8WAY_SKEWED,
)


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


def raster_output_coordinates(
    width: int,
    height: int,
    *,
    full_raster: bool,
    stride: int,
) -> tuple[np.ndarray, np.ndarray]:
    if full_raster:
        output_y, output_x = np.indices((height, width), dtype=np.int64)
        return output_x.ravel(), output_y.ravel()
    return sampled_output_coordinates(width, height, stride)


def evaluate_camera(
    name: str,
    camera: FixedPointCameraModel,
    *,
    width: int = WIDTH,
    height: int = HEIGHT,
    full_raster: bool = True,
    stride: int = RASTER_STRIDE,
) -> list[tuple[str, object, object]]:
    output_x, output_y = raster_output_coordinates(
        width,
        height,
        full_raster=full_raster,
        stride=stride,
    )
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


def build_report(
    width: int = WIDTH,
    height: int = HEIGHT,
    fps: int = FPS,
    full_raster: bool = True,
    stride: int = RASTER_STRIDE,
) -> str:
    if width <= 0 or height <= 0 or fps <= 0:
        raise ValueError("width, height, and fps must be positive")
    focal_scale = width / 1280.0
    focal_length = 900.0 * focal_scale
    cameras = (
        (
            "identity",
            FixedPointCameraModel.from_parameters(
                fx=focal_length,
                fy=focal_length,
                cx=(width - 1) / 2.0,
                cy=(height - 1) / 2.0,
            ),
        ),
        (
            "barrel",
            FixedPointCameraModel.from_parameters(
                fx=focal_length,
                fy=focal_length,
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
                fx=focal_length,
                fy=focal_length,
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
        rows.extend(
            evaluate_camera(
                name,
                camera,
                width=width,
                height=height,
                full_raster=full_raster,
                stride=stride,
            )
        )

    output_count = len(
        raster_output_coordinates(
            width,
            height,
            full_raster=full_raster,
            stride=stride,
        )[0]
    )
    frame_stream_bytes = width * height * 4 * 4
    lines = [
        "# Pixel Fetch Cache Summary",
        "",
        "This report is a deterministic full-raster physical-traffic model, not a board measurement.",
        "It uses RGBX8888 source pixels, 256-bit DDR beats, set-associative Tile Cache accounting,",
        "and does not claim DDR controller or PHY efficiency.",
        "",
        f"- output coordinates evaluated: `{output_count}`",
        f"- image size: `{width}×{height}`",
        f"- frame rate: `{fps} fps`",
        f"- raster: `{'full' if full_raster else f'stride-{stride}'}`",
        "- valid source coordinates use the four-neighbor policy `0 <= x0 < width-1` and `0 <= y0 < height-1`.",
        f"- four frame-equivalent RGBX streams: `{frame_stream_bytes}` bytes/frame, `{frame_stream_bytes * fps}` bytes/s.",
        "",
        "## Cache candidates",
        "",
        "`tile_32x4_128_8way_skewed` is the 1080P30 RTL candidate. Its physical source traffic is measured",
        "directly from the complete raster rather than extrapolated from stride sampling.",
        "",
        "| camera | policy | output requests | source pixel requests | cache hit rate | DDR read bytes | DDR bursts | DDR beats | average burst length (pixels) | average burst (beats) | cache capacity (pixels) |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for camera_name, _trace_metrics, metrics in rows:
        lines.append(
            "| "
            f"{camera_name} | {metrics.policy} | {metrics.output_requests} | "
            f"{metrics.source_pixel_requests} | {metrics.cache_hit_rate:.6f} | "
            f"{metrics.ddr_read_bytes} | {metrics.ddr_bursts} | "
            f"{metrics.ddr_beats} | {metrics.average_burst_length:.6f} | "
            f"{metrics.average_burst_beats:.6f} | "
            f"{metrics.cache_capacity_pixels} |"
        )

    lines.extend(
        (
            "",
            "## Interpretation",
            "",
            "`no_cache` is a lower-complexity traffic baseline with no reuse. The candidate cache",
            "loads one aligned 32×4 RGBX region on a miss and retains eight ways per set.",
            "DDR controller scheduling, read/write arbitration, and board measurements remain separate.",
            "",
        )
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--width", type=int, default=WIDTH)
    parser.add_argument("--height", type=int, default=HEIGHT)
    parser.add_argument("--fps", type=int, default=FPS)
    parser.add_argument("--stride", type=int, default=RASTER_STRIDE)
    parser.add_argument("--sampled", action="store_true")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        build_report(
            width=args.width,
            height=args.height,
            fps=args.fps,
            full_raster=not args.sampled,
            stride=args.stride,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
