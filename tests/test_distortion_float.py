from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))


class DistortionFloatTests(unittest.TestCase):
    def _module(self):
        try:
            import distortion_float
        except ModuleNotFoundError:
            self.fail("distortion_float is not implemented")
        return distortion_float

    def test_zero_coefficients_produce_identity_map(self) -> None:
        model = self._module()
        camera = model.CameraModel(fx=2.0, fy=3.0, cx=1.5, cy=1.0)

        map_x, map_y = model.build_distortion_map(width=4, height=3, camera=camera)

        expected_x, expected_y = np.meshgrid(
            np.arange(4, dtype=np.float64),
            np.arange(3, dtype=np.float64),
        )
        np.testing.assert_allclose(map_x, expected_x, atol=1e-12)
        np.testing.assert_allclose(map_y, expected_y, atol=1e-12)

    def test_optical_center_remains_fixed_with_distortion(self) -> None:
        model = self._module()
        camera = model.CameraModel(
            fx=100.0,
            fy=120.0,
            cx=2.0,
            cy=2.0,
            k1=-0.3,
            k2=0.08,
            p1=0.01,
            p2=-0.02,
        )

        map_x, map_y = model.build_distortion_map(width=5, height=5, camera=camera)

        self.assertAlmostEqual(float(map_x[2, 2]), 2.0, places=12)
        self.assertAlmostEqual(float(map_y[2, 2]), 2.0, places=12)

    def test_radial_formula_maps_unit_x_to_two(self) -> None:
        model = self._module()
        camera = model.CameraModel(fx=1.0, fy=1.0, cx=0.0, cy=0.0, k1=1.0)

        source_x, source_y = model.source_coordinates(1.0, 0.0, camera)

        self.assertAlmostEqual(float(source_x), 2.0, places=12)
        self.assertAlmostEqual(float(source_y), 0.0, places=12)

    def test_zero_distortion_correction_uses_project_border_policy(self) -> None:
        model = self._module()
        image = np.array(
            [
                [1.0, 2.0, 3.0],
                [4.0, 5.0, 6.0],
                [7.0, 8.0, 9.0],
            ]
        )
        camera = model.CameraModel(fx=2.0, fy=2.0, cx=1.0, cy=1.0)

        corrected, map_x, map_y = model.correct_distortion(image, camera)

        expected = np.array(
            [
                [1.0, 2.0, 0.0],
                [4.0, 5.0, 0.0],
                [0.0, 0.0, 0.0],
            ]
        )
        np.testing.assert_allclose(corrected, expected, atol=1e-12)
        self.assertEqual(map_x.shape, image.shape)
        self.assertEqual(map_y.shape, image.shape)


if __name__ == "__main__":
    unittest.main()
