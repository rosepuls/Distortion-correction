from __future__ import annotations

import sys
import unittest
from pathlib import Path


SIM_ASSET_DIR = Path(__file__).resolve().parents[1] / "software" / "sim_assets"
sys.path.insert(0, str(SIM_ASSET_DIR))

from compare_identity_mem import compare_identity_frame


class IdentityMemoryCompareTests(unittest.TestCase):
    def test_identity_frame_preserves_interior_and_blacks_last_row_column(self) -> None:
        source_words = [
            "000001", "000002", "000003",
            "000004", "000005", "000006",
        ]
        rtl_words = [
            "000001", "000002", "000000",
            "000000", "000000", "000000",
        ]

        mismatches = compare_identity_frame(
            source_words,
            rtl_words,
            width=3,
            height=2,
        )

        self.assertEqual(mismatches, [])

    def test_identity_frame_reports_wrong_interior_pixel_address(self) -> None:
        source_words = [
            "000001", "000002", "000003",
            "000004", "000005", "000006",
            "000007", "000008", "000009",
        ]
        rtl_words = [
            "000001", "000002", "000000",
            "000004", "0000FF", "000000",
            "000000", "000000", "000000",
        ]

        mismatches = compare_identity_frame(
            source_words,
            rtl_words,
            width=3,
            height=3,
        )

        self.assertEqual(mismatches, [(1, 1, "000005", "0000FF")])


if __name__ == "__main__":
    unittest.main()
