from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))

import bilinear_model
from bilinear_model import bilinear_sample


class BilinearSampleTests(unittest.TestCase):
    def test_fixed_reference_sample_returns_130(self) -> None:
        result = bilinear_sample(
            p00=100.0,
            p10=120.0,
            p01=140.0,
            p11=160.0,
            dx=0.3,
            dy=0.6,
        )

        self.assertAlmostEqual(float(result), 130.0, places=12)


class BilinearRemapTests(unittest.TestCase):
    def _remap(self, image: np.ndarray, map_x: np.ndarray, map_y: np.ndarray) -> np.ndarray:
        remap = getattr(bilinear_model, "bilinear_remap", None)
        if remap is None:
            self.fail("bilinear_remap is not implemented")
        return remap(image, map_x, map_y)

    def test_identity_map_preserves_interior_and_blacks_missing_neighbors(self) -> None:
        image = np.array(
            [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9],
            ],
            dtype=np.uint8,
        )
        map_y, map_x = np.indices(image.shape, dtype=np.float64)

        actual = self._remap(image, map_x, map_y)

        expected = np.array(
            [
                [1.0, 2.0, 0.0],
                [4.0, 5.0, 0.0],
                [0.0, 0.0, 0.0],
            ]
        )
        np.testing.assert_allclose(actual, expected, rtol=0.0, atol=0.0)

    def test_out_of_bounds_coordinates_use_black_border(self) -> None:
        image = np.arange(16, dtype=np.uint8).reshape(4, 4)
        map_x = np.array([[-0.1, 3.0], [1.0, 1.0]])
        map_y = np.array([[1.0, 1.0], [-0.1, 3.0]])

        actual = self._remap(image, map_x, map_y)

        np.testing.assert_array_equal(actual, np.zeros((2, 2), dtype=np.float64))

    def test_rgb_channels_are_interpolated_independently(self) -> None:
        image = np.array(
            [
                [[0, 10, 20], [20, 30, 40]],
                [[40, 50, 60], [60, 70, 80]],
            ],
            dtype=np.uint8,
        )
        map_x = np.array([[0.5]])
        map_y = np.array([[0.5]])

        actual = self._remap(image, map_x, map_y)

        np.testing.assert_allclose(actual, np.array([[[30.0, 40.0, 50.0]]]))


if __name__ == "__main__":
    unittest.main()
