"""Floating-point lens-distortion correction reference model.

The model builds a reverse map: each undistorted output pixel is converted to
normalized camera coordinates, distorted with the Brown-Conrady model, and
mapped back to a source-image coordinate for bilinear sampling.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import ArrayLike, NDArray

try:
    from .bilinear_model import bilinear_remap
except ImportError:  # Support running this file directly from software/.
    from bilinear_model import bilinear_remap


@dataclass(frozen=True)
class CameraModel:
    """Camera intrinsics and Brown-Conrady distortion coefficients."""

    fx: float
    fy: float
    cx: float
    cy: float
    k1: float = 0.0
    k2: float = 0.0
    p1: float = 0.0
    p2: float = 0.0

    def __post_init__(self) -> None:
        values = (self.fx, self.fy, self.cx, self.cy, self.k1, self.k2, self.p1, self.p2)
        if not all(np.isfinite(value) for value in values):
            raise ValueError("camera parameters must all be finite")
        if self.fx <= 0.0 or self.fy <= 0.0:
            raise ValueError("fx and fy must be greater than zero")


def source_coordinates(
    u: ArrayLike,
    v: ArrayLike,
    camera: CameraModel,
) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    """Convert undistorted output coordinates into distorted source coordinates."""

    output_x = np.asarray(u, dtype=np.float64)
    output_y = np.asarray(v, dtype=np.float64)
    if output_x.shape != output_y.shape:
        raise ValueError("u and v must have equal shapes")

    x = (output_x - camera.cx) / camera.fx
    y = (output_y - camera.cy) / camera.fy
    radius_squared = x * x + y * y
    radial = 1.0 + camera.k1 * radius_squared + camera.k2 * radius_squared * radius_squared

    distorted_x = (
        x * radial
        + 2.0 * camera.p1 * x * y
        + camera.p2 * (radius_squared + 2.0 * x * x)
    )
    distorted_y = (
        y * radial
        + camera.p1 * (radius_squared + 2.0 * y * y)
        + 2.0 * camera.p2 * x * y
    )

    source_x = camera.fx * distorted_x + camera.cx
    source_y = camera.fy * distorted_y + camera.cy
    return source_x, source_y


def build_distortion_map(
    width: int,
    height: int,
    camera: CameraModel,
) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    """Build source-coordinate maps for an output image of ``width`` by ``height``."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be greater than zero")

    output_y, output_x = np.indices((height, width), dtype=np.float64)
    return source_coordinates(output_x, output_y, camera)


def correct_distortion(
    image: ArrayLike,
    camera: CameraModel,
    border_value: float = 0.0,
) -> tuple[NDArray[np.float64], NDArray[np.float64], NDArray[np.float64]]:
    """Correct an image and return ``(corrected, map_x, map_y)``.

    Pixels whose four bilinear neighbours do not all exist are filled with the
    requested border value, matching the project's RTL boundary policy.
    """

    source = np.asarray(image)
    if source.ndim not in (2, 3):
        raise ValueError("image must be a 2-D grayscale or 3-D color array")

    height, width = source.shape[:2]
    map_x, map_y = build_distortion_map(width, height, camera)
    corrected = bilinear_remap(source, map_x, map_y, border_value=border_value)
    return corrected, map_x, map_y
