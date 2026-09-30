"""Behavioral reference for ``threshold.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def threshold(gradients: ArrayLike, level: int) -> int | NDArray[np.uint8]:
    """Return one only when a 12-bit gradient is strictly greater than level."""

    if not 0 <= level <= 0xFFF:
        raise ValueError("level must fit unsigned 12 bit")
    result = (np.asarray(gradients, dtype=np.int64) > level).astype(np.uint8)
    return int(result) if result.ndim == 0 else result
