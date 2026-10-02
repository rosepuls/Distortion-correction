from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parents[1] / "result" / "tool"
sys.path.insert(0, str(TOOL_DIR))

from mem_to_png import rgb888_mem_to_image


class MemoryToPngTests(unittest.TestCase):
    def test_converter_restores_rgb888_pixels_in_raster_order(self) -> None:
        image = rgb888_mem_to_image(
            ["123456", "ABCDEF", "001020", "FF8040"],
            width=2,
            height=2,
        )

        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.size, (2, 2))
        self.assertEqual(
            list(image.get_flattened_data()),
            [(0x12, 0x34, 0x56), (0xAB, 0xCD, 0xEF), (0x00, 0x10, 0x20), (0xFF, 0x80, 0x40)],
        )

    def test_converter_skips_stride_padding_words(self) -> None:
        image = rgb888_mem_to_image(
            ["010203", "040506", "000000", "000000", "070809", "0A0B0C", "000000", "000000"],
            width=2,
            height=2,
            frame_stride_pixels=4,
        )

        self.assertEqual(
            list(image.get_flattened_data()),
            [(1, 2, 3), (4, 5, 6), (7, 8, 9), (10, 11, 12)],
        )


if __name__ == "__main__":
    unittest.main()
