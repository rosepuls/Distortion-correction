"""Reference planning for one bilinear sampling request.

The public coordinate format is signed Q16.16.  The returned address fields
are always safe, clamped image addresses.  ``neighbor_valid`` uses bit order
P00, P10, P01, P11 from least significant to most significant bit.
"""


def plan_bilinear(
    sx_q16_16,
    sy_q16_16,
    *,
    width=1280,
    height=720,
    border_mode="black",
    geometry_valid=True,
):
    """Split a source coordinate into a 2x2 bilinear sample request."""
    if width <= 0 or height <= 0:
        raise ValueError("image dimensions must be positive")
    if border_mode not in ("black", "replicate"):
        raise ValueError("border_mode must be 'black' or 'replicate'")

    x0_raw = sx_q16_16 >> 16
    y0_raw = sy_q16_16 >> 16
    x1_raw = x0_raw + 1
    y1_raw = y0_raw + 1

    def clamp(value, upper):
        return min(max(value, 0), upper)

    x0 = clamp(x0_raw, width - 1)
    x1 = clamp(x1_raw, width - 1)
    y0 = clamp(y0_raw, height - 1)
    y1 = clamp(y1_raw, height - 1)

    if not geometry_valid:
        neighbor_valid = 0
    elif border_mode == "replicate":
        neighbor_valid = 0b1111
    else:
        x0_valid = 0 <= x0_raw < width
        x1_valid = 0 <= x1_raw < width
        y0_valid = 0 <= y0_raw < height
        y1_valid = 0 <= y1_raw < height
        neighbor_valid = (
            (x0_valid and y0_valid) << 0
            | (x1_valid and y0_valid) << 1
            | (x0_valid and y1_valid) << 2
            | (x1_valid and y1_valid) << 3
        )

    return {
        "x0": x0,
        "x1": x1,
        "y0": y0,
        "y1": y1,
        "fx": sx_q16_16 & 0xFFFF,
        "fy": sy_q16_16 & 0xFFFF,
        "neighbor_valid": neighbor_valid,
        "geometry_valid": bool(geometry_valid),
    }
