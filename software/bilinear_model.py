"""Floating-point bilinear interpolation reference model."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def bilinear_sample(
    p00: ArrayLike,
    p10: ArrayLike,
    p01: ArrayLike,
    p11: ArrayLike,
    dx: ArrayLike,
    dy: ArrayLike,
) -> float | NDArray[np.float64]:
    """Return one bilinear sample using the two-stage interpolation form."""

    top = p00 + (p10 - p00) * dx
    bottom = p01 + (p11 - p01) * dx
    return top + (bottom - top) * dy


def bilinear_remap(
    image: ArrayLike,
    map_x: ArrayLike,
    map_y: ArrayLike,
    border_value: float = 0.0,
) -> NDArray[np.float64]:
    """Remap a grayscale or multichannel image with bilinear interpolation.

    ``map_x`` and ``map_y`` contain source coordinates for every output pixel.
    A coordinate is valid only when all four interpolation neighbours are
    inside the source image. Invalid, non-finite, and boundary coordinates are
    filled with ``border_value``.
    """

    source = np.asarray(image)
    x_map = np.asarray(map_x, dtype=np.float64)
    y_map = np.asarray(map_y, dtype=np.float64)

    if source.ndim not in (2, 3):
        raise ValueError("image must be a 2-D grayscale or 3-D color array")
    if x_map.ndim != 2 or y_map.ndim != 2 or x_map.shape != y_map.shape:
        raise ValueError("map_x and map_y must be 2-D arrays with equal shapes")

    height, width = source.shape[:2]
    output_shape = x_map.shape + (() if source.ndim == 2 else (source.shape[2],))
    output = np.full(output_shape, border_value, dtype=np.float64)

    finite = np.isfinite(x_map) & np.isfinite(y_map)
    x0 = np.zeros(x_map.shape, dtype=np.int64)
    y0 = np.zeros(y_map.shape, dtype=np.int64)
    x0[finite] = np.floor(x_map[finite]).astype(np.int64)
    y0[finite] = np.floor(y_map[finite]).astype(np.int64)

    valid = finite & (x0 >= 0) & (x0 < width - 1) & (y0 >= 0) & (y0 < height - 1)
    if not np.any(valid):
        return output

    valid_x0 = x0[valid]
    valid_y0 = y0[valid]
    dx = x_map[valid] - valid_x0
    dy = y_map[valid] - valid_y0

    p00 = source[valid_y0, valid_x0].astype(np.float64)
    p10 = source[valid_y0, valid_x0 + 1].astype(np.float64)
    p01 = source[valid_y0 + 1, valid_x0].astype(np.float64)
    p11 = source[valid_y0 + 1, valid_x0 + 1].astype(np.float64)

    if source.ndim == 3:
        dx = dx[:, np.newaxis]
        dy = dy[:, np.newaxis]

    output[valid] = bilinear_sample(p00, p10, p01, p11, dx, dy)
    return output
