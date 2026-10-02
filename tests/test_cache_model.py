from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))

from address_trace_model import generate_address_trace
from cache_model import NO_CACHE, ROW_WINDOW, TILE_16X4, simulate_cache


class CacheModelTests(unittest.TestCase):
    def test_tile_cache_reuses_repeated_neighbor_pixels(self) -> None:
        requests, _ = generate_address_trace(
            np.full((1, 20), 1),
            np.full((1, 20), 1),
            np.full((1, 20), True),
            32,
            8,
        )

        no_cache = simulate_cache(requests, 32, 8, NO_CACHE)
        tile = simulate_cache(requests, 32, 8, TILE_16X4)

        self.assertEqual(no_cache.source_pixel_requests, 80)
        self.assertEqual(no_cache.ddr_read_pixels, 80)
        self.assertEqual(no_cache.cache_hits, 0)
        self.assertLess(tile.ddr_read_pixels, no_cache.ddr_read_pixels)
        self.assertGreater(tile.cache_hit_rate, 0.0)

    def test_row_window_loads_only_in_bounds_aligned_region(self) -> None:
        requests, _ = generate_address_trace(
            np.array([[6]]),
            np.array([[6]]),
            np.array([[True]]),
            8,
            8,
        )

        metrics = simulate_cache(requests, 8, 8, ROW_WINDOW)

        self.assertEqual(metrics.cache_capacity_pixels, 8)
        self.assertEqual(metrics.ddr_read_pixels, 8)
        self.assertEqual(metrics.ddr_bursts, 2)
        self.assertEqual(metrics.average_burst_length, 4.0)

    def test_invalid_outputs_do_not_enter_cache_simulator(self) -> None:
        requests, _ = generate_address_trace(
            np.array([[7]]),
            np.array([[2]]),
            np.array([[True]]),
            8,
            8,
        )

        metrics = simulate_cache(requests, 8, 8, TILE_16X4)

        self.assertEqual(metrics.output_requests, 0)
        self.assertEqual(metrics.source_pixel_requests, 0)
        self.assertEqual(metrics.ddr_read_pixels, 0)
        self.assertEqual(metrics.ddr_bursts, 0)

    def test_cache_metrics_are_deterministic(self) -> None:
        requests, _ = generate_address_trace(
            np.array([[1, 2, 4]]),
            np.array([[1, 1, 2]]),
            np.array([[True, True, True]]),
            8,
            8,
        )

        first = simulate_cache(requests, 8, 8, TILE_16X4)
        second = simulate_cache(requests, 8, 8, TILE_16X4)

        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
