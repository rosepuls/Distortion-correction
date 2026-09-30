"""Bit-accurate Q0.16 reference for ``bilinear_interp.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def bilinear_interp(
    p00: ArrayLike,
    p10: ArrayLike,
    p01: ArrayLike,
    p11: ArrayLike,
    dx_q16: int,
    dy_q16: int,
    coord_valid: bool = True,
) -> int | NDArray[np.uint8]:
    """Perform the same two-stage integer interpolation and truncation as RTL."""

    if not 0 <= dx_q16 <= 0xFFFF or not 0 <= dy_q16 <= 0xFFFF:
        raise ValueError("dx_q16 and dy_q16 must fit unsigned Q0.16")
    top_left, top_right, bottom_left, bottom_right = np.broadcast_arrays(
        np.asarray(p00, dtype=np.int64),
        np.asarray(p10, dtype=np.int64),
        np.asarray(p01, dtype=np.int64),
        np.asarray(p11, dtype=np.int64),
    )
    if not coord_valid:
        result = np.zeros(top_left.shape, dtype=np.uint8)
    else:
        top_q16 = (top_left << 16) + (top_right - top_left) * dx_q16
        bottom_q16 = (bottom_left << 16) + (bottom_right - bottom_left) * dx_q16
        result_q32 = (top_q16 << 16) + (bottom_q16 - top_q16) * dy_q16
        result = np.clip(result_q32 >> 32, 0, 255).astype(np.uint8)
    return int(result) if result.ndim == 0 else result
