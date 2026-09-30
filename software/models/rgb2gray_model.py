"""Bit-accurate reference for ``rgb2gray.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def rgb2gray(rgb: ArrayLike) -> int | NDArray[np.uint8]:
    """Convert RGB888 values with ``(77R + 150G + 29B) >> 8``."""

    pixels = np.asarray(rgb, dtype=np.int64)
    if pixels.ndim == 0 or pixels.shape[-1] != 3:
        raise ValueError("rgb must have a final dimension of length 3")
    weighted = 77 * pixels[..., 0] + 150 * pixels[..., 1] + 29 * pixels[..., 2]
    gray = (weighted >> 8).astype(np.uint8)
    return int(gray) if gray.ndim == 0 else gray
