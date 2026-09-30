"""Bit-accurate reference for ``sobel_3x3.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike


_GX = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.int64)
_GY = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.int64)


def sobel_3x3(window: ArrayLike) -> int:
    """Return ``abs(Gx) + abs(Gy)`` as an unsigned 12-bit-compatible value."""

    pixels = np.asarray(window, dtype=np.int64)
    if pixels.shape != (3, 3):
        raise ValueError("window must have shape (3, 3)")
    gx = int(np.sum(pixels * _GX))
    gy = int(np.sum(pixels * _GY))
    return abs(gx) + abs(gy)
