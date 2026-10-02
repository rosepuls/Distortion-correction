from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOFTWARE_DIR = PROJECT_ROOT / "software"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
for directory in (SOFTWARE_DIR, SCRIPTS_DIR):
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))

from address_trace_model import generate_address_trace
from cache_model import CacheConfig, simulate_cache
from evaluate_pixel_fetch_cache import build_report


class ThroughputModelTests(unittest.TestCase):
    def test_skewed_set_hash_preserves_vertical_tile_working_set(self) -> None:
        tile_rows = np.arange(9, dtype=np.int64)
        x0 = np.ones(tile_rows.size * 2, dtype=np.int64)
        y0 = np.concatenate((tile_rows * 4 + 1, tile_rows * 4 + 1))
        requests, _ = generate_address_trace(
            x0,
            y0,
            np.ones_like(x0, dtype=bool),
            width=512,
            height=40,
        )

        linear = CacheConfig(
            "linear_16x8",
            tile_width=32,
            tile_height=4,
            burst_length=32,
            set_count=16,
            ways=8,
            pixel_bytes=4,
            burst_beats=4,
            set_hash="linear",
        )
        skewed = CacheConfig(
            "skewed_16x8",
            tile_width=32,
            tile_height=4,
            burst_length=32,
            set_count=16,
            ways=8,
            pixel_bytes=4,
            burst_beats=4,
            set_hash="skewed_x_minus_y",
        )

        linear_metrics = simulate_cache(requests, 512, 40, linear)
        skewed_metrics = simulate_cache(requests, 512, 40, skewed)

        self.assertEqual(linear_metrics.cache_misses, 18)
        self.assertEqual(skewed_metrics.cache_misses, 9)

    def test_rgbx_tile_config_reports_physical_tile_load(self) -> None:
        x0 = np.array([[1]], dtype=np.int64)
        y0 = np.array([[1]], dtype=np.int64)
        valid = np.array([[True]], dtype=bool)
        requests, _ = generate_address_trace(x0, y0, valid, 64, 8)

        config = CacheConfig(
            "tile_32x4_128_4way",
            tile_width=32,
            tile_height=4,
            burst_length=32,
            set_count=32,
            ways=4,
            pixel_bytes=4,
            burst_beats=4,
        )
        metrics = simulate_cache(requests, 64, 8, config)

        self.assertEqual(metrics.ddr_read_bytes, 512)
        self.assertEqual(metrics.ddr_bursts, 4)
        self.assertEqual(metrics.ddr_beats, 16)
        self.assertEqual(metrics.average_burst_beats, 4.0)

    def test_report_can_evaluate_a_complete_raster_at_a_requested_frame_rate(self) -> None:
        report = build_report(width=8, height=6, fps=30, full_raster=True)

        self.assertIn("image size: `8×6`", report)
        self.assertIn("frame rate: `30 fps`", report)
        self.assertIn("raster: `full`", report)
        self.assertIn("tile_32x4_128_8way_skewed", report)
        self.assertIn("retains eight ways per set", report)


if __name__ == "__main__":
    unittest.main()
