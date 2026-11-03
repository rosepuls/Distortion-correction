"""Small image-level checks for the HDMI verification measurements."""

import unittest

import cv2
import numpy as np

from host.verification.measure_hdmi_sfr import (
    compute_sfr, fit_edge, measure_black_border, measure_grid_straightness,
)


class VerificationMetricsTests(unittest.TestCase):
    def test_grid_straightness_detects_a_straight_board(self):
        image = np.full((480, 640, 3), 235, np.uint8)
        for row in range(7):
            for col in range(10):
                color = (35, 35, 35) if (row + col) % 2 else (235, 235, 235)
                cv2.rectangle(image, (70 + col * 50, 60 + row * 50),
                              (120 + col * 50, 110 + row * 50), color, -1)
        result = measure_grid_straightness(image)
        self.assertEqual(result["inner_corners"], [9, 6])
        self.assertLess(result["p95_px"], 0.5)

    def test_black_border_only_counts_boundary_connected_black(self):
        image = np.full((100, 160, 3), 180, np.uint8)
        image[:5] = 0
        image[40:60, 70:90] = 0
        result, mask = measure_black_border(image)
        self.assertEqual(result["pixels"], 5 * 160)
        self.assertAlmostEqual(result["percent"], 5.0)
        self.assertEqual(int(mask[50, 80]), 0)

    def test_input_photo_discounts_preexisting_dark_content(self):
        source = np.full((100, 160, 3), 180, np.uint8)
        source[:, :40] = 0
        output = source.copy()
        output[:5] = 0
        result, mask = measure_black_border(output, reference_input=source)
        self.assertEqual(result["pixels"], 5 * 160 - 5 * 40)
        self.assertAlmostEqual(result["percent"], 3.75)
        self.assertEqual(int(mask[80, 10]), 0)

    def test_clean_slanted_edge_produces_sfr_curve(self):
        yy, xx = np.indices((140, 160))
        edge_image = np.where(xx >= 72 + 0.12 * yy, 220, 20).astype(np.uint8)
        edge_image = cv2.GaussianBlur(edge_image, (0, 0), 1.2)
        fit = fit_edge(edge_image, "vertical")
        frequency, sfr, contrast = compute_sfr(edge_image, fit)
        self.assertGreater(contrast, 150)
        self.assertGreater(float(np.interp(0.1, frequency, sfr)),
                           float(np.interp(0.3, frequency, sfr)))


if __name__ == "__main__":
    unittest.main()
