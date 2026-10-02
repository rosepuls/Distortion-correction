from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PIL import Image


SIM_ASSET_DIR = Path(__file__).resolve().parents[1] / "software" / "sim_assets"
sys.path.insert(0, str(SIM_ASSET_DIR))

from create_checkerboard import create_checkerboard
from create_checkerboard import default_checkerboard_output_path
from image_to_mem import default_mem_output_path, rgb888_mem_words


class SimulationAssetTests(unittest.TestCase):
    def test_default_artifacts_are_grouped_under_result_sim_assets(self) -> None:
        self.assertEqual(
            default_checkerboard_output_path(64, 48),
            Path("result/sim_assets/checkerboard_64x48.png"),
        )
        self.assertEqual(
            default_mem_output_path(Path("input/checkerboard_64x48.png")),
            Path("result/sim_assets/checkerboard_64x48.mem"),
        )

    def test_checkerboard_starts_black_and_alternates_by_square(self) -> None:
        image = create_checkerboard(width=8, height=6, square_size=2)

        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.size, (8, 6))
        self.assertEqual(image.getpixel((0, 0)), (0, 0, 0))
        self.assertEqual(image.getpixel((2, 0)), (255, 255, 255))
        self.assertEqual(image.getpixel((0, 2)), (255, 255, 255))
        self.assertEqual(image.getpixel((2, 2)), (0, 0, 0))

    def test_converter_returns_rgb888_in_raster_address_order(self) -> None:
        image = Image.new("RGB", (2, 2))
        image.putdata(
            [
                (0x12, 0x34, 0x56),
                (0xAB, 0xCD, 0xEF),
                (0x00, 0x10, 0x20),
                (0xFF, 0x80, 0x40),
            ]
        )

        self.assertEqual(
            list(rgb888_mem_words(image)),
            ["123456", "ABCDEF", "001020", "FF8040"],
        )

    def test_converter_inserts_zero_padding_for_frame_stride(self) -> None:
        image = Image.new("RGB", (2, 2), color=(1, 2, 3))

        self.assertEqual(
            list(rgb888_mem_words(image, frame_stride_pixels=4)),
            [
                "010203",
                "010203",
                "000000",
                "000000",
                "010203",
                "010203",
                "000000",
                "000000",
            ],
        )


if __name__ == "__main__":
    unittest.main()
