from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SIM_ASSET_DIR = PROJECT_ROOT / "software" / "sim_assets"
SOFTWARE_DIR = PROJECT_ROOT / "software"
sys.path.insert(0, str(SIM_ASSET_DIR))
sys.path.insert(0, str(SOFTWARE_DIR))

from compare_mem_frames import compare_rgb888_frames
from create_checkerboard import COLOR_PALETTE, create_color_checkerboard
from bitaccurate_distortion import FixedPointCameraModel
from generate_distortion_vectors import (
    build_distortion_map_optimized_q18,
    coordinate_vector_words,
    pack_coordinate_word,
)


class DistortionImageAssetTests(unittest.TestCase):
    def test_color_checkerboard_uses_repeatable_rgb_palette(self) -> None:
        image = create_color_checkerboard(width=8, height=4, square_size=2)

        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.getpixel((0, 0)), COLOR_PALETTE[0])
        self.assertEqual(image.getpixel((2, 0)), COLOR_PALETTE[1])
        self.assertEqual(image.getpixel((0, 2)), COLOR_PALETTE[3])

    def test_coordinate_word_layout_is_valid_x0_y0_dx_dy(self) -> None:
        self.assertEqual(
            pack_coordinate_word(x0=1, y0=2, dx_q16=0x8000, dy_q16=0x4000, coord_valid=True),
            "10001000280004000",
        )

    def test_coordinate_vectors_mark_an_incomplete_right_neighborhood_invalid(self) -> None:
        scale = 1 << 19
        source_x = np.asarray([[0, scale, 2 * scale]], dtype=np.int64)
        source_y = np.zeros((1, 3), dtype=np.int64)

        words = coordinate_vector_words(source_x, source_y, width=3, height=2)

        self.assertEqual(words[0], "10000000000000000")
        self.assertEqual(words[2], "00002000000000000")

    def test_q18_optimized_map_preserves_a_power_of_two_identity_camera(self) -> None:
        camera = FixedPointCameraModel.from_parameters(
            fx=8.0,
            fy=8.0,
            cx=1.0,
            cy=0.5,
        )

        source_x, source_y = build_distortion_map_optimized_q18(3, 2, camera)

        scale = 1 << 19
        np.testing.assert_array_equal(
            source_x,
            np.asarray([[0, scale, 2 * scale], [0, scale, 2 * scale]], dtype=np.int64),
        )
        np.testing.assert_array_equal(
            source_y,
            np.asarray([[0, 0, 0], [scale, scale, scale]], dtype=np.int64),
        )

    def test_frame_comparator_reports_raster_coordinate_and_words(self) -> None:
        mismatches = compare_rgb888_frames(
            ["000000", "112233", "445566", "778899"],
            ["000000", "112233", "ABCDEF", "778899"],
            width=2,
            height=2,
        )

        self.assertEqual(mismatches, [(0, 1, "445566", "ABCDEF")])


if __name__ == "__main__":
    unittest.main()
