import sys
import unittest
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from stage13_motion_stabilization import (  # noqa: E402
    ShakeOnlyCompensator,
    estimate_translation,
    make_stage13_request,
    resize_for_fpga,
)


def textured_frame():
    rng = np.random.default_rng(13)
    gray = rng.integers(0, 256, (240, 320), dtype=np.uint8)
    return cv2.GaussianBlur(gray, (5, 5), 0.8)


def translated(image, dx, dy):
    matrix = np.float32([[1, 0, dx], [0, 1, dy]])
    return cv2.warpAffine(image, matrix, (image.shape[1], image.shape[0]))


class Stage13MotionTests(unittest.TestCase):
    def test_camera_frame_resizes_to_fpga_dimensions_even_when_aspect_differs(self):
        frame = np.zeros((480, 640, 3), dtype=np.uint8)

        resized = resize_for_fpga(frame, 1280, 720)

        self.assertEqual(resized.shape, (720, 1280, 3))

    def test_sparse_flow_recovers_global_frame_translation(self):
        previous = textured_frame()
        current = translated(previous, 2.5, -1.5)

        dx, dy, confidence, inliers = estimate_translation(previous, current)

        self.assertAlmostEqual(dx, 2.5, delta=0.35)
        self.assertAlmostEqual(dy, -1.5, delta=0.35)
        self.assertGreaterEqual(confidence, 0.5)
        self.assertGreaterEqual(inliers, 12)

    def test_sustained_pan_is_not_accumulated_as_shake_compensation(self):
        detector = ShakeOnlyCompensator(alpha=0.25, max_correction_px=8.0)
        result = None
        for _ in range(80):
            result = detector.update(1.0, 0.0)

        correction_x, correction_y, trend_x, trend_y = result
        self.assertAlmostEqual(trend_x, 77.0, delta=0.02)
        self.assertAlmostEqual(correction_x, 3.0, delta=0.02)
        self.assertLess(abs(result[0] - detector.update(1.0, 0.0)[0]), 0.02)
        self.assertEqual(correction_y, 0.0)

    def test_alternating_camera_jitter_generates_bounded_compensation(self):
        detector = ShakeOnlyCompensator(alpha=0.25, max_correction_px=3.0)
        values = [detector.update(x, 0.0)[0] for x in (2.0, -2.0) * 8]

        self.assertGreater(max(values) - min(values), 1.0)
        self.assertLessEqual(max(abs(value) for value in values), 3.0)

    def test_static_scene_motion_does_not_create_compensation(self):
        detector = ShakeOnlyCompensator(alpha=0.18, max_correction_px=8.0)
        values = [detector.update(0.0, 0.0)[:2] for _ in range(20)]

        self.assertTrue(all(pair == (0.0, 0.0) for pair in values))

    def test_first_trusted_frame_shift_gets_same_sign_sampling_correction(self):
        detector = ShakeOnlyCompensator(alpha=0.25, max_correction_px=8.0)

        correction_x, correction_y, _, _ = detector.update(2.0, -1.0)

        self.assertGreater(correction_x, 0.0)
        self.assertLess(correction_y, 0.0)

    def test_uart_packet_keeps_homography_and_profile_and_encodes_q16_translation(self):
        rows = [0x40000000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x00010000]
        packet = make_stage13_request(0x1234, rows, 5, -1.25, 2.5)

        self.assertEqual(len(packet), 65)
        self.assertEqual(packet[:7], bytes((0xA5, 0x5A, 2, 1, 0x34, 0x12, 0x02)))
        self.assertEqual(packet[43], 5)
        self.assertEqual(int.from_bytes(packet[44:48], "little", signed=True), round(-1.25 * 65536))
        self.assertEqual(int.from_bytes(packet[48:52], "little", signed=True), round(2.5 * 65536))
        self.assertEqual(packet[52:63], bytes(11))
        crc = 0xFFFF
        for value in packet[2:63]:
            crc ^= value << 8
            for _ in range(8):
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
        self.assertEqual(packet[63:65], crc.to_bytes(2, "big"))
