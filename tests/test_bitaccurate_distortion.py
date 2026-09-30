from __future__ import annotations

import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

import numpy as np


SOFTWARE_DIR = Path(__file__).resolve().parents[1] / "software"
sys.path.insert(0, str(SOFTWARE_DIR))


class BitAccurateDistortionTests(unittest.TestCase):
    def _module(self):
        try:
            import bitaccurate_distortion
        except ModuleNotFoundError:
            self.fail("bitaccurate_distortion is not implemented")
        return bitaccurate_distortion

    def test_zero_coefficients_preserve_integer_coordinates(self) -> None:
        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=2.0,
            fy=2.0,
            cx=1.5,
            cy=1.0,
        )

        map_x, map_y = model.build_distortion_map_fixed(4, 3, camera)

        expected_x = np.array(
            [[0, 1, 2, 3], [0, 1, 2, 3], [0, 1, 2, 3]], dtype=np.int64
        )
        expected_y = np.array(
            [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2]], dtype=np.int64
        )
        scale = 1 << model.DEFAULT_CONFIG.src_coord_frac_bits
        np.testing.assert_array_equal(map_x, expected_x * scale)
        np.testing.assert_array_equal(map_y, expected_y * scale)

    def test_quantized_horner_identity_keeps_integer_source_coordinates(self) -> None:
        """Dropping the radial identity term must not move the optical centre."""

        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=512.0,
            fy=512.0,
            cx=2.0,
            cy=1.0,
        )

        source_x, source_y = model.source_coordinates_horner_quantized(
            [2], [1], camera, model.InternalFormat.default_candidate()
        )

        self.assertEqual(int(source_x[0]), 2 << 19)
        self.assertEqual(int(source_y[0]), 1 << 19)

    def test_candidate_metrics_detects_a_coarse_validity_boundary_error(self) -> None:
        """Changing a candidate's border decision is a functional failure."""

        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=2.0,
            fy=2.0,
            cx=1.5,
            cy=1.0,
        )
        coarse = model.InternalFormat(
            centered_width=6,
            centered_frac_bits=0,
            inverse_width=4,
            inverse_frac_bits=0,
            normalized_width=6,
            normalized_frac_bits=0,
            coefficient_width=4,
            coefficient_frac_bits=0,
            radius_width=6,
            radius_frac_bits=0,
            radial_width=6,
            radial_frac_bits=0,
            distorted_width=6,
            distorted_frac_bits=0,
            focal_width=6,
            focal_frac_bits=0,
        )

        metrics = model.evaluate_internal_format(4, 3, camera, coarse)

        self.assertGreater(metrics.coord_valid_mismatches, 0)

    def test_default_candidate_preserves_identity_validity(self) -> None:
        """The selected-width identity mapping must retain every border decision."""

        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=512.0,
            fy=512.0,
            cx=2.0,
            cy=1.0,
        )

        metrics = model.evaluate_internal_format(
            5, 3, camera, model.InternalFormat.default_candidate()
        )

        self.assertEqual(metrics.coord_valid_mismatches, 0)

    def test_quantized_horner_unit_radial_term_maps_to_two_pixels(self) -> None:
        """Adding the Horner coefficient twice would turn this into 3 pixels."""

        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=1.0,
            fy=1.0,
            cx=0.0,
            cy=0.0,
            k1=1.0,
        )

        source_x, source_y = model.source_coordinates_horner_quantized(
            [1], [0], camera, model.InternalFormat.default_candidate()
        )

        self.assertEqual(int(source_x[0]), 2 << 19)
        self.assertEqual(int(source_y[0]), 0)

    def test_format_scan_writes_candidate_table(self) -> None:
        """Removing a required report column must fail the format-selection gate."""

        project_root = Path(__file__).resolve().parents[1]
        script = project_root / "scripts" / "scan_distortion_formats.py"
        with tempfile.TemporaryDirectory(dir=project_root / "result") as directory:
            report = Path(directory) / "format-report.md"
            completed = subprocess.run(
                [sys.executable, str(script), "--output", str(report)],
                cwd=project_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report_text = report.read_text(encoding="utf-8")

        for heading in (
            "Candidate",
            "Max error",
            "Mean error",
            "coord_valid mismatches",
            "Selected",
        ):
            self.assertIn(heading, report_text)

    def test_format_scan_writes_q18_golden_vectors(self) -> None:
        """Removing Q18 vector export would leave RTL without a golden oracle."""

        project_root = Path(__file__).resolve().parents[1]
        script = project_root / "scripts" / "scan_distortion_formats.py"
        with tempfile.TemporaryDirectory(dir=project_root / "result") as directory:
            vectors = Path(directory) / "vectors.txt"
            completed = subprocess.run(
                [sys.executable, str(script), "--output", str(Path(directory) / "report.md"), "--vectors", str(vectors)],
                cwd=project_root, capture_output=True, text=True, check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            first_data_line = next(line for line in vectors.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#"))
        self.assertEqual(len(first_data_line.split()), 12)

    def test_coordinate_trace_returns_q_format_split_for_identity_mapping(self) -> None:
        """A missing Q13.19-to-Q0.16 split would break RTL vector generation."""

        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=2.0,
            fy=2.0,
            cx=1.5,
            cy=1.0,
        )

        trace = model.source_coordinate_trace(2, 1, camera, width=4, height=3)

        self.assertEqual(trace["src_x"], 2 << 19)
        self.assertEqual(trace["src_y"], 1 << 19)
        self.assertEqual(trace["x0"], 2)
        self.assertEqual(trace["y0"], 1)
        self.assertEqual(trace["dx"], 0)
        self.assertEqual(trace["dy"], 0)
        self.assertTrue(trace["coord_valid"])

    def test_unit_x_radial_term_maps_to_two_pixels(self) -> None:
        model = self._module()
        camera = model.FixedPointCameraModel.from_parameters(
            fx=1.0,
            fy=1.0,
            cx=0.0,
            cy=0.0,
            k1=1.0,
        )

        map_x, map_y = model.source_coordinates_fixed([1], [0], camera)
        scale = 1 << model.DEFAULT_CONFIG.src_coord_frac_bits

        self.assertEqual(int(map_x[0]), 2 * scale)
        self.assertEqual(int(map_y[0]), 0)

    def test_negative_fixed_coordinate_uses_mathematical_floor(self) -> None:
        model = self._module()
        scale = 1 << model.DEFAULT_CONFIG.src_coord_frac_bits

        x0, dx = model.split_fixed_coordinate(-scale // 4)

        self.assertEqual(x0, -1)
        self.assertEqual(dx, 3 * scale // 4)

    def test_bilinear_validity_requires_four_source_neighbors(self) -> None:
        model = self._module()
        scale = 1 << model.DEFAULT_CONFIG.src_coord_frac_bits

        x0, y0, dx, dy, valid = model.split_source_coordinates(
            np.array([[0, 1, 2]], dtype=np.int64) * scale,
            np.array([[0, 0, 0]], dtype=np.int64) * scale,
            width=3,
            height=2,
        )

        np.testing.assert_array_equal(x0, [[0, 1, 2]])
        np.testing.assert_array_equal(y0, [[0, 0, 0]])
        np.testing.assert_array_equal(dx, [[0, 0, 0]])
        np.testing.assert_array_equal(dy, [[0, 0, 0]])
        np.testing.assert_array_equal(valid, [[True, True, False]])

    def test_integer_bilinear_interpolation_truncates_after_two_stages(self) -> None:
        model = self._module()

        image = np.array([[100, 120], [140, 160]], dtype=np.uint8)
        actual = model.bilinear_remap_fixed(
            image,
            np.array([[model.DEFAULT_CONFIG.src_coord_scale // 2]], dtype=np.int64),
            np.array([[model.DEFAULT_CONFIG.src_coord_scale // 2]], dtype=np.int64),
        )

        np.testing.assert_array_equal(actual, np.array([[130]], dtype=np.uint8))

    def test_zero_distortion_correction_obeys_black_boundary_policy(self) -> None:
        model = self._module()
        image = np.array(
            [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9],
            ],
            dtype=np.uint8,
        )
        camera = model.FixedPointCameraModel.from_parameters(
            fx=2.0,
            fy=2.0,
            cx=1.0,
            cy=1.0,
        )

        corrected, _, _ = model.correct_distortion_fixed(image, camera)

        expected = np.array(
            [
                [1, 2, 0],
                [4, 5, 0],
                [0, 0, 0],
            ],
            dtype=np.uint8,
        )
        np.testing.assert_array_equal(corrected, expected)


if __name__ == "__main__":
    unittest.main()
