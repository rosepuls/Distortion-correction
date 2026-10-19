"""Quantize real calibration for the legacy four-coefficient FPGA mapper."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def signed_q32(value: float, fractional_bits: int, name: str) -> int:
    if not math.isfinite(value):
        raise SystemExit(f"{name} is not finite")
    scaled = value * (1 << fractional_bits)
    integer = math.floor(scaled + 0.5) if scaled >= 0 else math.ceil(scaled - 0.5)
    if not -(1 << 31) <= integer < (1 << 31):
        raise SystemExit(f"{name} does not fit signed 32-bit Q format")
    return integer


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--max-k3-map-error-px", type=float, default=0.5,
                        help="reject the four-coefficient export above this pixel shift")
    args = parser.parse_args()
    if not math.isfinite(args.max_k3_map_error_px) or args.max_k3_map_error_px < 0:
        parser.error("--max-k3-map-error-px must be finite and non-negative")
    calibration_path = args.calibration.resolve()
    if not calibration_path.is_file():
        raise SystemExit(f"Calibration JSON does not exist: {calibration_path}")
    data = json.loads(calibration_path.read_text(encoding="utf-8"))
    if data.get("schema") != "pango-camera-calibration-v1":
        raise SystemExit("Unsupported calibration JSON schema")
    if data.get("image_size") != [1280, 720]:
        raise SystemExit("Only the final 1280x720 camera mode can be exported")
    camera_matrix = data["camera_matrix"]
    coefficients = data["distortion_coefficients"]
    if len(camera_matrix) != 3 or any(len(row) != 3 for row in camera_matrix):
        raise SystemExit("Expected a 3x3 camera matrix")
    if len(coefficients) < 5:
        raise SystemExit("Expected k1, k2, p1, p2 and k3")
    k3_shift = float(data["k3_zeroed_map_difference"]["max_px"])
    if not math.isfinite(k3_shift) or k3_shift > args.max_k3_map_error_px:
        raise SystemExit(
            f"k3 changes the source map by {k3_shift:.4f} px at most; "
            "the legacy mapper has no k3 input. Extend the FPGA core first."
        )

    fx, fy = float(camera_matrix[0][0]), float(camera_matrix[1][1])
    cx, cy = float(camera_matrix[0][2]), float(camera_matrix[1][2])
    if not math.isfinite(fx) or not math.isfinite(fy) or fx <= 0 or fy <= 0:
        raise SystemExit("Camera focal lengths must be finite and positive")
    source_values = {
        "cfg_fx_q19": (fx, 19),
        "cfg_fy_q19": (fy, 19),
        "cfg_cx_q19": (cx, 19),
        "cfg_cy_q19": (cy, 19),
        "cfg_inv_fx_q30": (1.0 / fx, 30),
        "cfg_inv_fy_q30": (1.0 / fy, 30),
        "cfg_k1_q28": (float(coefficients[0]), 28),
        "cfg_k2_q28": (float(coefficients[1]), 28),
        "cfg_p1_q28": (float(coefficients[2]), 28),
        "cfg_p2_q28": (float(coefficients[3]), 28),
    }
    quantized = {
        name: {
            "signed": signed_q32(value, bits, name),
            "fractional_bits": bits,
        }
        for name, (value, bits) in source_values.items()
    }
    for field in quantized.values():
        field["hex_twos_complement"] = f"{field['signed'] & 0xffffffff:08X}"
    output = {
        "schema": "pango-fixed-calibration-v1",
        "calibration_file": str(calibration_path),
        "calibration_sha256": sha256_file(calibration_path),
        "image_size": [1280, 720],
        "input_and_output_camera_matrix": camera_matrix,
        "k3_zeroed_max_map_error_px": k3_shift,
        "four_coefficient_approximation": True,
        "registers": quantized,
    }
    out_path = args.out.resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {out_path}")


if __name__ == "__main__":
    main()
