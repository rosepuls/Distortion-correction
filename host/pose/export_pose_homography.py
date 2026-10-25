"""Export planar FPGA mapping candidates from synthetic or tracked poses."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys
from typing import Iterator

import numpy as np

from planar_geometry import homography_from_board_poses, homography_from_relative_pose
from pose_geometry import load_calibration, relative_pose
from render_homography_reference import rotation_matrix
from track_pose import load_reference


SCHEMA = "pango-pose-homography-parameters-v1"
SCALE_NUMERATOR = 1 << 16
SCALE_DENOMINATOR = 1 << 30
SIGNED32_MIN = -(1 << 31)
SIGNED32_MAX = (1 << 31) - 1


def positive_float(text: str) -> float:
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("value must be finite and positive")
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pose-log", type=Path, help="track_pose.py JSONL; omit for synthetic poses")
    parser.add_argument("--calibration", type=Path, help="calibration.json for a real pose log")
    parser.add_argument("--reference", type=Path, help="reference_pose.json for a real pose log")
    parser.add_argument("--out", type=Path, default=Path("host/pose/output/pose_homography.jsonl"))
    parser.add_argument("--analyze-maps", action="store_true", help="compare full-frame floating and quantized coordinate maps")
    parser.add_argument("--analyze-reciprocal", action="store_true", help="evaluate the proposed integer LUT/Newton reciprocal path")
    parser.add_argument("--width", type=int, default=1280, help="synthetic image width")
    parser.add_argument("--height", type=int, default=720, help="synthetic image height")
    parser.add_argument("--fx", type=positive_float, default=900.0, help="synthetic focal length X in pixels")
    parser.add_argument("--fy", type=positive_float, default=900.0, help="synthetic focal length Y in pixels")
    parser.add_argument("--plane-distance-mm", type=positive_float, default=1000.0)
    args = parser.parse_args()
    supplied = [args.pose_log is not None, args.calibration is not None, args.reference is not None]
    if any(supplied) and not all(supplied):
        parser.error("--pose-log, --calibration and --reference must be supplied together")
    if args.width <= 1 or args.height <= 1:
        parser.error("image width and height must be greater than one")
    return args


def check_rotation(rotation: np.ndarray, label: str) -> np.ndarray:
    rotation = np.asarray(rotation, dtype=np.float64)
    if rotation.shape != (3, 3) or not np.isfinite(rotation).all():
        raise ValueError(f"{label} must be a finite 3x3 matrix")
    if (np.max(np.abs(rotation.T @ rotation - np.eye(3))) > 1e-3
            or abs(float(np.linalg.det(rotation)) - 1.0) > 1e-3):
        raise ValueError(f"{label} is not a rotation matrix")
    return rotation


def check_translation(translation: np.ndarray, label: str) -> np.ndarray:
    translation = np.asarray(translation, dtype=np.float64)
    if translation.shape != (3,) or not np.isfinite(translation).all():
        raise ValueError(f"{label} must be a finite 3-vector")
    return translation


def quantize_coefficients(homography: np.ndarray) -> dict:
    """Candidate coefficient registers; this is not a complete FPGA datapath."""
    scales = np.asarray([[SCALE_NUMERATOR] * 3] * 2 + [[SCALE_DENOMINATOR] * 3])
    raw = np.rint(homography * scales)
    if not np.isfinite(raw).all() or np.any(raw < SIGNED32_MIN) or np.any(raw > SIGNED32_MAX):
        raise ValueError("Homography coefficients exceed signed 32-bit candidate registers")
    integers = raw.astype(np.int64).tolist()
    words = [value for row in integers for value in row]
    return {
        "numerator_rows_format": "signed Q16.16",
        "denominator_row_format": "signed Q2.30",
        "source_coordinate_format": "signed Q16.16",
        "coefficient_rounding": "nearest integer, ties to even",
        "integer_rows": integers,
        "twos_complement_hex_rows": [
            [f"0x{value & 0xFFFFFFFF:08X}" for value in row] for row in integers
        ],
        "cfg_words_288bit_hex": "0x" + "".join(f"{value & 0xFFFFFFFF:08X}" for value in reversed(words)),
        "cfg_words_note": "word 0 (h00) occupies bits 31:0; this is bus packing, not UART byte order",
    }


def evaluate_map(homography: np.ndarray, width: int, height: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    u, v = np.meshgrid(np.arange(width, dtype=np.float64), np.arange(height, dtype=np.float64))
    denominator = homography[2, 0] * u + homography[2, 1] * v + homography[2, 2]
    safe = np.isfinite(denominator) & (np.abs(denominator) > 1e-12)
    d = np.where(safe, denominator, 1.0)
    x = (homography[0, 0] * u + homography[0, 1] * v + homography[0, 2]) / d
    y = (homography[1, 0] * u + homography[1, 1] * v + homography[1, 2]) / d
    return x, y, safe


def analyze_maps(homography: np.ndarray, coefficients: dict, width: int, height: int) -> dict:
    fixed = np.asarray(coefficients["integer_rows"], dtype=np.float64)
    fixed[:2] /= SCALE_NUMERATOR
    fixed[2] /= SCALE_DENOMINATOR
    reference_x, reference_y, reference_safe = evaluate_map(homography, width, height)
    candidate_x, candidate_y, candidate_safe = evaluate_map(fixed, width, height)

    representable = (
        (candidate_x >= SIGNED32_MIN / SCALE_NUMERATOR)
        & (candidate_x <= SIGNED32_MAX / SCALE_NUMERATOR)
        & (candidate_y >= SIGNED32_MIN / SCALE_NUMERATOR)
        & (candidate_y <= SIGNED32_MAX / SCALE_NUMERATOR)
    )
    candidate_x = np.rint(np.where(representable, candidate_x, 0.0) * SCALE_NUMERATOR) / SCALE_NUMERATOR
    candidate_y = np.rint(np.where(representable, candidate_y, 0.0) * SCALE_NUMERATOR) / SCALE_NUMERATOR
    reference_valid = (
        reference_safe & np.isfinite(reference_x) & np.isfinite(reference_y)
        & (reference_x >= 0) & (reference_x < width - 1)
        & (reference_y >= 0) & (reference_y < height - 1)
    )
    candidate_valid = (
        candidate_safe & representable
        & (candidate_x >= 0) & (candidate_x < width - 1)
        & (candidate_y >= 0) & (candidate_y < height - 1)
    )
    common = reference_valid & candidate_valid
    coordinate_error = np.maximum(
        np.abs(reference_x[common] - candidate_x[common]),
        np.abs(reference_y[common] - candidate_y[common]),
    )
    return {
        "floating_valid_pixels": int(np.count_nonzero(reference_valid)),
        "candidate_valid_pixels": int(np.count_nonzero(candidate_valid)),
        "valid_mask_difference_pixels": int(np.count_nonzero(reference_valid != candidate_valid)),
        "common_valid_pixels": int(np.count_nonzero(common)),
        "max_axis_coordinate_error_px": float(np.max(coordinate_error)) if coordinate_error.size else None,
        "p99_axis_coordinate_error_px": float(np.percentile(coordinate_error, 99)) if coordinate_error.size else None,
        "analysis_scope": "coefficient quantization and Q16.16 output rounding; FPGA arithmetic not modeled",
    }


def _rounded_signed_shift(value: np.ndarray, bits: int) -> np.ndarray:
    magnitude = (np.abs(value) + (1 << (bits - 1))) >> bits
    return np.where(value < 0, -magnitude, magnitude)


def analyze_reciprocal_model(homography: np.ndarray, coefficients: dict, width: int, height: int) -> dict:
    """Model a 1024-word reciprocal ROM and one fixed-point Newton step."""
    rows = np.asarray(coefficients["integer_rows"], dtype=np.int64)
    corners = ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1))
    for u, v in corners:
        d = int(rows[2, 0] * u + rows[2, 1] * v + rows[2, 2])
        nx = int(rows[0, 0] * u + rows[0, 1] * v + rows[0, 2])
        ny = int(rows[1, 0] * u + rows[1, 1] * v + rows[1, 2])
        if not ((1 << 29) <= d < (2 << 30)):
            return {"profile_supported": False, "reason": "denominator outside [0.5, 2.0) at a frame corner"}
        if max(abs(nx), abs(ny)) > (1 << 30):
            return {"profile_supported": False, "reason": "numerator magnitude exceeds 2^30 Q16.16 at a frame corner"}

    u, v = np.meshgrid(np.arange(width, dtype=np.int64), np.arange(height, dtype=np.int64))
    nx = rows[0, 0] * u + rows[0, 1] * v + rows[0, 2]
    ny = rows[1, 0] * u + rows[1, 1] * v + rows[1, 2]
    d = rows[2, 0] * u + rows[2, 1] * v + rows[2, 2]
    # Q2.30 values from 0.5 to 2.0 use 768 of the 1024 ROM addresses.
    address = (d - (1 << 29)) >> 21
    midpoints = 0.5 + (np.arange(1024, dtype=np.float64) + 0.5) / 512.0
    seed_rom = np.rint((1 << 30) / midpoints).astype(np.int64)
    r0 = seed_rom[address]
    d_times_r0_q30 = (d * r0 + (1 << 29)) >> 30
    r1 = (r0 * ((2 << 30) - d_times_r0_q30) + (1 << 29)) >> 30
    # Preserve the identity map and exact integer border coordinates.
    r1 = np.where(d == (1 << 30), 1 << 30, r1)
    x_q16 = _rounded_signed_shift(nx * r1, 30)
    y_q16 = _rounded_signed_shift(ny * r1, 30)
    candidate_x = x_q16.astype(np.float64) / SCALE_NUMERATOR
    candidate_y = y_q16.astype(np.float64) / SCALE_NUMERATOR

    reference_x, reference_y, safe = evaluate_map(homography, width, height)
    reference_valid = (
        safe & (reference_x >= 0) & (reference_x < width - 1)
        & (reference_y >= 0) & (reference_y < height - 1)
    )
    candidate_valid = (
        (x_q16 >= SIGNED32_MIN) & (x_q16 <= SIGNED32_MAX)
        & (y_q16 >= SIGNED32_MIN) & (y_q16 <= SIGNED32_MAX)
        & (candidate_x >= 0) & (candidate_x < width - 1)
        & (candidate_y >= 0) & (candidate_y < height - 1)
    )
    common = reference_valid & candidate_valid
    error = np.maximum(
        np.abs(candidate_x[common] - reference_x[common]),
        np.abs(candidate_y[common] - reference_y[common]),
    )
    return {
        "profile_supported": True,
        "denominator_corner_range_q2_30": [int(np.min(d)), int(np.max(d))],
        "reciprocal_rom_words": 1024,
        "rom_address_step": "1/512 from denominator 0.5",
        "newton_iterations": 1,
        "integer_product_rounding": "nearest, ties away from zero for signed products",
        "floating_valid_pixels": int(np.count_nonzero(reference_valid)),
        "candidate_valid_pixels": int(np.count_nonzero(candidate_valid)),
        "valid_mask_difference_pixels": int(np.count_nonzero(reference_valid != candidate_valid)),
        "common_valid_pixels": int(np.count_nonzero(common)),
        "max_axis_coordinate_error_px": float(np.max(error)) if error.size else None,
        "p99_axis_coordinate_error_px": float(np.percentile(error, 99)) if error.size else None,
        "analysis_scope": "integer per-pixel arithmetic only; pipeline timing, ROM implementation and DDR throughput not modeled",
    }


def synthetic_records(args: argparse.Namespace) -> tuple[np.ndarray, np.ndarray, np.ndarray, tuple[int, int], Iterator[dict]]:
    width, height = args.width, args.height
    camera_matrix = np.asarray([
        [args.fx, 0.0, (width - 1) / 2],
        [0.0, args.fy, (height - 1) / 2],
        [0.0, 0.0, 1.0],
    ], dtype=np.float64)
    reference_rotation = np.eye(3, dtype=np.float64)
    reference_translation = np.asarray([0.0, 0.0, args.plane_distance_mm], dtype=np.float64)

    def records() -> Iterator[dict]:
        for axis in ("x", "y"):
            for angle in (-20.0, -10.0, 0.0, 10.0, 20.0):
                current_rotation = rotation_matrix(axis, angle)
                current_translation = reference_translation.copy()
                delta_rotation, delta_translation = relative_pose(
                    reference_rotation, reference_translation,
                    current_rotation, current_translation,
                )
                yield {
                    "valid": True,
                    "pose_source": f"synthetic_{axis}_{angle:+g}deg",
                    "relative_rotation_matrix": delta_rotation.tolist(),
                    "relative_translation_mm": delta_translation.tolist(),
                    "board_to_camera_rotation": current_rotation.tolist(),
                    "board_to_camera_translation_mm": current_translation.tolist(),
                }

    return camera_matrix, reference_rotation, reference_translation, (width, height), records()


def tracked_records(args: argparse.Namespace) -> tuple[np.ndarray, np.ndarray, np.ndarray, tuple[int, int], Iterator[dict]]:
    calibration = load_calibration(args.calibration)
    reference_rotation, reference_translation = load_reference(args.reference, calibration)
    reference_rotation = check_rotation(reference_rotation, "reference_rotation")
    reference_translation = check_translation(reference_translation, "reference_translation")

    def records() -> Iterator[dict]:
        with args.pose_log.open("r", encoding="utf-8") as source:
            for line_number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"Invalid pose JSON at line {line_number}: {exc}") from exc
                if not isinstance(record, dict):
                    raise ValueError(f"Pose JSON at line {line_number} must be an object")
                yield record

    return (calibration["_camera_matrix"], reference_rotation, reference_translation,
            calibration["_image_size"], records())


def export_record(
    record: dict, camera_matrix: np.ndarray, reference_rotation: np.ndarray,
    reference_translation: np.ndarray, image_size: tuple[int, int],
    analyze: bool, analyze_reciprocal: bool,
) -> dict:
    result = {"schema": SCHEMA, "valid": False}
    for name in ("timestamp_unix_ns", "frame_index", "pose_source"):
        if name in record:
            result[name] = record[name]
    if record.get("valid") is not True:
        result["reason"] = record.get("reason", "source_pose_invalid")
        return result
    try:
        delta_rotation = check_rotation(record["relative_rotation_matrix"], "relative_rotation_matrix")
        delta_translation = check_translation(record["relative_translation_mm"], "relative_translation_mm")
        homography = homography_from_relative_pose(
            camera_matrix, reference_rotation, reference_translation,
            delta_rotation, delta_translation,
        )
        coefficients = quantize_coefficients(homography)
        result["output_to_source_homography"] = homography.tolist()
        result["candidate_fixed_point"] = coefficients
        if "board_to_camera_rotation" in record and "board_to_camera_translation_mm" in record:
            direct = homography_from_board_poses(
                camera_matrix, reference_rotation, reference_translation,
                check_rotation(record["board_to_camera_rotation"], "board_to_camera_rotation"),
                check_translation(record["board_to_camera_translation_mm"], "board_to_camera_translation_mm"),
            )
            if not np.allclose(homography, direct, rtol=1e-7, atol=1e-7):
                raise ValueError("relative pose disagrees with board-to-camera pose")
            result["relative_vs_direct_max_coefficient_difference"] = float(np.max(np.abs(homography - direct)))
        if analyze:
            result["map_comparison"] = analyze_maps(homography, coefficients, *image_size)
        if analyze_reciprocal:
            result["reciprocal_model_comparison"] = analyze_reciprocal_model(
                homography, coefficients, *image_size
            )
        result["valid"] = True
    except (KeyError, TypeError, ValueError, np.linalg.LinAlgError) as exc:
        result.pop("output_to_source_homography", None)
        result.pop("candidate_fixed_point", None)
        result.pop("map_comparison", None)
        result.pop("reciprocal_model_comparison", None)
        result["reason"] = f"pose_to_homography_failed: {exc}"
    return result


def main() -> int:
    args = parse_args()
    try:
        if args.pose_log:
            camera_matrix, reference_rotation, reference_translation, image_size, records = tracked_records(args)
            source_kind = "track_pose_jsonl"
        else:
            camera_matrix, reference_rotation, reference_translation, image_size, records = synthetic_records(args)
            source_kind = "synthetic_known_poses"
        args.out.parent.mkdir(parents=True, exist_ok=True)
        valid_count = invalid_count = 0
        maximum_error = 0.0
        mask_differences = 0
        reciprocal_maximum_error = 0.0
        reciprocal_mask_differences = 0
        unsupported_reciprocal_records = 0
        with args.out.open("w", encoding="utf-8", newline="\n") as destination:
            for record in records:
                exported = export_record(
                    record, camera_matrix, reference_rotation, reference_translation,
                    image_size, args.analyze_maps, args.analyze_reciprocal,
                )
                destination.write(json.dumps(exported, ensure_ascii=False) + "\n")
                valid_count += int(exported["valid"])
                invalid_count += int(not exported["valid"])
                if exported["valid"] and args.analyze_maps:
                    comparison = exported["map_comparison"]
                    maximum_error = max(maximum_error, comparison["max_axis_coordinate_error_px"] or 0.0)
                    mask_differences += comparison["valid_mask_difference_pixels"]
                if exported["valid"] and args.analyze_reciprocal:
                    reciprocal = exported["reciprocal_model_comparison"]
                    if reciprocal["profile_supported"]:
                        reciprocal_maximum_error = max(
                            reciprocal_maximum_error,
                            reciprocal["max_axis_coordinate_error_px"] or 0.0,
                        )
                        reciprocal_mask_differences += reciprocal["valid_mask_difference_pixels"]
                    else:
                        unsupported_reciprocal_records += 1
    except (OSError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps({
        "output": str(args.out.resolve()),
        "source": source_kind,
        "valid_records": valid_count,
        "invalid_records": invalid_count,
        "analyzed_maps": args.analyze_maps,
        "maximum_axis_coordinate_error_px": maximum_error if args.analyze_maps else None,
        "total_valid_mask_difference_pixels": mask_differences if args.analyze_maps else None,
        "reciprocal_model_maximum_axis_error_px": reciprocal_maximum_error if args.analyze_reciprocal else None,
        "reciprocal_model_total_mask_difference_pixels": reciprocal_mask_differences if args.analyze_reciprocal else None,
        "unsupported_reciprocal_records": unsupported_reciprocal_records if args.analyze_reciprocal else None,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
