"""Behavioral reference for ``gamma_lut.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def gamma_lut(
    pixels: ArrayLike, table: ArrayLike, enable: bool = True
) -> int | NDArray[np.uint8]:
    """Map each u8 pixel through one selected 256-entry LUT, or bypass it."""

    source = np.asarray(pixels, dtype=np.uint8)
    lut = np.asarray(table, dtype=np.uint8)
    if lut.shape != (256,):
        raise ValueError("table must contain exactly 256 entries")
    result = lut[source] if enable else source.copy()
    return int(result) if result.ndim == 0 else result.astype(np.uint8, copy=False)
