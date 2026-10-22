"""Bit-exact software reference for the public identity-mapper contract.

The mapper boundary represents source pixel coordinates as signed Q16.16.
Pixel (0, 0) is the center of the top-left source pixel.
"""

from __future__ import annotations

from collections.abc import Iterator


Q16_FRACTION_BITS = 16
Q16_ONE = 1 << Q16_FRACTION_BITS
Q16_FRACTION_MASK = Q16_ONE - 1


def identity_map(u: int, v: int) -> tuple[int, int, bool]:
    """Map an output pixel to the same source pixel in signed Q16.16."""

    return u * Q16_ONE, v * Q16_ONE, True


def identity_jacobian() -> tuple[int, int, int, int, bool]:
    """Return Q16.16 derivatives (dsx/du, dsx/dv, dsy/du, dsy/dv)."""

    return Q16_ONE, 0, 0, Q16_ONE, True


def split_q16_16(raw: int) -> tuple[int, int]:
    """Return mathematical floor and the non-negative Q16 fraction."""

    return raw >> Q16_FRACTION_BITS, raw & Q16_FRACTION_MASK


def iter_identity_frame(
    width: int,
    height: int,
    frame_id: int = 0,
    param_version: int = 0,
) -> Iterator[dict[str, int | bool]]:
    """Yield a raster-ordered identity coordinate reference frame."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")

    last_pixel_id = width * height - 1
    j00, j01, j10, j11, j_valid = identity_jacobian()
    for v in range(height):
        for u in range(width):
            pixel_id = v * width + u
            sx, sy, geometry_valid = identity_map(u, v)
            yield {
                "u": u,
                "v": v,
                "pixel_id": pixel_id,
                "sx_q16_16": sx,
                "sy_q16_16": sy,
                "geometry_valid": geometry_valid,
                "frame_id": frame_id,
                "param_version": param_version,
                "jacobian_q16_16": (j00, j01, j10, j11),
                "j_valid": j_valid,
                "sof": pixel_id == 0,
                "eol": u == width - 1,
                "eof": pixel_id == last_pixel_id,
            }
