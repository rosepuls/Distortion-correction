from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))

from models.bilinear_interp_model import bilinear_interp
from models.brightness_gain_model import brightness_gain
from models.gamma_lut_model import gamma_lut
from models.gaussian_3x3_model import gaussian_3x3
from models.line_buffer_3x3_model import line_buffer_taps
from models.morphology_model import morphology_3x3
from models.rgb2gray_model import rgb2gray
from models.sobel_3x3_model import sobel_3x3
from models.threshold_model import threshold
from models.window_3x3_model import window_3x3


class PreprocessGoldenModelTests(unittest.TestCase):
    def test_rgb2gray_uses_project_integer_weights(self) -> None:
        pixels = np.array(
            [[0, 0, 0], [255, 255, 255], [255, 0, 0], [0, 255, 0], [0, 0, 255]],
            dtype=np.uint8,
        )
        np.testing.assert_array_equal(rgb2gray(pixels), [0, 255, 76, 149, 28])

    def test_brightness_gain_scales_offsets_and_saturates(self) -> None:
        np.testing.assert_array_equal(
            brightness_gain([0, 128, 255], gain_q12=0x1000, offset=0), [0, 128, 255]
        )
        np.testing.assert_array_equal(
            brightness_gain([0, 200], gain_q12=0x2000, offset=10), [10, 255]
        )
        np.testing.assert_array_equal(
            brightness_gain([0, 255], gain_q12=0x1000, offset=-200), [0, 55]
        )

    def test_gamma_lut_maps_all_addresses_and_can_bypass(self) -> None:
        lut = np.arange(255, -1, -1, dtype=np.uint8)
        np.testing.assert_array_equal(gamma_lut([0, 1, 255], lut), [255, 254, 0])
        np.testing.assert_array_equal(gamma_lut([0, 1, 255], lut, enable=False), [0, 1, 255])

    def test_bilinear_interp_matches_two_stage_q16_truncation(self) -> None:
        self.assertEqual(
            bilinear_interp(100, 200, 50, 150, dx_q16=32768, dy_q16=32768), 125
        )
        np.testing.assert_array_equal(
            bilinear_interp(
                [10, 20, 30],
                [30, 40, 50],
                [50, 60, 70],
                [70, 80, 90],
                dx_q16=32768,
                dy_q16=32768,
            ),
            [40, 50, 60],
        )
        self.assertEqual(bilinear_interp(1, 2, 3, 4, 100, 200, coord_valid=False), 0)

    def test_line_buffer_model_emits_real_and_two_flush_rows(self) -> None:
        image = np.array([[1, 2, 3], [4, 5, 6]], dtype=np.uint8)
        taps = line_buffer_taps(image)
        self.assertEqual(taps.shape, (4, 3, 3))
        np.testing.assert_array_equal(taps[0, 1], [0, 0, 2])
        np.testing.assert_array_equal(taps[1, 1], [0, 2, 5])
        np.testing.assert_array_equal(taps[2, 1], [2, 5, 0])
        np.testing.assert_array_equal(taps[3, 1], [5, 0, 0])

    def test_window_model_zero_pads_all_four_corners(self) -> None:
        image = np.array([[1, 2, 3], [4, 5, 6]], dtype=np.uint8)
        windows = window_3x3(image)
        np.testing.assert_array_equal(windows[0, 0], [[0, 0, 0], [0, 1, 2], [0, 4, 5]])
        np.testing.assert_array_equal(windows[1, 2], [[2, 3, 0], [5, 6, 0], [0, 0, 0]])

    def test_gaussian_uses_121_kernel_and_truncates(self) -> None:
        impulse = np.zeros((3, 3), dtype=np.uint8)
        impulse[1, 1] = 255
        self.assertEqual(gaussian_3x3(impulse), 63)
        self.assertEqual(gaussian_3x3(np.full((3, 3), 255, dtype=np.uint8)), 255)

    def test_sobel_returns_l1_gradient(self) -> None:
        vertical_edge = np.array([[0, 0, 255], [0, 0, 255], [0, 0, 255]], dtype=np.uint8)
        self.assertEqual(sobel_3x3(vertical_edge), 1020)
        self.assertEqual(sobel_3x3(np.full((3, 3), 77, dtype=np.uint8)), 0)

    def test_threshold_is_strictly_greater_than(self) -> None:
        np.testing.assert_array_equal(threshold([99, 100, 101], 100), [0, 0, 1])

    def test_morphology_selects_or_for_dilation_and_and_for_erosion(self) -> None:
        one_foreground = np.zeros((3, 3), dtype=np.uint8)
        one_foreground[1, 1] = 1
        self.assertEqual(morphology_3x3(one_foreground, dilate=True), 1)
        self.assertEqual(morphology_3x3(one_foreground, dilate=False), 0)
        self.assertEqual(morphology_3x3(np.ones((3, 3), dtype=np.uint8), dilate=False), 1)


if __name__ == "__main__":
    unittest.main()
