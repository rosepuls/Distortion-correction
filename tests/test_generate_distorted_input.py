from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "software"))
sys.path.insert(0, str(PROJECT_ROOT / "software" / "sim_assets"))

from distortion_float import CameraModel
from generate_distorted_input import inverse_distortion_map


class GenerateDistortedInputTests(unittest.TestCase):
    def test_identity_camera_inverse_map_preserves_pixel_coordinates(self) -> None:
        camera = CameraModel(fx=4.0, fy=4.0, cx=2.0, cy=2.0)

        source_x_q19, source_y_q19 = inverse_distortion_map(5, 5, camera)

        expected_axis = np.arange(5, dtype=np.int64) << 19
        np.testing.assert_array_equal(source_x_q19[2], expected_axis)
        np.testing.assert_array_equal(source_y_q19[:, 2], expected_axis)

    def test_negative_radial_distortion_inverse_moves_edge_sample_outward(self) -> None:
        camera = CameraModel(
            fx=4.0,
            fy=4.0,
            cx=2.0,
            cy=2.0,
            k1=-0.25,
            k2=0.05,
        )

        source_x_q19, _ = inverse_distortion_map(5, 5, camera)

        self.assertGreater(int(source_x_q19[2, 3]), 3 << 19)

    def test_inverse_map_rejects_nonpositive_iteration_count(self) -> None:
        camera = CameraModel(fx=4.0, fy=4.0, cx=2.0, cy=2.0)

        with self.assertRaisesRegex(ValueError, "iterations"):
            inverse_distortion_map(5, 5, camera, iterations=0)


if __name__ == "__main__":
    unittest.main()
