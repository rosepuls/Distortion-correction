"""Focused tests for host-side lighting selection; no camera or UART required."""

import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest.mock import patch

import numpy as np

from lighting_profile import LightingSelector, analyze_bgr, classify_lighting


class LightingProfileTests(unittest.TestCase):
    def test_uniform_scenes(self):
        cases = [(18, 2), (60, 1), (125, 0), (210, 3), (235, 4)]
        for level, profile in cases:
            with self.subTest(level=level):
                frame = np.full((32, 40, 3), level, dtype=np.uint8)
                self.assertEqual(classify_lighting(analyze_bgr(frame)), profile)

    def test_highlight_ratio_detects_mixed_scene(self):
        frame = np.full((40, 40, 3), 100, dtype=np.uint8)
        frame[:8] = 255
        metrics = analyze_bgr(frame, sample_stride=1)
        self.assertAlmostEqual(metrics.highlight_ratio, 0.2)
        self.assertEqual(classify_lighting(metrics), 3)

    def test_local_highlight_is_detected_below_global_threshold(self):
        frame = np.full((128, 128, 3), 120, dtype=np.uint8)
        frame[16:40, 16:40] = 255
        metrics = analyze_bgr(frame, sample_stride=1)
        self.assertLess(metrics.highlight_ratio, 0.1)
        self.assertEqual(classify_lighting(metrics), 3)

    def test_local_shadow_is_detected_below_global_threshold(self):
        frame = np.full((128, 128, 3), 125, dtype=np.uint8)
        frame[0:32, 0:32] = 20
        metrics = analyze_bgr(frame, sample_stride=1)
        self.assertLess(metrics.dark_ratio, 0.35)
        self.assertEqual(classify_lighting(metrics), 1)

    def test_tiny_dark_patch_does_not_change_normal_scene(self):
        frame = np.full((128, 128, 3), 125, dtype=np.uint8)
        frame[0:8, 0:8] = 20
        self.assertEqual(classify_lighting(analyze_bgr(frame, sample_stride=1)), 0)

    def test_mixed_local_highlight_and_shadow_has_own_profile(self):
        frame = np.full((128, 128, 3), 125, dtype=np.uint8)
        frame[0:32, 0:32] = 255
        frame[96:128, 96:128] = 20
        self.assertEqual(classify_lighting(analyze_bgr(frame, sample_stride=1)), 5)

    def test_dark_scene_with_large_clipped_area_is_mixed(self):
        frame = np.full((40, 40, 3), 20, dtype=np.uint8)
        frame[:8] = 255
        self.assertEqual(classify_lighting(analyze_bgr(frame, sample_stride=1)), 5)

    def test_luma_uses_bgr_channel_order(self):
        red = np.array([[[0, 0, 255]]], dtype=np.uint8)
        blue = np.array([[[255, 0, 0]]], dtype=np.uint8)
        self.assertGreater(analyze_bgr(red).mean, analyze_bgr(blue).mean)

    def test_three_consecutive_frames_to_switch(self):
        selector = LightingSelector(stable_frames=3)
        self.assertEqual(selector.update(2), 0)
        self.assertEqual(selector.update(2), 0)
        self.assertEqual(selector.update(2), 2)
        self.assertEqual(selector.update(4), 2)
        self.assertEqual(selector.update(2), 2)
        self.assertEqual(selector.update(4), 2)
        self.assertEqual(selector.update(4), 2)
        self.assertEqual(selector.update(4), 4)

    def test_invalid_frames_and_profiles(self):
        with self.assertRaises(ValueError):
            analyze_bgr(np.zeros((10, 10), dtype=np.uint8))
        with self.assertRaises(ValueError):
            analyze_bgr(np.zeros((0, 10, 3), dtype=np.uint8))
        with self.assertRaises(ValueError):
            analyze_bgr(np.zeros((10, 10, 3), dtype=np.uint8), sample_stride=0)
        with self.assertRaises(ValueError):
            LightingSelector().update(6)

    def test_preview_reads_video_without_uart(self):
        from preview_lighting_profiles import main

        class FakeCapture:
            def __init__(self):
                self.frames = [np.full((16, 16, 3), 18, dtype=np.uint8) for _ in range(3)]
                self.frames += [np.full((16, 16, 3), 125, dtype=np.uint8) for _ in range(3)]

            def isOpened(self):
                return True

            def read(self):
                return (True, self.frames.pop(0)) if self.frames else (False, None)

            def release(self):
                pass

        output = StringIO()
        with patch("preview_lighting_profiles.cv2.VideoCapture", return_value=FakeCapture()):
            with redirect_stdout(output):
                self.assertEqual(main(["--source", "sample.avi", "--report-every", "1"]), 0)
        self.assertIn("active=2:night_strong", output.getvalue())
        self.assertIn("active=0:bypass", output.getvalue())


if __name__ == "__main__":
    unittest.main()
