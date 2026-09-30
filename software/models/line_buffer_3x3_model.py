"""Frame-level behavioral reference for ``line_buffer_3x3.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def line_buffer_taps(image: ArrayLike) -> NDArray[np.uint8]:
    """Return ``[top, middle, bottom]`` taps for real rows plus two flush rows."""

    source = np.asarray(image, dtype=np.uint8)
    if source.ndim != 2:
        raise ValueError("image must be a two-dimensional grayscale array")
    height, width = source.shape
    taps = np.zeros((height + 2, width, 3), dtype=np.uint8)
    for row in range(height + 2):
        if 0 <= row - 2 < height:
            taps[row, :, 0] = source[row - 2]
        if 0 <= row - 1 < height:
            taps[row, :, 1] = source[row - 1]
        if row < height:
            taps[row, :, 2] = source[row]
    return taps
