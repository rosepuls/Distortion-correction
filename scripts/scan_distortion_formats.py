"""Select a narrowed distortion-core format from measured fixed-point error.

The scan deliberately uses the same integer-only candidate path that feeds
the optimized RTL.  It writes a report even when no candidate qualifies, so
the next candidate can be widened from measured evidence rather than guesswork.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "software"))

import bitaccurate_distortion as model


MAX_ERROR_PIXELS = 1.0 / 16.0
MEAN_ERROR_PIXELS = 1.0 / 64.0

CAMERAS = {
    "identity": dict(fx=900.0, fy=900.0, cx=639.5, cy=359.5),
    "barrel": dict(
        fx=900.0,
        fy=900.0,
        cx=639.5,
        cy=359.5,
        k1=-0.25,
        k2=0.05,
        p1=0.001,
        p2=-0.001,
    ),
    "pincushion": dict(
        fx=900.0,
        fy=900.0,
        cx=639.5,
        cy=359.5,
        k1=0.15,
        k2=0.02,
        p1=-0.001,
        p2=0.001,
    ),
}

CANDIDATES = (
    (
        "narrow-q12-q22",
        model.InternalFormat(25, 12, 24, 22, 26, 22, 24, 20, 28, 22, 26, 22, 26, 22, 25, 12),
    ),
    (
        "medium-q12-q24",
        model.InternalFormat(25, 12, 26, 24, 28, 24, 26, 22, 30, 24, 28, 24, 28, 24, 25, 12),
    ),
    (
        "wide-q14-q24",
        model.InternalFormat(27, 14, 26, 24, 28, 24, 26, 22, 30, 24, 28, 24, 28, 24, 27, 14),
    ),
)

Q18_RTL_FORMAT = model.InternalFormat(
    centered_width=23, centered_frac_bits=12,
    inverse_width=26, inverse_frac_bits=24,
    normalized_width=20, normalized_frac_bits=18,
    coefficient_width=20, coefficient_frac_bits=18,
    radius_width=20, radius_frac_bits=18,
    radial_width=21, radial_frac_bits=18,
    distorted_width=21, distorted_frac_bits=18,
    focal_width=24, focal_frac_bits=12,
)


def _format_description(internal_format: model.InternalFormat) -> str:
    return (
        f"centered S{internal_format.centered_width}.Q{internal_format.centered_frac_bits}; "
        f"inverse S{internal_format.inverse_width}.Q{internal_format.inverse_frac_bits}; "
        f"normalized S{internal_format.normalized_width}.Q{internal_format.normalized_frac_bits}; "
        f"coefficient S{internal_format.coefficient_width}.Q{internal_format.coefficient_frac_bits}; "
        f"radius S{internal_format.radius_width}.Q{internal_format.radius_frac_bits}; "
        f"radial S{internal_format.radial_width}.Q{internal_format.radial_frac_bits}; "
        f"distorted S{internal_format.distorted_width}.Q{internal_format.distorted_frac_bits}; "
        f"focal S{internal_format.focal_width}.Q{internal_format.focal_frac_bits}"
    )


def _qualifies(metrics: model.CandidateMetrics) -> bool:
    return (
        metrics.max_error_pixels <= MAX_ERROR_PIXELS
        and metrics.mean_error_pixels <= MEAN_ERROR_PIXELS
        and metrics.coord_valid_mismatches == 0
    )


def scan(width: int, height: int, stride: int) -> tuple[list[tuple[str, str, model.CandidateMetrics]], str | None]:
    """Return all candidate/camera measurements and the first valid candidate."""

    rows: list[tuple[str, str, model.CandidateMetrics]] = []
    selected: str | None = None
    for candidate_name, internal_format in CANDIDATES:
        candidate_metrics = []
        for camera_name, parameters in CAMERAS.items():
            metrics = model.evaluate_internal_format(
                width,
                height,
                model.FixedPointCameraModel.from_parameters(**parameters),
                internal_format,
                stride=stride,
            )
            rows.append((candidate_name, camera_name, metrics))
            candidate_metrics.append(metrics)
        if selected is None and all(_qualifies(metrics) for metrics in candidate_metrics):
            selected = candidate_name
    return rows, selected


def render_report(
    width: int,
    height: int,
    stride: int,
    rows: list[tuple[str, str, model.CandidateMetrics]],
    selected: str | None,
) -> str:
    """Render the deterministic Markdown evidence table."""

    lines = [
        "# Distortion Internal Format Scan",
        "",
        f"Frame: {width}x{height}; raster stride: {stride}; every border pixel included.",
        f"Limits: max error <= {MAX_ERROR_PIXELS:.6f} pixel; mean error <= {MEAN_ERROR_PIXELS:.6f} pixel; coord_valid mismatches = 0.",
        "",
        "| Candidate | Camera | Max error (pixel) | Mean error (pixel) | RMSE (pixel) | coord_valid mismatches | Selected |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    for candidate_name, camera_name, metrics in rows:
        selected_mark = "yes" if candidate_name == selected else ""
        lines.append(
            "| "
            f"{candidate_name} | {camera_name} | {metrics.max_error_pixels:.9f} | "
            f"{metrics.mean_error_pixels:.9f} | {metrics.rmse_pixels:.9f} | "
            f"{metrics.coord_valid_mismatches} | {selected_mark} |"
        )
    lines.extend(("", "## Candidate formats", ""))
    for candidate_name, internal_format in CANDIDATES:
        lines.append(f"- `{candidate_name}`: {_format_description(internal_format)}")
    lines.extend(("", "## Selection", ""))
    if selected is None:
        lines.append("No candidate meets every acceptance limit.")
    else:
        selected_format = dict(CANDIDATES)[selected]
        lines.append(f"SELECTED_FORMAT = `{selected}`")
        lines.append("")
        lines.append(_format_description(selected_format))
    lines.append("")
    return "\n".join(lines)


def write_q18_vectors(path: Path, width: int = 1280, height: int = 720) -> None:
    """Write deterministic Q18 RTL comparison vectors for frame and boundary cases."""

    points = ((0, 0, 1, 0), (width - 1, 0, 0, 0), (0, height - 1, 0, 0),
              (width - 1, height - 1, 0, 1), (width // 2, height // 2, 0, 0))
    vector_cameras = list(CAMERAS.items()) + [
        (
            "overflow_guard",
            dict(fx=900.0, fy=900.0, cx=4095.0, cy=359.5),
        ),
        (
            "image_regression",
            dict(
                fx=180.0,
                fy=180.0,
                cx=127.5,
                cy=95.5,
                k1=-0.25,
                k2=0.05,
                p1=0.001,
                p2=-0.001,
            ),
        ),
    ]
    lines = ["# u v sof eol cfg_id src_x_q19 src_y_q19 x0 y0 dx_q16 dy_q16 coord_valid"]
    for cfg_id, (_, parameters) in enumerate(vector_cameras):
        camera = model.FixedPointCameraModel.from_parameters(**parameters)
        for u, v, sof, eol in points:
            source_x, source_y = model.source_coordinates_horner_quantized(
                [u], [v], camera, Q18_RTL_FORMAT
            )
            x0, y0, dx, dy, valid = model.split_source_coordinates(
                source_x, source_y, width=width, height=height
            )
            lines.append(
                f"{u} {v} {sof} {eol} {cfg_id} {int(source_x[0])} {int(source_y[0])} "
                f"{int(x0[0])} {int(y0[0])} {int(dx[0])} {int(dy[0])} {int(valid[0])}"
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Markdown report path")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--stride", type=int, default=8)
    parser.add_argument("--vectors", type=Path, help="optional Q18 RTL golden-vector output")
    arguments = parser.parse_args()
    if arguments.width <= 1 or arguments.height <= 1 or arguments.stride <= 0:
        parser.error("width/height must be greater than one and stride must be positive")

    rows, selected = scan(arguments.width, arguments.height, arguments.stride)
    report = render_report(arguments.width, arguments.height, arguments.stride, rows, selected)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(report, encoding="utf-8")
    if arguments.vectors is not None:
        write_q18_vectors(arguments.vectors)
    print(f"Wrote {arguments.output}")
    if selected is None:
        print("No format satisfied the error and validity gates.", file=sys.stderr)
        return 1
    print(f"Selected {selected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
