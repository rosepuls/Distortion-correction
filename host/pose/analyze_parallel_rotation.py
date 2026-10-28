"""Estimate image-plane rotation coefficients from a labeled checkerboard sweep."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np


SCALE_NUMERATOR = 1 << 16
SCALE_DENOMINATOR = 1 << 30
SIGNED32_MIN = -(1 << 31)
SIGNED32_MAX = (1 << 31) - 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--images",
        type=Path,
        default=Path("../picture/Calibration/parallel angle"),
        help="folder containing PNGs named by their nominal angle in degrees",
    )
    parser.add_argument(
        "--calibration",
        type=Path,
        default=Path("host/calibration/output/calibration.json"),
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("host/pose/output/parallel_rotation_coefficients.json"),
    )
    parser.add_argument("--cols", type=int, default=9, help="checkerboard inner corners")
    parser.add_argument("--rows", type=int, default=6, help="checkerboard inner corners")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    return parser.parse_args()


def load_calibration(path: Path) -> tuple[np.ndarray, np.ndarray]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if tuple(data.get("image_size", ())) != (1280, 720):
        raise ValueError("Calibration image_size must be 1280x720")
    return (
        np.asarray(data["camera_matrix"], dtype=np.float64),
        np.asarray(data["distortion_coefficients"], dtype=np.float64),
    )


def detect_grid(path: Path, cols: int, rows: int, K: np.ndarray, D: np.ndarray,
                width: int, height: int) -> tuple[np.ndarray, float, float]:
    encoded = np.fromfile(str(path), dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_GRAYSCALE) if encoded.size else None
    if image is None:
        raise ValueError(f"Could not read image: {path}")
    if image.shape != (height, width):
        raise ValueError(f"{path.name}: expected {width}x{height}, got {image.shape[1]}x{image.shape[0]}")
    found, corners = cv2.findChessboardCornersSB(
        image,
        (cols, rows),
        flags=cv2.CALIB_CB_EXHAUSTIVE | cv2.CALIB_CB_ACCURACY,
    )
    if not found:
        raise ValueError(f"{path.name}: could not detect the full {cols}x{rows} inner-corner grid")

    # Measure directions after lens undistortion, matching the ideal-pixel
    # coordinate space used before the FPGA Brown mapper.
    grid = cv2.undistortPoints(corners.reshape(-1, 1, 2), K, D, P=K)
    grid = grid.reshape(rows, cols, 2)
    row_vectors = np.asarray([grid[row, cols - 2] - grid[row, 1]
                              for row in range(1, rows - 1)])
    row_angles = np.arctan2(row_vectors[:, 1], row_vectors[:, 0])
    doubled_mean = np.mean(np.exp(2j * row_angles))
    angle = math.degrees(0.5 * math.atan2(doubled_mean.imag, doubled_mean.real))
    angle = ((angle + 90.0) % 180.0) - 90.0
    spread = math.degrees(float(np.ptp(row_angles)))
    return grid, angle, spread


def quantize(h: np.ndarray) -> dict:
    scales = np.asarray(
        [[SCALE_NUMERATOR] * 3] * 2 + [[SCALE_DENOMINATOR] * 3],
        dtype=np.float64,
    )
    raw = np.rint(h * scales)
    if not np.isfinite(raw).all() or np.any(raw < SIGNED32_MIN) or np.any(raw > SIGNED32_MAX):
        raise ValueError("Rotation homography exceeds signed 32-bit Stage 8 coefficient range")
    rows = raw.astype(np.int64).tolist()
    words = [value for row in rows for value in row]
    return {
        "numerator_format": "signed Q16.16",
        "denominator_format": "signed Q2.30",
        "rounding": "nearest integer, ties to even",
        "integer_rows": rows,
        "two_complement_hex_rows": [
            [f"0x{value & 0xffffffff:08X}" for value in row] for row in rows
        ],
        "cfg_words_288bit_hex": "0x" + "".join(
            f"{value & 0xffffffff:08X}" for value in reversed(words)
        ),
        "cfg_words_note": "word 0 h00 is bits [31:0]; this is bus packing, not UART byte order",
    }


def rotation_homography(theta_deg: float, cx: float, cy: float) -> np.ndarray:
    """Output-reference ideal pixel -> current-source ideal pixel mapping."""
    theta = math.radians(theta_deg)
    cosine, sine = math.cos(theta), math.sin(theta)
    return np.asarray([
        [cosine, -sine, cx * (1.0 - cosine) + sine * cy],
        [sine, cosine, cy * (1.0 - cosine) - sine * cx],
        [0.0, 0.0, 1.0],
    ], dtype=np.float64)


def similarity_diagnostics(reference: np.ndarray, current: np.ndarray) -> tuple[float, float, float]:
    """Return center drift, fitted scale, and residual RMS for board corners."""
    ref = reference.reshape(-1, 2)
    cur = current.reshape(-1, 2)
    x = ref - ref.mean(axis=0)
    y = cur - cur.mean(axis=0)
    u, _, vt = np.linalg.svd(x.T @ y)
    rotation = u @ np.diag([1.0, np.linalg.det(u @ vt)]) @ vt
    scale = float(np.sum((x @ rotation) * y) / np.sum(x * x))
    fitted = scale * (x @ rotation) + cur.mean(axis=0)
    rms = float(np.sqrt(np.mean(np.sum((fitted - cur) ** 2, axis=1))))
    drift = float(np.linalg.norm(cur.mean(axis=0) - ref.mean(axis=0)))
    return drift, scale, rms


def main() -> None:
    args = parse_args()
    K, D = load_calibration(args.calibration)
    cx, cy = float(K[0, 2]), float(K[1, 2])
    files = []
    for path in args.images.glob("*.png"):
        try:
            nominal = float(path.stem)
        except ValueError:
            continue
        grid, raw_angle, spread = detect_grid(
            path, args.cols, args.rows, K, D, args.width, args.height
        )
        files.append((nominal, path, grid, raw_angle, spread))
    files.sort(key=lambda item: item[0])
    if not files:
        raise ValueError(f"No angle-named PNG files found in {args.images}")

    # findChessboardCornersSB reports the grid orientation modulo 180 degrees.
    # Unwrap in filename order, choosing the continuous branch across the sweep.
    unwrapped = []
    for _, _, _, raw_angle, _ in files:
        value = raw_angle
        if unwrapped:
            while value - unwrapped[-1] > 90.0:
                value -= 180.0
            while value - unwrapped[-1] < -90.0:
                value += 180.0
        unwrapped.append(value)
    baseline = unwrapped[0]
    reference_grid = files[0][2]

    image_records = []
    angle_pairs = []
    for (nominal, path, grid, _, spread), absolute_angle in zip(files, unwrapped):
        relative_angle = absolute_angle - baseline
        homography = rotation_homography(relative_angle, cx, cy)
        packed = quantize(homography)

        # Orient the detected lattice continuously so geometric diagnostics
        # compare matching physical checkerboard corners.
        branch_delta = int(round((absolute_angle - files[0][3]) / 180.0))
        oriented_grid = grid[::-1, ::-1, :] if branch_delta % 2 else grid
        drift, scale, fit_rms = similarity_diagnostics(reference_grid, oriented_grid)

        image_records.append({
            "file": path.name,
            "nominal_angle_deg": nominal,
            "detected_absolute_grid_angle_deg": absolute_angle,
            "relative_grid_angle_deg": relative_angle,
            "angle_spread_across_middle_rows_deg": spread,
            "rotation_center_xy_ideal_pixels": [cx, cy],
            "mapping": "reference output ideal pixel -> current source ideal pixel",
            "homography_output_to_source_float": homography.tolist(),
            "stage8_fixed_coefficients": packed,
            "board_plane_diagnostics": {
                "corner_center_drift_from_reference_px": drift,
                "similarity_scale_current_over_reference": scale,
                "similarity_fit_rms_px": fit_rms,
                "note": "Nonzero residual indicates board-plane perspective/translation/scale beyond pure rotation.",
            },
        })
        angle_pairs.append((nominal, relative_angle))

    x = np.asarray([pair[0] for pair in angle_pairs], dtype=np.float64)
    y = np.asarray([pair[1] for pair in angle_pairs], dtype=np.float64)
    if len(x) >= 2:
        slope, intercept = np.polyfit(x, y, 1)
        residual = y - (slope * x + intercept)
        fit = {
            "relative_angle_vs_nominal_fit": {
                "slope_deg_per_nominal_deg": float(slope),
                "intercept_deg": float(intercept),
                "rms_residual_deg": float(np.sqrt(np.mean(residual ** 2))),
                "maximum_absolute_residual_deg": float(np.max(np.abs(residual))),
            }
        }
    else:
        fit = {}

    result = {
        "schema": "pango-parallel-board-image-rotation-v1",
        "image_size": [args.width, args.height],
        "reference_image": files[0][1].name,
        "detected_image_count": len(image_records),
        "checkerboard_inner_corners": [args.cols, args.rows],
        "calibration_file": str(args.calibration),
        "camera_matrix": K.tolist(),
        "distortion_coefficients": D.tolist(),
        "rotation_center_xy_ideal_pixels": [cx, cy],
        "coordinate_convention": {
            "image_x_right_y_down": True,
            "relative_angle_sign": "negative means the board x-axis moved counterclockwise in the image",
            "stage8_homography": "output reference ideal pixels -> current source ideal pixels",
            "stage8_coefficients": "row-major h00..h22; rows 0-1 signed Q16.16; row 2 signed Q2.30",
        },
        "method": "Detect 9x6 checkerboard corners, undistort with the supplied calibration, estimate the long grid-axis orientation from central rows, unwrap its 180-degree ambiguity in filename order, and subtract the first image angle.",
        "interpretation": "The primary coefficients model a pure image-plane rotation about the calibrated principal point. Board-plane diagnostics quantify extra translation, scale, and perspective visible in this fixed-camera board sweep.",
        **fit,
        "images": image_records,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(image_records)} image coefficient records to {args.out}")
    if fit:
        f = fit["relative_angle_vs_nominal_fit"]
        print(
            "Measured-relative-angle fit: "
            f"{f['slope_deg_per_nominal_deg']:.5f} * nominal "
            f"+ {f['intercept_deg']:.4f} deg; "
            f"RMS {f['rms_residual_deg']:.3f} deg"
        )
    for record in image_records:
        print(
            f"{record['file']:>7}: relative={record['relative_grid_angle_deg']:+8.3f} deg; "
            f"Q16/Q30={record['stage8_fixed_coefficients']['cfg_words_288bit_hex']}"
        )


if __name__ == "__main__":
    main()
