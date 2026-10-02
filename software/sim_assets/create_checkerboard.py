"""Create an RGB black-and-white checkerboard image for RTL simulation."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


COLOR_PALETTE: tuple[tuple[int, int, int], ...] = (
    (0, 0, 0),
    (255, 0, 0),
    (0, 255, 0),
    (0, 0, 255),
    (255, 255, 0),
    (0, 255, 255),
    (255, 0, 255),
    (255, 255, 255),
)


def default_checkerboard_output_path(width: int, height: int) -> Path:
    """Return the standard result location for one generated checkerboard."""

    return Path("result") / "sim_assets" / f"checkerboard_{width}x{height}.png"


def default_color_checkerboard_output_path(width: int, height: int) -> Path:
    """Return the standard result location for a color checkerboard."""

    return Path("result") / "sim_assets" / f"color_checkerboard_{width}x{height}.png"


def create_checkerboard(
    *,
    width: int,
    height: int,
    square_size: int,
    top_left_black: bool = True,
) -> Image.Image:
    """Return an RGB checkerboard with pixel origin at the top-left."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")
    if square_size <= 0:
        raise ValueError("square_size must be positive")

    image = Image.new("RGB", (width, height))
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            is_black = ((x // square_size) + (y // square_size)) % 2 == 0
            if not top_left_black:
                is_black = not is_black
            pixels[x, y] = (0, 0, 0) if is_black else (255, 255, 255)
    return image


def create_color_checkerboard(*, width: int, height: int, square_size: int) -> Image.Image:
    """Return an RGB checkerboard whose tiles cycle through ``COLOR_PALETTE``.

    The row contribution deliberately advances by three colors.  It makes
    both horizontal and vertical displacement immediately visible in the
    distortion result while retaining a repeatable, simple test pattern.
    """

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")
    if square_size <= 0:
        raise ValueError("square_size must be positive")

    image = Image.new("RGB", (width, height))
    pixels = image.load()
    for y in range(height):
        tile_y = y // square_size
        for x in range(width):
            tile_x = x // square_size
            pixels[x, y] = COLOR_PALETTE[(tile_x + 3 * tile_y) % len(COLOR_PALETTE)]
    return image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=64, help="image width in pixels")
    parser.add_argument("--height", type=int, default=48, help="image height in pixels")
    parser.add_argument(
        "--square-size", type=int, default=8, help="checkerboard square side in pixels"
    )
    parser.add_argument("--output", type=Path, default=None, help="PNG output path")
    parser.add_argument(
        "--top-left-white",
        action="store_true",
        help="make the top-left square white instead of black",
    )
    parser.add_argument(
        "--color",
        action="store_true",
        help="generate the deterministic RGB color checkerboard instead of black and white",
    )
    arguments = parser.parse_args()

    output_path = arguments.output or (
        default_color_checkerboard_output_path(arguments.width, arguments.height)
        if arguments.color
        else default_checkerboard_output_path(arguments.width, arguments.height)
    )
    if arguments.color:
        image = create_color_checkerboard(
            width=arguments.width,
            height=arguments.height,
            square_size=arguments.square_size,
        )
    else:
        image = create_checkerboard(
            width=arguments.width,
            height=arguments.height,
            square_size=arguments.square_size,
            top_left_black=not arguments.top_left_white,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, format="PNG")
    pattern_name = "color checkerboard" if arguments.color else "checkerboard"
    print(f"Created RGB {pattern_name}: {output_path} ({arguments.width}x{arguments.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
