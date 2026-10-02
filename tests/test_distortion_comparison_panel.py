from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PIL import Image


SIM_ASSET_DIR = Path(__file__).resolve().parents[1] / "software" / "sim_assets"
sys.path.insert(0, str(SIM_ASSET_DIR))

from create_comparison_panel import create_comparison_panel


class DistortionComparisonPanelTests(unittest.TestCase):
    def test_equal_golden_and_rtl_frames_produce_a_black_difference_tile(self) -> None:
        source = Image.new("RGB", (4, 4), color=(255, 0, 0))
        corrected = Image.new("RGB", (4, 4), color=(12, 34, 56))

        panel = create_comparison_panel(source, corrected, corrected)

        self.assertEqual(panel.size, (8, 48))
        self.assertEqual(panel.getpixel((4, 44)), (0, 0, 0))

    def test_difference_tile_amplifies_channel_errors_by_eight(self) -> None:
        source = Image.new("RGB", (4, 4), color=(0, 0, 0))
        golden = Image.new("RGB", (4, 4), color=(10, 20, 30))
        rtl = Image.new("RGB", (4, 4), color=(12, 17, 31))

        panel = create_comparison_panel(source, golden, rtl)

        self.assertEqual(panel.getpixel((4, 44)), (16, 24, 8))


if __name__ == "__main__":
    unittest.main()
