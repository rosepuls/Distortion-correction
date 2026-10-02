"""Generate a synthetic camera-distorted image by inverting Brown-Conrady."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from numpy.typing import NDArray
from PIL import Image


SOFTWARE_DIR = Path(__file__).resolve().parents[1]
if str(SOFTWARE_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_DIR))

from bitaccurate_distortion import DEFAULT_CONFIG, bilinear_remap_fixed
from distortion_float import CameraModel


def _quantize_q19(values: NDArray[np.float64]) -> NDArray[np.int64]:
    scaled = values * float(DEFAULT_CONFIG.src_coord_scale)
    rounded = np.where(scaled >= 0.0, np.floor(scaled + 0.5), np.ceil(scaled - 0.5))
    return rounded.astype(np.int64)


def inverse_distortion_map(
    width: int,
    height: int,
    camera: CameraModel,
    *,
    iterations: int = 12,
) -> tuple[NDArray[np.int64], NDArray[np.int64]]:
    """Map each distorted output pixel to its clean-image Q13.19 source.

    The Brown-Conrady forward model maps an undistorted normalized point to
    the distorted camera location.  Fixed-point iteration solves the inverse
    relation for every regular pixel in the synthetic distorted frame.
    """

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be greater than zero")
    if iterations <= 0:
        raise ValueError("iterations must be greater than zero")

    distorted_y_pixels, distorted_x_pixels = np.indices(
        (height, width), dtype=np.float64
    )
    distorted_x = (distorted_x_pixels - camera.cx) / camera.fx
    distorted_y = (distorted_y_pixels - camera.cy) / camera.fy
    undistorted_x = distorted_x.copy()
    undistorted_y = distorted_y.copy()

    for _ in range(iterations):
        radius_squared = undistorted_x * undistorted_x + undistorted_y * undistorted_y
        radial = (
            1.0
            + camera.k1 * radius_squared
            + camera.k2 * radius_squared * radius_squared
        )
        if np.any(np.abs(radial) < 1.0e-12):
            raise ValueError("distortion model is singular for this image domain")
        tangential_x = (
            2.0 * camera.p1 * undistorted_x * undistorted_y
            + camera.p2 * (radius_squared + 2.0 * undistorted_x * undistorted_x)
        )
        tangential_y = (
            camera.p1 * (radius_squared + 2.0 * undistorted_y * undistorted_y)
            + 2.0 * camera.p2 * undistorted_x * undistorted_y
        )
        undistorted_x = (distorted_x - tangential_x) / radial
        undistorted_y = (distorted_y - tangential_y) / radial

    source_x = camera.fx * undistorted_x + camera.cx
    source_y = camera.fy * undistorted_y + camera.cy
    return _quantize_q19(source_x), _quantize_q19(source_y)


def generate_distorted_input(
    image: Image.Image,
    camera: CameraModel,
    *,
    iterations: int = 12,
) -> Image.Image:
    """Return an RGB frame that simulates the configured camera distortion."""

    clean = np.asarray(image.convert("RGB"), dtype=np.uint8)
    height, width = clean.shape[:2]
    source_x_q19, source_y_q19 = inverse_distortion_map(
        width, height, camera, iterations=iterations
    )
    distorted = bilinear_remap_fixed(clean, source_x_q19, source_y_q19)
    return Image.fromarray(distorted)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_image", type=Path, help="clean reference image")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=12)
    parser.add_argument("--fx", type=float, default=180.0)
    parser.add_argument("--fy", type=float, default=180.0)
    parser.add_argument("--cx", type=float, default=127.5)
    parser.add_argument("--cy", type=float, default=95.5)
    parser.add_argument("--k1", type=float, default=-0.25)
    parser.add_argument("--k2", type=float, default=0.05)
    parser.add_argument("--p1", type=float, default=0.001)
    parser.add_argument("--p2", type=float, default=-0.001)
    arguments = parser.parse_args()

    camera = CameraModel(
        fx=arguments.fx,
        fy=arguments.fy,
        cx=arguments.cx,
        cy=arguments.cy,
        k1=arguments.k1,
        k2=arguments.k2,
        p1=arguments.p1,
        p2=arguments.p2,
    )
    with Image.open(arguments.input_image) as image:
        distorted = generate_distorted_input(
            image, camera, iterations=arguments.iterations
        )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    distorted.save(arguments.output, format="PNG")
    print(f"Created synthetic distorted input: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
