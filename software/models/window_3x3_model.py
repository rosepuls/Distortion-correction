"""Zero-padded frame reference for ``window_3x3.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def window_3x3(image: ArrayLike) -> NDArray[np.uint8]:
    """Return one centre-aligned, zero-padded 3x3 window per image pixel."""

    source = np.asarray(image, dtype=np.uint8)
    if source.ndim != 2:
        raise ValueError("image must be a two-dimensional grayscale array")
    height, width = source.shape
    padded = np.pad(source, ((1, 1), (1, 1)), mode="constant")
    windows = np.empty((height, width, 3, 3), dtype=np.uint8)
    for row in range(height):
        for column in range(width):
            windows[row, column] = padded[row : row + 3, column : column + 3]
    return windows
