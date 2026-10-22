"""Bit-accurate RGBX8888 bilinear interpolation reference."""


def bilinear_interpolate_rgbx8888(
    p00,
    p10,
    p01,
    p11,
    *,
    fx,
    fy,
    neighbor_valid=0b1111,
):
    """Interpolate four RGBX8888 pixels with unsigned Q0.16 fractions.

    Invalid neighbors contribute constant black.  The three color channels
    are rounded once after the full two-dimensional Q0.32 accumulation, and
    the public X byte is always zero.
    """
    if not 0 <= fx <= 0xFFFF or not 0 <= fy <= 0xFFFF:
        raise ValueError("fx and fy must fit unsigned Q0.16")
    if not 0 <= neighbor_valid <= 0xF:
        raise ValueError("neighbor_valid must be a four-bit mask")

    pixels = (p00, p10, p01, p11)
    wx0 = 0x10000 - fx
    wy0 = 0x10000 - fy

    def channel(shift):
        samples = [
            ((pixel >> shift) & 0xFF) if neighbor_valid & (1 << index) else 0
            for index, pixel in enumerate(pixels)
        ]
        top = samples[0] * wx0 + samples[1] * fx
        bottom = samples[2] * wx0 + samples[3] * fx
        accumulated = top * wy0 + bottom * fy
        return (accumulated + (1 << 31)) >> 32

    red = channel(24)
    green = channel(16)
    blue = channel(8)
    return (red << 24) | (green << 16) | (blue << 8)
