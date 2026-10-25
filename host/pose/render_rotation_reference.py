"""Render output-to-source image-plane rotation references for FPGA work."""

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
    raise SystemExit("Install host/requirements.txt before rendering a rotation reference") from exc


DEFAULT_ANGLES = (0.0, -10.0, 10.0, -20.0, 20.0)


def finite_angle(value: str) -> float:
    try:
        angle = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("angle must be a number of degrees") from exc
    if not math.isfinite(angle):
        raise argparse.ArgumentTypeError("angle must be finite")
    return angle


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be a positive integer")
    return number


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="optional image; without it, generate a synthetic checkerboard")
    parser.add_argument("--out", type=Path, default=Path("host/pose/output"), help="output directory")
    parser.add_argument("--angles-deg", type=finite_angle, nargs="+", default=DEFAULT_ANGLES,
                        help="visible counterclockwise angles; default: 0 -10 10 -20 20")
    parser.add_argument("--width", type=positive_int, default=1280, help="synthetic image width")
    parser.add_argument("--height", type=positive_int, default=720, help="synthetic image height")
    parser.add_argument("--square-px", type=positive_int, default=64, help="synthetic checker square size")
    parser.add_argument("--center", type=float, nargs=2, metavar=("X", "Y"),
                        help="rotation center in pixels; default is the image pixel-center midpoint")
    return parser.parse_args()


def read_image(path: Path) -> np.ndarray:
    encoded = np.fromfile(str(path), dtype=np.uint8)
    image = cv.imdecode(encoded, cv.IMREAD_COLOR) if encoded.size else None
    if image is None:
        raise ValueError(f"Cannot decode input image: {path}")
    return image


def write_png(path: Path, image: np.ndarray) -> None:
    ok, encoded = cv.imencode(".png", image)
    if not ok:
        raise OSError(f"Cannot encode PNG: {path}")
    encoded.tofile(str(path))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def make_checkerboard(width: int, height: int, square_px: int) -> np.ndarray:
    """Create a centered 10x7 square board (9x6 inner corners)."""
    image = np.full((height, width, 3), 112, dtype=np.uint8)
    cols, rows = 10, 7
    board_width, board_height = cols * square_px, rows * square_px
    left, top = (width - board_width) // 2, (height - board_height) // 2
    if left < 0 or top < 0:
        raise ValueError("Synthetic checkerboard does not fit; reduce --square-px")
    for row in range(rows):
        for col in range(cols):
            shade = 245 if (row + col) % 2 == 0 else 12
            x0, y0 = left + col * square_px, top + row * square_px
            image[y0:y0 + square_px, x0:x0 + square_px] = shade
    cv.rectangle(image, (left, top), (left + board_width - 1, top + board_height - 1), (0, 80, 255), 2)
    cv.drawMarker(image, (width // 2, height // 2), (0, 255, 0), cv.MARKER_CROSS, 25, 2)
    cv.putText(image, "IMAGE CENTER", (width // 2 + 12, height // 2 - 10),
               cv.FONT_HERSHEY_SIMPLEX, 0.45, (0, 180, 0), 1, cv.LINE_AA)
    return image


def output_to_source_maps(
    width: int, height: int, angle_deg: float, center: tuple[float, float]
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Build maps for positive visible CCW rotation in x-right/y-down image space."""
    cx, cy = center
    theta = math.radians(angle_deg)
    cosine, sine = math.cos(theta), math.sin(theta)
    output_x, output_y = np.meshgrid(
        np.arange(width, dtype=np.float32), np.arange(height, dtype=np.float32)
    )
    dx, dy = output_x - cx, output_y - cy
    source_x = cx + cosine * dx - sine * dy
    source_y = cy + sine * dx + cosine * dy
    matrix = np.asarray(
        [
            [cosine, -sine, cx * (1.0 - cosine) + sine * cy],
            [sine, cosine, cy * (1.0 - cosine) - sine * cx],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )
    return source_x, source_y, matrix


def render_angle(
    source: np.ndarray, angle_deg: float, center: tuple[float, float]
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    height, width = source.shape[:2]
    map_x, map_y, matrix = output_to_source_maps(width, height, angle_deg, center)
    valid = (
        np.isfinite(map_x) & np.isfinite(map_y)
        & (map_x >= 0.0) & (map_y >= 0.0)
        & (map_x < width - 1) & (map_y < height - 1)
    )
    rendered = cv.remap(
        source, map_x, map_y, cv.INTER_LINEAR,
        borderMode=cv.BORDER_CONSTANT, borderValue=(0, 0, 0),
    )
    rendered[~valid] = 0
    return rendered, (valid.astype(np.uint8) * 255), matrix


def angle_tag(angle_deg: float) -> str:
    sign = "p" if angle_deg >= 0 else "m"
    number = f"{abs(angle_deg):g}".replace(".", "p")
    return f"{sign}{number}deg"


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
    if args.center is None:
        center = ((width - 1) / 2.0, (height - 1) / 2.0)
    else:
        center = (float(args.center[0]), float(args.center[1]))
        if not all(math.isfinite(value) for value in center):
            raise SystemExit("Rotation center must contain finite pixel coordinates")

    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    source_hash = sha256_file(input_path) if input_path else None
    outputs = []
    seen = set()
    for angle in args.angles_deg:
        if angle in seen:
            continue
        seen.add(angle)
        tag = angle_tag(angle)
        rendered, mask, matrix = render_angle(source, angle, center)
        image_name, mask_name = f"rotation_{tag}.png", f"rotation_{tag}_valid_mask.png"
        write_png(out_dir / image_name, rendered)
        write_png(out_dir / mask_name, mask)
        outputs.append({
            "angle_deg": angle,
            "image": image_name,
            "valid_mask": mask_name,
            "output_to_source_homography": matrix.tolist(),
            "valid_four_neighbor_pixels": int(np.count_nonzero(mask)),
            "invalid_pixels": int(mask.size - np.count_nonzero(mask)),
        })

    metadata = {
        "schema": "pango-rotation-reference-v1",
        "input_file": str(input_path) if input_path else "generated_synthetic_checkerboard",
        "input_sha256": source_hash,
        "image_size": [width, height],
        "opencv_version": cv.__version__,
        "rotation_center_xy_pixels": list(center),
        "angle_semantics": "positive angle rotates the displayed source image counterclockwise",
        "coordinate_convention": "pixel centers; x increases right; y increases down",
        "mapping": "output pixel -> source pixel; source = center + R_image(-angle) * (output - center)",
        "interpolation": "OpenCV INTER_LINEAR",
        "outside_four_neighbor_policy": "black; valid only when all four bilinear source neighbors are in-frame",
        "outputs": outputs,
    }
    (out_dir / "rotation_reference.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Saved {len(outputs)} angle references in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
