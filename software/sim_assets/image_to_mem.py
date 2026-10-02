"""Convert an image into raster-ordered RGB888 words for Verilog $readmemh."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def default_mem_output_path(input_image: Path) -> Path:
    """Return the standard result location for a converted memory image."""

    return Path("result") / "sim_assets" / f"{input_image.stem}.mem"


def rgb888_mem_words(
    image: Image.Image,
    *,
    frame_stride_pixels: int | None = None,
) -> list[str]:
    """Return one ``RRGGBB`` word per logical source-pixel address.

    The image is converted to RGB.  Rows are emitted from top to bottom and
    pixels from left to right, matching ``addr = y * frame_stride_pixels + x``.
    If the stride exceeds the image width, black words fill each row's padding
    addresses so a `$readmemh` array preserves the logical layout.
    """

    rgb_image = image.convert("RGB")
    width, height = rgb_image.size
    stride = width if frame_stride_pixels is None else frame_stride_pixels
    if stride < width:
        raise ValueError("frame_stride_pixels must be greater than or equal to image width")

    pixels = rgb_image.load()
    words: list[str] = []
    for y in range(height):
        for x in range(width):
            red, green, blue = pixels[x, y]
            words.append(f"{red:02X}{green:02X}{blue:02X}")
        words.extend("000000" for _ in range(stride - width))
    return words


def image_to_rgb888_mem(
    image: Image.Image,
    output_path: Path,
    *,
    frame_stride_pixels: int | None = None,
) -> None:
    """Write the raster-ordered RGB888 words to a `$readmemh` file."""

    words = rgb888_mem_words(image, frame_stride_pixels=frame_stride_pixels)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(words) + "\n", encoding="ascii", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_image", type=Path, help="input image path")
    parser.add_argument("--output", type=Path, default=None, help=".mem output path")
    parser.add_argument(
        "--frame-stride-pixels",
        type=int,
        default=None,
        help="logical pixels per source row; defaults to the image width",
    )
    arguments = parser.parse_args()

    output_path = arguments.output or default_mem_output_path(arguments.input_image)
    with Image.open(arguments.input_image) as image:
        image_to_rgb888_mem(
            image,
            output_path,
            frame_stride_pixels=arguments.frame_stride_pixels,
        )
    print(f"Created RGB888 memory file: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
