"""Render planar pose-correction references with synthetic camera intrinsics."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

try:
    import cv2 as cv
    import numpy as np
except ImportError as exc:
    raise SystemExit("Install host/requirements.txt before rendering a homography reference") from exc

from render_rotation_reference import angle_tag, make_checkerboard, read_image, sha256_file, write_png
from planar_geometry import homography_from_board_poses


DEFAULT_ANGLES = (-20.0, -10.0, 0.0, 10.0, 20.0)


def finite_float(value: str) -> float:
    try:
        number = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("value must be numeric") from exc
    if not math.isfinite(number):
        raise argparse.ArgumentTypeError("value must be finite")
    return number


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be a positive integer")
    return number


def positive_float(value: str) -> float:
    number = finite_float(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return number


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="optional ideal/undistorted reference-view image")
    parser.add_argument("--out", type=Path, default=Path("host/pose/output"), help="output directory")
    parser.add_argument("--angles-deg", type=finite_float, nargs="+", default=DEFAULT_ANGLES,
                        help="pose rotation angle list; default: -20 -10 0 10 20")
    parser.add_argument("--axes", choices=("x", "y", "z"), nargs="+", default=("x", "y"),
                        help="camera-coordinate axes to tilt around; default: x y")
    parser.add_argument("--width", type=positive_int, default=1280, help="synthetic frame width")
    parser.add_argument("--height", type=positive_int, default=720, help="synthetic frame height")
    parser.add_argument("--square-px", type=positive_int, default=64, help="synthetic checker square size")
    parser.add_argument("--fx", type=positive_float, default=900.0, help="synthetic focal length X in pixels")
    parser.add_argument("--fy", type=positive_float, default=900.0, help="synthetic focal length Y in pixels")
    parser.add_argument("--cx", type=finite_float, help="principal point X; default image center")
    parser.add_argument("--cy", type=finite_float, help="principal point Y; default image center")
    parser.add_argument("--plane-distance-mm", type=positive_float, default=1000.0,
                        help="reference plane distance from camera")
    parser.add_argument("--translation-mm", type=finite_float, nargs=3, default=(0.0, 0.0, 0.0),
                        metavar=("TX", "TY", "TZ"), help="additional board-plane translation per pose")
    return parser.parse_args()


def rotation_matrix(axis: str, angle_deg: float) -> np.ndarray:
    theta = math.radians(angle_deg)
    c, s = math.cos(theta), math.sin(theta)
    if axis == "x":
        return np.asarray([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)
    if axis == "y":
        return np.asarray([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)
    return np.asarray([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def build_output_to_source_homography(
    camera_matrix: np.ndarray,
    plane_distance_mm: float,
    axis: str,
    angle_deg: float,
    translation_mm: tuple[float, float, float],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Map reference-view ideal pixels to current-view source pixels."""
    reference_rotation = np.eye(3, dtype=np.float64)
    reference_translation = np.asarray([0.0, 0.0, plane_distance_mm], dtype=np.float64)
    current_rotation = rotation_matrix(axis, angle_deg)
    current_translation = reference_translation + np.asarray(translation_mm, dtype=np.float64)

    homography = homography_from_board_poses(
        camera_matrix,
        reference_rotation,
        reference_translation,
        current_rotation,
        current_translation,
    )
    return homography, current_rotation, current_translation


def homography_maps(
    width: int, height: int, homography: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    output_x, output_y = np.meshgrid(
        np.arange(width, dtype=np.float64), np.arange(height, dtype=np.float64)
    )
    denominator = (
        homography[2, 0] * output_x
        + homography[2, 1] * output_y
        + homography[2, 2]
    )
    valid_denominator = np.isfinite(denominator) & (np.abs(denominator) > 1e-12)
    safe_denominator = np.where(valid_denominator, denominator, 1.0)
    source_x = (
        homography[0, 0] * output_x
        + homography[0, 1] * output_y
        + homography[0, 2]
    ) / safe_denominator
    source_y = (
        homography[1, 0] * output_x
        + homography[1, 1] * output_y
        + homography[1, 2]
    ) / safe_denominator
    source_x = source_x.astype(np.float32)
    source_y = source_y.astype(np.float32)
    valid = (
        valid_denominator
        & np.isfinite(source_x) & np.isfinite(source_y)
        & (source_x >= 0.0) & (source_y >= 0.0)
        & (source_x < width - 1) & (source_y < height - 1)
    )
    return source_x, source_y, valid


def render_homography(
    source: np.ndarray, homography: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    height, width = source.shape[:2]
    map_x, map_y, valid = homography_maps(width, height, homography)
    rendered = cv.remap(
        source, map_x, map_y, cv.INTER_LINEAR,
        borderMode=cv.BORDER_CONSTANT, borderValue=(0, 0, 0),
    )
    rendered[~valid] = 0
    return rendered, valid.astype(np.uint8) * 255


def main() -> int:
    args = parse_args()
    input_path = args.input.resolve() if args.input else None
    try:
        source = read_image(input_path) if input_path else make_checkerboard(
            args.width, args.height, args.square_px
        )
    except (OSError, ValueError, cv.error) as exc:
        raise SystemExit(str(exc)) from exc

    height, width = source.shape[:2]
    cx = (width - 1) / 2.0 if args.cx is None else args.cx
    cy = (height - 1) / 2.0 if args.cy is None else args.cy
    camera_matrix = np.asarray(
        [[args.fx, 0.0, cx], [0.0, args.fy, cy], [0.0, 0.0, 1.0]],
        dtype=np.float64,
    )
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    source_hash = sha256_file(input_path) if input_path else None
    outputs = []
    seen = set()
    for axis in args.axes:
        for angle in args.angles_deg:
            key = (axis, angle)
            if key in seen:
                continue
            seen.add(key)
            homography, rotation, translation = build_output_to_source_homography(
                camera_matrix,
                args.plane_distance_mm,
                axis,
                angle,
                tuple(args.translation_mm),
            )
            rendered, mask = render_homography(source, homography)
            tag = f"{axis}_{angle_tag(angle)}"
            image_name, mask_name = f"homography_{tag}.png", f"homography_{tag}_valid_mask.png"
            write_png(out_dir / image_name, rendered)
            write_png(out_dir / mask_name, mask)
            outputs.append({
                "axis": axis,
                "angle_deg": angle,
                "image": image_name,
                "valid_mask": mask_name,
                "output_to_source_homography": homography.tolist(),
                "board_to_camera_rotation": rotation.tolist(),
                "board_to_camera_translation_mm": translation.tolist(),
                "valid_four_neighbor_pixels": int(np.count_nonzero(mask)),
                "invalid_pixels": int(mask.size - np.count_nonzero(mask)),
            })

    metadata = {
        "schema": "pango-planar-homography-reference-v1",
        "input_file": str(input_path) if input_path else "generated_synthetic_checkerboard",
        "input_sha256": source_hash,
        "image_size": [width, height],
        "opencv_version": cv.__version__,
        "camera_matrix": camera_matrix.tolist(),
        "intrinsics_source": "synthetic command-line defaults or explicit pixel values; not camera calibrated",
        "reference_plane_distance_mm": args.plane_distance_mm,
        "additional_plane_translation_mm": list(args.translation_mm),
        "coordinate_convention": "OpenCV camera coordinates; x right, y down, z forward; board origin at image center",
        "mapping": "ideal reference output pixel -> current ideal source pixel via planar homography",
        "interpolation": "OpenCV INTER_LINEAR",
        "outside_four_neighbor_policy": "black; all four source neighbors must be in frame",
        "outputs": outputs,
        "limitations": [
            "This synthetic reference does not include lens distortion.",
            "A single planar homography does not correct parallax across a translated 3D scene.",
            "Synthetic intrinsics and pose are for coordinate and crop development, not accuracy claims.",
        ],
    }
    (out_dir / "homography_reference.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Saved {len(outputs)} planar homography references in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
