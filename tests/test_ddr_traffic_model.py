from __future__ import annotations

import sys
import unittest
from pathlib import Path


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))

from ddr_traffic_model import (
    frame_traffic_totals,
    rgbx_pixel_byte_address,
    tile_row_bursts,
)


class DdrTrafficModelTests(unittest.TestCase):
    def test_eight_rgbx_pixels_fit_one_256_bit_beat(self) -> None:
        self.assertEqual(rgbx_pixel_byte_address(8, 0, 1920), 32)

    def test_tile_row_is_one_four_beat_burst_per_valid_row(self) -> None:
        bursts = tile_row_bursts(1, 2, 1920, 1080)

        self.assertEqual(len(bursts), 4)
        self.assertTrue(all(beats == 4 for _address, beats in bursts))
        self.assertEqual(bursts[0][0], (2 * 4 * 1920 + 32) * 4)

    def test_right_edge_tile_reduces_burst_count(self) -> None:
        bursts = tile_row_bursts(1, 0, 40, 8)

        self.assertEqual(len(bursts), 4)
        self.assertTrue(all(beats == 1 for _address, beats in bursts))

    def test_1080p30_four_rgbx_stream_baseline(self) -> None:
        totals = frame_traffic_totals(1920, 1080, 30)

        self.assertEqual(totals.input_bytes, 8_294_400)
        self.assertEqual(totals.source_bytes, 8_294_400)
        self.assertEqual(totals.output_bytes, 8_294_400)
        self.assertEqual(totals.display_bytes, 8_294_400)
        self.assertEqual(totals.total_bytes, 33_177_600)
        self.assertEqual(totals.bytes_per_second, 995_328_000)


if __name__ == "__main__":
    unittest.main()
