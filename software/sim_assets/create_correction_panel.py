"""Create a visual clean/distorted/corrected/bit-difference panel."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


LABEL_HEIGHT = 20
DIFFERENCE_GAIN = 8


def create_correction_panel(
    clean_image: Image.Image,
    distorted_image: Image.Image,
    rtl_corrected_image: Image.Image,
    golden_corrected_image: Image.Image,
) -> Image.Image:
    """Return a labeled 2x2 correction panel with amplified RTL error."""

    clean = clean_image.convert("RGB")
    distorted = distorted_image.convert("RGB")
    rtl = rtl_corrected_image.convert("RGB")
    golden = golden_corrected_image.convert("RGB")
    if not (clean.size == distorted.size == rtl.size == golden.size):
        raise ValueError("all correction-panel images must have equal dimensions")

    difference = ImageChops.difference(rtl, golden).point(
        lambda value: min(255, value * DIFFERENCE_GAIN)
    )
    width, height = clean.size
    row_height = LABEL_HEIGHT + height
    panel = Image.new("RGB", (2 * width, 2 * row_height), color=(32, 32, 32))
    draw = ImageDraw.Draw(panel)
    tiles = (
        ("CLEAN REFERENCE", clean, 0, 0),
        ("SYNTHETIC CAMERA INPUT", distorted, width, 0),
        ("RTL CORRECTED", rtl, 0, row_height),
        (f"RTL vs GOLDEN DIFF x{DIFFERENCE_GAIN}", difference, width, row_height),
    )
    for label, image, x, y in tiles:
        draw.text((x + 4, y + 4), label, fill=(255, 255, 255))
        panel.paste(image, (x, y + LABEL_HEIGHT))
    return panel


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("clean_image", type=Path)
    parser.add_argument("distorted_image", type=Path)
    parser.add_argument("rtl_corrected_image", type=Path)
    parser.add_argument("golden_corrected_image", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    with Image.open(arguments.clean_image) as clean:
        with Image.open(arguments.distorted_image) as distorted:
            with Image.open(arguments.rtl_corrected_image) as rtl:
                with Image.open(arguments.golden_corrected_image) as golden:
                    panel = create_correction_panel(clean, distorted, rtl, golden)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    panel.save(arguments.output, format="PNG")
    print(f"Created correction comparison panel: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
