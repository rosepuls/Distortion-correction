"""Analyze checkerboard rotation images and print Stage 8 protocol-v2 UART frames."""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys

import cv2

from analyze_parallel_rotation import (
    detect_grid,
    load_calibration,
    quantize,
    rotation_homography,
)


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DISTORTION_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_IMAGES = PROJECT_ROOT / "picture" / "Calibration" / "parallel angle"
DEFAULT_CALIBRATION = DISTORTION_ROOT / "host" / "calibration" / "output" / "calibration.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, default=DEFAULT_IMAGES,
                        help="folder with PNG files named by nominal rotation angle")
    parser.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION,
                        help="current camera calibration JSON")
    parser.add_argument("--cols", type=int, default=9, help="checkerboard inner corners")
    parser.add_argument("--rows", type=int, default=6, help="checkerboard inner corners")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--sequence-start", type=int, default=1,
                        help="first 16-bit request sequence number")
    parser.add_argument("--only-angle", type=float,
                        help="print only the image whose filename stem has this angle; all images are still analyzed for angle unwrapping")
    return parser.parse_args()


def crc16_ccitt_false(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def validate_stage8_profile(integer_rows: list[list[int]], width: int, height: int) -> None:
    """Reject matrices outside the Stage 8 homography numeric profile."""
    if integer_rows[2][2] != 0x40000000:
        raise ValueError("Stage 8 requires h22 == 0x40000000")
    for x in (0, width - 1):
        for y in (0, height - 1):
            nx = integer_rows[0][0] * x + integer_rows[0][1] * y + integer_rows[0][2]
            ny = integer_rows[1][0] * x + integer_rows[1][1] * y + integer_rows[1][2]
            denominator = integer_rows[2][0] * x + integer_rows[2][1] * y + integer_rows[2][2]
            if not (1 << 29) <= denominator < (1 << 31):
                raise ValueError(f"Stage 8 denominator out of range at ({x}, {y}): {denominator}")
            if abs(nx) > (1 << 30) or abs(ny) > (1 << 30):
                raise ValueError(f"Stage 8 numerator out of range at ({x}, {y}): ({nx}, {ny})")


def make_request(sequence: int, integer_rows: list[list[int]]) -> bytes:
    if not 0 <= sequence <= 0xFFFF:
        raise ValueError(f"Sequence must be in 0..65535, got {sequence}")
    frame = bytearray((0xA5, 0x5A, 0x02, 0x01,
                       sequence & 0xFF, (sequence >> 8) & 0xFF, 0x01))
    for value in (value for row in integer_rows for value in row):
        frame.extend((value & 0xFFFFFFFF).to_bytes(4, byteorder="little", signed=False))
    frame.extend(bytes(20))  # Reserved extension bytes; protocol v2 requires zero.
    crc = crc16_ccitt_false(frame[2:63])
    frame.extend((crc >> 8, crc & 0xFF))
    if len(frame) != 65:
        raise ValueError(f"Internal packet error: expected 65 bytes, got {len(frame)}")
    return bytes(frame)


def main() -> int:
    args = parse_args()
    if not 0 <= args.sequence_start <= 0xFFFF:
        raise SystemExit("--sequence-start must be in 0..65535")

    try:
        K, D = load_calibration(args.calibration)
        cx, cy = float(K[0, 2]), float(K[1, 2])

        files = []
        for path in args.images.glob("*.png"):
            try:
                nominal = float(path.stem)
            except ValueError:
                continue
            grid, raw_angle, spread = detect_grid(
                path, args.cols, args.rows, K, D, args.width, args.height
            )
            files.append((nominal, path, grid, raw_angle, spread))
        files.sort(key=lambda item: item[0])
        if not files:
            raise ValueError(f"No angle-named PNG files found in {args.images}")

        # Checkerboard orientation is detected modulo 180 degrees. Unwrap the
        # sweep in filename order before measuring each frame against the first.
        unwrapped = []
        for _, _, _, angle, _ in files:
            value = angle
            if unwrapped:
                while value - unwrapped[-1] > 90.0:
                    value -= 180.0
                while value - unwrapped[-1] < -90.0:
                    value += 180.0
            unwrapped.append(value)

        records = []
        baseline = unwrapped[0]
        for index, ((nominal, path, _grid, _raw_angle, spread), absolute_angle) in enumerate(
            zip(files, unwrapped)
        ):
            relative_angle = absolute_angle - baseline
            homography = rotation_homography(relative_angle, cx, cy)
            fixed = quantize(homography)
            rows = fixed["integer_rows"]
            validate_stage8_profile(rows, args.width, args.height)
            sequence = (args.sequence_start + index) & 0xFFFF
            packet = make_request(sequence, rows)
            records.append({
                "nominal_angle": nominal,
                "file": path.name,
                "relative_angle": relative_angle,
                "spread": spread,
                "sequence": sequence,
                "rows": rows,
                "packet": packet,
            })

        if args.only_angle is not None:
            records = [record for record in records
                       if math.isclose(record["nominal_angle"], args.only_angle,
                                       rel_tol=0.0, abs_tol=1e-9)]
            if not records:
                raise ValueError(f"No image named {args.only_angle:g}.png in {args.images}")

    except (OSError, ValueError, cv2.error) as exc:
        raise SystemExit(str(exc)) from exc

    print(f"Images analyzed: {len(files)} | reference: {files[0][1].name} | packets printed: {len(records)}")
    print("Packet format: Stage 8 protocol v2 request, 65 bytes, 115200 8-N-1; output is not sent automatically.\n")
    for record in records:
        packet_hex = " ".join(f"{value:02X}" for value in record["packet"])
        print(
            f"{record['file']}: nominal={record['nominal_angle']:+g} deg, "
            f"measured_relative={record['relative_angle']:+.3f} deg, "
            f"row_spread={record['spread']:.3f} deg, sequence={record['sequence']}"
        )
        print("  H_words=" + " ".join(f"{value & 0xFFFFFFFF:08X}"
                                      for row in record["rows"] for value in row))
        print(f"  UART_HEX ({len(record['packet'])} bytes): {packet_hex}\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
