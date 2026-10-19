"""Calibrate the final 1280x720 camera mode from raw chessboard photographs."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

try:
    import cv2 as cv
    import numpy as np
except ImportError as exc:
    raise SystemExit("Install host/requirements.txt before running calibration") from exc


IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".tif", ".tiff"}


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def positive_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return number


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, required=True, help="raw camera photograph directory")
    parser.add_argument("--cols", type=positive_int, required=True, help="chessboard inner corners across")
    parser.add_argument("--rows", type=positive_int, required=True, help="chessboard inner corners down")
    parser.add_argument("--square-mm", type=positive_float, required=True, help="physical square edge")
    parser.add_argument("--out", type=Path, required=True, help="output directory for calibration.json")
    parser.add_argument("--width", type=positive_int, default=1280)
    parser.add_argument("--height", type=positive_int, default=720)
    parser.add_argument("--min-views", type=positive_int, default=20)
    parser.add_argument("--camera-id", default="", help="camera model or serial number")
    parser.add_argument("--lens-notes", default="", help="lens, focus and aperture notes")
    return parser.parse_args()


def read_image(path: Path):
    # imdecode handles non-ASCII Windows paths that imread may reject.
    encoded = np.fromfile(str(path), dtype=np.uint8)
    if encoded.size == 0:
        return None
    return cv.imdecode(encoded, cv.IMREAD_COLOR)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def k3_map_difference(camera_matrix, coefficients, image_size):
    full = np.asarray(coefficients, dtype=np.float64).reshape(-1)
    if full.size < 5:
        return {"max_px": 0.0, "p95_px": 0.0}
    four = full.copy()
    four[4] = 0.0
    full_x, full_y = cv.initUndistortRectifyMap(
        camera_matrix, full, None, camera_matrix, image_size, cv.CV_32FC1
    )
    four_x, four_y = cv.initUndistortRectifyMap(
        camera_matrix, four, None, camera_matrix, image_size, cv.CV_32FC1
    )
    delta = np.hypot(full_x - four_x, full_y - four_y)
    return {"max_px": float(np.max(delta)), "p95_px": float(np.percentile(delta, 95))}


def main() -> int:
    args = parse_args()
    image_dir = args.images.resolve()
    out_dir = args.out.resolve()
    if not image_dir.is_dir():
        raise SystemExit(f"Image directory does not exist: {image_dir}")
    paths = sorted(
        (
            path for path in image_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
            and out_dir not in path.parents
        ),
        key=lambda path: str(path).casefold(),
    )
    if not paths:
        raise SystemExit(f"No supported photographs found in {image_dir}")

    object_grid = np.zeros((args.cols * args.rows, 3), np.float32)
    object_grid[:, :2] = (
        np.mgrid[0:args.cols, 0:args.rows].T.reshape(-1, 2) * args.square_mm
    )
    criteria = (cv.TERM_CRITERIA_EPS + cv.TERM_CRITERIA_MAX_ITER, 40, 0.001)
    detection_flags = cv.CALIB_CB_ADAPTIVE_THRESH + cv.CALIB_CB_NORMALIZE_IMAGE
    object_points = []
    image_points = []
    accepted = []
    rejected = []

    for path in paths:
        relative = str(path.relative_to(image_dir))
        try:
            image = read_image(path)
        except (OSError, ValueError, cv.error) as exc:
            rejected.append({"file": relative, "reason": f"read_error: {exc}"})
            continue
        if image is None:
            rejected.append({"file": relative, "reason": "image_decode_failed"})
            continue
        height, width = image.shape[:2]
        if (width, height) != (args.width, args.height):
            rejected.append({"file": relative, "reason": f"resolution_{width}x{height}"})
            continue
        gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY)
        found, corners = cv.findChessboardCorners(
            gray, (args.cols, args.rows), detection_flags
        )
        if not found:
            rejected.append({"file": relative, "reason": "inner_corners_not_found"})
            continue
        refined = cv.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
        object_points.append(object_grid.copy())
        image_points.append(refined)
        accepted.append({"file": relative, "sha256": sha256_file(path)})

    if len(accepted) < args.min_views:
        raise SystemExit(
            f"Only {len(accepted)} valid views; need at least {args.min_views}. "
            f"Rejected: {json.dumps(rejected, ensure_ascii=False)}"
        )

    image_size = (args.width, args.height)
    try:
        rms, camera_matrix, coefficients, rvecs, tvecs = cv.calibrateCamera(
            object_points, image_points, image_size, None, None
        )
    except cv.error as exc:
        raise SystemExit(f"OpenCV calibration failed: {exc}") from exc
    if not np.isfinite(camera_matrix).all() or not np.isfinite(coefficients).all():
        raise SystemExit("Calibration produced non-finite parameters")

    for item, obj, measured, rotation, translation in zip(
        accepted, object_points, image_points, rvecs, tvecs, strict=True
    ):
        projected, _ = cv.projectPoints(
            obj, rotation, translation, camera_matrix, coefficients
        )
        distance = np.linalg.norm(
            projected.reshape(-1, 2) - measured.reshape(-1, 2), axis=1
        )
        item["reprojection_rms_px"] = float(np.sqrt(np.mean(distance * distance)))
        item["reprojection_max_px"] = float(np.max(distance))

    flat_coefficients = coefficients.reshape(-1).tolist()
    if len(flat_coefficients) < 5:
        raise SystemExit("Expected OpenCV's k1, k2, p1, p2, k3 distortion model")
    result = {
        "schema": "pango-camera-calibration-v1",
        "image_size": [args.width, args.height],
        "camera_id": args.camera_id,
        "lens_notes": args.lens_notes,
        "images_directory": str(image_dir),
        "chessboard": {
            "inner_corners": [args.cols, args.rows],
            "square_edge_mm": args.square_mm,
        },
        "opencv_version": cv.__version__,
        "camera_matrix": camera_matrix.tolist(),
        "distortion_coefficients": flat_coefficients,
        "distortion_order": ["k1", "k2", "p1", "p2", "k3"],
        "global_rms_px": float(rms),
        "k3_zeroed_map_difference": k3_map_difference(
            camera_matrix, coefficients, image_size
        ),
        "accepted": accepted,
        "rejected": rejected,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    output = out_dir / "calibration.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {output}; {len(accepted)} valid views, {len(rejected)} rejected")
    print(f"Global RMS: {rms:.4f} px; k3 map delta: {result['k3_zeroed_map_difference']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
