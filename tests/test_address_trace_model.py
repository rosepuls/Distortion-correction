from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
if str(SOFTWARE_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_DIR))


class AddressTraceModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        try:
            cls.model = importlib.import_module("address_trace_model")
        except ModuleNotFoundError as exc:
            cls.model = None
            cls.import_error = exc

    def setUp(self) -> None:
        if self.model is None:
            self.fail(f"address_trace_model is not implemented: {self.import_error}")

    def test_logical_address_uses_pixels_not_rgb_bytes(self) -> None:
        self.assertEqual(self.model.logical_pixel_address(3, 2, 8), 19)

    def test_valid_request_contains_four_row_major_neighbors(self) -> None:
        requests, metrics = self.model.generate_address_trace(
            np.array([[1]]),
            np.array([[1]]),
            np.array([[True]]),
            4,
            4,
        )

        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].output_index, 0)
        self.assertEqual(requests[0].x0, 1)
        self.assertEqual(requests[0].y0, 1)
        self.assertEqual(requests[0].addresses, (5, 6, 9, 10))
        self.assertEqual(metrics.total_outputs, 1)
        self.assertEqual(metrics.valid_outputs, 1)
        self.assertEqual(metrics.total_source_reads, 4)
        self.assertEqual(metrics.logical_bytes_read, 12)

    def test_invalid_coordinate_generates_no_memory_request(self) -> None:
        requests, metrics = self.model.generate_address_trace(
            np.array([[3]]),
            np.array([[1]]),
            np.array([[False]]),
            4,
            4,
        )

        self.assertEqual(requests, [])
        self.assertEqual(metrics.total_outputs, 1)
        self.assertEqual(metrics.valid_outputs, 0)
        self.assertEqual(metrics.invalid_outputs, 1)
        self.assertEqual(metrics.total_source_reads, 0)

    def test_last_column_is_invalid_even_when_coord_valid_is_true(self) -> None:
        requests, metrics = self.model.generate_address_trace(
            np.array([[3]]),
            np.array([[1]]),
            np.array([[True]]),
            4,
            4,
        )

        self.assertEqual(requests, [])
        self.assertEqual(metrics.invalid_outputs, 1)

    def test_custom_frame_stride_is_used_for_addresses(self) -> None:
        requests, _ = self.model.generate_address_trace(
            np.array([[2]]),
            np.array([[1]]),
            np.array([[True]]),
            4,
            4,
            frame_stride_pixels=8,
        )

        self.assertEqual(requests[0].addresses, (10, 11, 18, 19))

    def test_repeated_source_reads_are_reported(self) -> None:
        requests, metrics = self.model.generate_address_trace(
            np.array([[1, 2]]),
            np.array([[1, 1]]),
            np.array([[True, True]]),
            8,
            8,
        )

        self.assertEqual(len(requests), 2)
        self.assertEqual(metrics.total_source_reads, 8)
        self.assertEqual(metrics.unique_source_addresses, 6)
        self.assertEqual(metrics.repeated_source_reads, 2)


if __name__ == "__main__":
    unittest.main()
