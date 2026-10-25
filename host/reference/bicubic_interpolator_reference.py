"""Bit-accurate fixed-point reference for Catmull–Rom RGBX8888 interpolation.

Coordinates are represented as unsigned Q0.16 fractions. Catmull–Rom weights
are signed Q2.30 values; the center weight is corrected so the four quantized
weights sum exactly to 1. Horizontal products retain Q30 precision and the
vertical sum retains Q60 precision. Final conversion rounds to nearest with
ties away from zero, then saturates each RGB channel to [0, 255]. The X byte
does not participate and the output X byte is always zero.
"""

from typing import Sequence


WEIGHT_FRAC_BITS = 14
WEIGHT_ONE = 1 << WEIGHT_FRAC_BITS
COORD_FRAC_BITS = 16
COORD_ONE = 1 << COORD_FRAC_BITS


def _round_shift_away_from_zero(value: int, shift: int) -> int:
    half = 1 << (shift - 1)
    if value < 0:
        return -((-value + half) >> shift)
    return (value + half) >> shift


def catmull_rom_weights_q14(fraction_q16: int) -> tuple[int, int, int, int]:
    """Return Catmull–Rom weights for one Q0.16 fraction as signed Q2.14."""
    if not isinstance(fraction_q16, int) or not 0 <= fraction_q16 < COORD_ONE:
        raise ValueError("fraction_q16 must be an integer in [0, 65535]")

    t = fraction_q16
    t2 = (t * t) >> COORD_FRAC_BITS
    t3 = (t2 * t) >> COORD_FRAC_BITS
    weights_q16 = (
        -(t >> 1) + t2 - (t3 >> 1),
        COORD_ONE - ((5 * t2) >> 1) + ((3 * t3) >> 1),
        (t >> 1) + (t2 << 1) - ((3 * t3) >> 1),
        -(t2 >> 1) + (t3 >> 1),
    )
    q0, q2, q3 = (
        _round_shift_away_from_zero(weights_q16[index], COORD_FRAC_BITS-WEIGHT_FRAC_BITS)
        for index in (0, 2, 3)
    )
    # Enforce partition of unity after quantization for constant-color input.
    q1 = WEIGHT_ONE - q0 - q2 - q3
    return q0, q1, q2, q3


def bicubic_interpolate_rgbx8888(
    samples: Sequence[Sequence[int]], fraction_x_q16: int, fraction_y_q16: int
) -> int:
    """Interpolate a 4×4 row-major RGBX8888 neighborhood.

    The center of the returned stencil is sample ``[1][1]`` at fraction 0, 0.
    Input values are unsigned 32-bit RGBX8888 words.
    """
    if len(samples) != 4 or any(len(row) != 4 for row in samples):
        raise ValueError("samples must contain exactly four rows of four pixels")
    if any(not isinstance(pixel, int) or not 0 <= pixel <= 0xFFFFFFFF
           for row in samples for pixel in row):
        raise ValueError("each sample must be an unsigned 32-bit pixel")

    wx = catmull_rom_weights_q14(fraction_x_q16)
    wy = catmull_rom_weights_q14(fraction_y_q16)
    output = []
    for shift in (24, 16, 8):
        horizontal = [
            sum(((pixel >> shift) & 0xFF) * weight
                for pixel, weight in zip(row, wx))
            for row in samples
        ]
        accumulated_q60 = sum(value * weight for value, weight in zip(horizontal, wy))
        channel = _round_shift_away_from_zero(accumulated_q60, 2 * WEIGHT_FRAC_BITS)
        output.append(min(255, max(0, channel)))

    red, green, blue = output
    return (red << 24) | (green << 16) | (blue << 8)
