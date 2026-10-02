"""Create a labeled input/Golden/RTL/difference image for visual inspection."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


LABEL_HEIGHT = 20
DIFFERENCE_GAIN = 8


def create_comparison_panel(
    input_image: Image.Image,
    golden_image: Image.Image,
    rtl_image: Image.Image,
) -> Image.Image:
    """Return a 2x2 RGB panel with an amplified absolute-difference tile."""

    source = input_image.convert("RGB")
    golden = golden_image.convert("RGB")
    rtl = rtl_image.convert("RGB")
    if source.size != golden.size or source.size != rtl.size:
        raise ValueError("input, Golden, and RTL images must have equal dimensions")

    difference = ImageChops.difference(golden, rtl).point(
        lambda value: min(255, value * DIFFERENCE_GAIN)
    )
    width, height = source.size
    row_height = LABEL_HEIGHT + height
    panel = Image.new("RGB", (2 * width, 2 * row_height), color=(32, 32, 32))
    draw = ImageDraw.Draw(panel)
    tiles = (
        ("INPUT", source, 0, 0),
        ("PYTHON GOLDEN", golden, width, 0),
        ("RTL FULL CHAIN", rtl, 0, row_height),
        (f"ABS DIFF x{DIFFERENCE_GAIN}", difference, width, row_height),
    )
    for label, image, x, y in tiles:
        draw.text((x + 4, y + 4), label, fill=(255, 255, 255))
        panel.paste(image, (x, y + LABEL_HEIGHT))
    return panel


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_image", type=Path)
    parser.add_argument("golden_image", type=Path)
    parser.add_argument("rtl_image", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    with Image.open(arguments.input_image) as source:
        with Image.open(arguments.golden_image) as golden:
            with Image.open(arguments.rtl_image) as rtl:
                panel = create_comparison_panel(source, golden, rtl)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    panel.save(arguments.output, format="PNG")
    print(f"Created comparison panel: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
