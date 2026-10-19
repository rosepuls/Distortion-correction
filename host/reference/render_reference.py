"""Render a full-frame undistortion reference from real calibration data."""

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
    raise SystemExit("Install host/requirements.txt before rendering a reference") from exc


def parse_alpha(value: str) -> float:
    alpha = float(value)
    if not math.isfinite(alpha) or not 0.0 <= alpha <= 1.0:
        raise argparse.ArgumentTypeError("alpha must be between 0 and 1")
    return alpha


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True, help="raw 720p camera image")
    parser.add_argument("--out", type=Path, required=True, help="output directory")
    parser.add_argument("--output-matrix", choices=("input", "optimal"), default="input",
                        help="use input intrinsics by default; optimal needs a later FPGA extension")
    parser.add_argument("--alpha", type=parse_alpha, default=1.0,
                        help="field of view retained when --output-matrix optimal")
    parser.add_argument("--rgbx-hex", action="store_true",
                        help="also write one 32-bit RRGGBB00 word per pixel")
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_image(path: Path):
    encoded = np.fromfile(str(path), dtype=np.uint8)
    if encoded.size == 0:
        raise SystemExit(f"Empty image: {path}")
    image = cv.imdecode(encoded, cv.IMREAD_COLOR)
    if image is None:
        raise SystemExit(f"Cannot decode image: {path}")
    return image


def write_png(path: Path, image) -> None:
    success, encoded = cv.imencode(".png", image)
    if not success:
        raise SystemExit(f"Cannot encode PNG: {path}")
    encoded.tofile(str(path))


def write_rgbx_hex(path: Path, bgr) -> None:
    # The numeric word is RRGGBB00. A text file avoids host byte-order ambiguity.
    rgb = cv.cvtColor(bgr, cv.COLOR_BGR2RGB)
    with path.open("w", encoding="ascii", newline="\n") as output:
        for row in rgb:
            for red, green, blue in row:
                output.write(f"{int(red):02X}{int(green):02X}{int(blue):02X}00\n")


def main() -> int:
    args = parse_args()
    calibration_path = args.calibration.resolve()
    image_path = args.input.resolve()
    if not calibration_path.is_file() or not image_path.is_file():
        raise SystemExit("Calibration JSON and input image must both exist")
    calibration = json.loads(calibration_path.read_text(encoding="utf-8"))
    if calibration.get("schema") != "pango-camera-calibration-v1":
        raise SystemExit("Unsupported calibration JSON schema")
    size = tuple(calibration["image_size"])
    if size != (1280, 720):
        raise SystemExit(f"Expected final 1280x720 mode; calibration says {size}")
    camera_matrix = np.asarray(calibration["camera_matrix"], dtype=np.float64)
    coefficients = np.asarray(
        calibration["distortion_coefficients"], dtype=np.float64
    ).reshape(-1)
    if camera_matrix.shape != (3, 3) or coefficients.size < 5:
        raise SystemExit("Calibration matrix or distortion vector has the wrong shape")
    if not np.isfinite(camera_matrix).all() or not np.isfinite(coefficients).all():
        raise SystemExit("Calibration contains non-finite values")
    source = read_image(image_path)
    if (source.shape[1], source.shape[0]) != size:
        raise SystemExit(
            f"Input image is {source.shape[1]}x{source.shape[0]}, expected {size[0]}x{size[1]}"
        )

    if args.output_matrix == "input":
        new_camera_matrix = camera_matrix.copy()
        roi = (0, 0, size[0], size[1])
    else:
        new_camera_matrix, roi = cv.getOptimalNewCameraMatrix(
            camera_matrix, coefficients, size, args.alpha, size
        )
    map_x, map_y = cv.initUndistortRectifyMap(
        camera_matrix, coefficients, None, new_camera_matrix, size, cv.CV_32FC1
    )
    # The FPGA interpolator requires all four source neighbors. OpenCV can
    # interpolate a partially out-of-bounds neighborhood; force these pixels
    # black here so the software reference uses the same border policy.
    valid = (
        np.isfinite(map_x) & np.isfinite(map_y)
        & (map_x >= 0.0) & (map_y >= 0.0)
        & (map_x < size[0] - 1) & (map_y < size[1] - 1)
    )
    reference = cv.remap(
        source, map_x, map_y, cv.INTER_LINEAR,
        borderMode=cv.BORDER_CONSTANT, borderValue=(0, 0, 0),
    )
    reference[~valid] = 0
    mask = (valid.astype(np.uint8) * 255)

    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    write_png(out_dir / "undistorted.png", reference)
    write_png(out_dir / "valid_mask.png", mask)
    if args.rgbx_hex:
        write_rgbx_hex(out_dir / "undistorted_rgbx.mem", reference)

    full_map_metadata = {
        "schema": "pango-undistort-reference-v1",
        "calibration_file": str(calibration_path),
        "calibration_sha256": sha256_file(calibration_path),
        "input_file": str(image_path),
        "input_sha256": sha256_file(image_path),
        "image_size": list(size),
        "opencv_version": cv.__version__,
        "output_matrix_choice": args.output_matrix,
        "alpha": args.alpha,
        "new_camera_matrix": new_camera_matrix.tolist(),
        "valid_pixel_roi": [int(value) for value in roi],
        "valid_four_neighbor_pixels": int(valid.sum()),
        "invalid_pixels": int(valid.size - valid.sum()),
        "interpolation": "OpenCV INTER_LINEAR",
        "outside_four_neighbor_policy": "black",
        "rgbx_word_format": "RRGGBB00" if args.rgbx_hex else None,
    }
    (out_dir / "reference.json").write_text(
        json.dumps(full_map_metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Saved reference and mask in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
