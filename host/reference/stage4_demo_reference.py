"""Software reference and preview renderer for the Stage 4 board demo."""

import argparse
from pathlib import Path

from bilinear_interpolator_reference import bilinear_interpolate_rgbx8888
from bilinear_sample_reference import plan_bilinear


def map_demo_radial(u, v, *, center_x=640, center_y=360, radial_shift=23):
    """Return the demo radial source coordinate as signed Q16.16 integers."""
    dx = u - center_x
    dy = v - center_y
    radius_squared = dx * dx + dy * dy
    q16_shift = radial_shift - 16
    return (
        (u << 16) + ((dx * radius_squared) >> q16_shift),
        (v << 16) + ((dy * radius_squared) >> q16_shift),
    )


def procedural_pixel(x, y, *, width=1280, height=720):
    """Evaluate the RTL grid/gradient source at one integer coordinate."""
    if x % 64 == 0 or y % 64 == 0 or x == width - 1 or y == height - 1:
        return 0xFFFFFF00
    return ((x & 0xFF) << 24) | ((y & 0xFF) << 16) | (((x ^ y) & 0xFF) << 8)


def stage4_demo_pixel(u, v, *, width=1280, height=720):
    """Evaluate the complete radial, border and bilinear demo path."""
    sx, sy = map_demo_radial(u, v, center_x=width // 2, center_y=height // 2)
    request = plan_bilinear(sx, sy, width=width, height=height, border_mode="black")
    pixels = (
        procedural_pixel(request["x0"], request["y0"], width=width, height=height),
        procedural_pixel(request["x1"], request["y0"], width=width, height=height),
        procedural_pixel(request["x0"], request["y1"], width=width, height=height),
        procedural_pixel(request["x1"], request["y1"], width=width, height=height),
    )
    return bilinear_interpolate_rgbx8888(
        *pixels,
        fx=request["fx"],
        fy=request["fy"],
        neighbor_valid=request["neighbor_valid"],
    )


def render_demo_frame(width=1280, height=720):
    """Return the expected board image as an HxWx3 RGB uint8 array."""
    import numpy as np

    image = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        for x in range(width):
            pixel = stage4_demo_pixel(x, y, width=width, height=height)
            image[y, x] = (pixel >> 24, (pixel >> 16) & 0xFF, (pixel >> 8) & 0xFF)
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    args = parser.parse_args()

    from PIL import Image

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(render_demo_frame(args.width, args.height), mode="RGB").save(args.output)


if __name__ == "__main__":
    main()
