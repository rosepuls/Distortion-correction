"""Behavioral reference for binary ``morphology.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike


def morphology_3x3(window: ArrayLike, dilate: bool) -> int:
    """Use OR for dilation and AND for erosion over a 3x3 binary window."""

    pixels = np.asarray(window)
    if pixels.shape != (3, 3):
        raise ValueError("window must have shape (3, 3)")
    binary = pixels != 0
    return int(np.any(binary) if dilate else np.all(binary))
