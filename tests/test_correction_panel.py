from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PIL import Image


SIM_ASSET_DIR = Path(__file__).resolve().parents[1] / "software" / "sim_assets"
sys.path.insert(0, str(SIM_ASSET_DIR))

from create_correction_panel import create_correction_panel


class CorrectionPanelTests(unittest.TestCase):
    def test_matching_rtl_and_golden_produce_black_difference_tile(self) -> None:
        clean = Image.new("RGB", (4, 4), color=(255, 255, 255))
        distorted = Image.new("RGB", (4, 4), color=(255, 0, 0))
        corrected = Image.new("RGB", (4, 4), color=(10, 20, 30))

        panel = create_correction_panel(clean, distorted, corrected, corrected)

        self.assertEqual(panel.size, (8, 48))
        self.assertEqual(panel.getpixel((4, 44)), (0, 0, 0))


if __name__ == "__main__":
    unittest.main()
