"""Bit-accurate reference for ``brightness_gain.sv``."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def brightness_gain(
    pixels: ArrayLike, gain_q12: int, offset: int
) -> int | NDArray[np.uint8]:
    """Apply unsigned Q4.12 gain, signed integer offset, and u8 saturation."""

    if not 0 <= gain_q12 <= 0xFFFF:
        raise ValueError("gain_q12 must fit unsigned 16 bit")
    if not -512 <= offset <= 511:
        raise ValueError("offset must fit signed 10 bit")
    source = np.asarray(pixels, dtype=np.int64)
    adjusted = ((source * gain_q12) + (offset << 12)) >> 12
    result = np.clip(adjusted, 0, 255).astype(np.uint8)
    return int(result) if result.ndim == 0 else result
