"""Bit-accurate reference for ``gaussian_3x3.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike


_KERNEL = np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]], dtype=np.int64)


def gaussian_3x3(window: ArrayLike) -> int:
    """Apply the 1-2-1 Gaussian kernel and truncate by shifting right four."""

    pixels = np.asarray(window, dtype=np.int64)
    if pixels.shape != (3, 3):
        raise ValueError("window must have shape (3, 3)")
    return int(np.sum(pixels * _KERNEL) >> 4)
