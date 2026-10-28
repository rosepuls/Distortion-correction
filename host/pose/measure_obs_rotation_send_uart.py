"""Measure one OBS checkerboard rotation against picture/Calibration/00.png.

The script reads five valid frames from the selected camera, estimates the
checkerboard's undistorted image-plane angle relative to the fixed 00.png
reference, then sends exactly one Stage 8 homography packet unless --dry-run
is specified. The symmetric checkerboard only defines an angle modulo 180°;
the reported branch is the one in [-90°, 90°).
"""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import serial

from analyze_parallel_rotation import (
    load_calibration as load_rotation_calibration,
    quantize,
    rotation_homography,
)
from encode_rotation_images_uart import (
    crc16_ccitt_false,
    make_request,
    validate_stage8_profile,
)
from pose_geometry import load_calibration, read_image, validate_image_size


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DISTORTION_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CALIBRATION = DISTORTION_ROOT / "host" / "calibration" / "output" / "calibration.json"
FIXED_REFERENCE = PROJECT_ROOT / "picture" / "Calibration" / "00.png"
UART_BAUD = 115200
PACKET_LENGTH = 65


def parse_source(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=parse_source, default=2,
                        help="OBS Virtual Camera device index (default 2) or video path")
    parser.add_argument("--port", default="COM7", help="USB-UART port (default COM7)")
    parser.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION,
                        help="camera calibration JSON")
    parser.add_argument("--sequence", type=int,
                        help="16-bit parameter sequence/version; defaults to current Unix time")
    parser.add_argument("--dry-run", action="store_true",
                        help="measure and print the packet without opening the serial port")
    parser.add_argument("--save-frame", type=Path,
                        help="optionally save the selected OBS frame")
    return parser.parse_args()


def estimate_grid_angle(image: np.ndarray, calibration: dict) -> tuple[float, float]:
    """Return undistorted grid angle in [-90, 90) and middle-row spread."""
    cols, rows = calibration["_board_size"]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    flags = cv2.CALIB_CB_EXHAUSTIVE | cv2.CALIB_CB_ACCURACY
    found, corners = cv2.findChessboardCornersSB(gray, (cols, rows), flags=flags)
    if not found:
        raise ValueError("full checkerboard was not detected")

    ideal = cv2.undistortPoints(
        corners.reshape(-1, 1, 2),
        calibration["_camera_matrix"],
        calibration["_distortion"],
        P=calibration["_camera_matrix"],
    ).reshape(rows, cols, 2)
    row_vectors = np.asarray([
        ideal[row, cols - 2] - ideal[row, 1]
        for row in range(1, rows - 1)
    ])
    row_angles = np.arctan2(row_vectors[:, 1], row_vectors[:, 0])
    doubled_mean = np.mean(np.exp(2j * row_angles))
    angle = math.degrees(0.5 * math.atan2(doubled_mean.imag, doubled_mean.real))
    angle = ((angle + 90.0) % 180.0) - 90.0
    spread = math.degrees(float(np.ptp(row_angles)))
    return angle, spread


def wrap_half_turn(angle_deg: float) -> float:
    """Choose the checkerboard-equivalent relative angle nearest zero."""
    return ((angle_deg + 90.0) % 180.0) - 90.0


def mean_half_turn(angles_deg: list[float]) -> float:
    """Average angles while respecting the checkerboard's 180° symmetry."""
    doubled = np.exp(2j * np.radians(angles_deg)).mean()
    return wrap_half_turn(math.degrees(0.5 * math.atan2(doubled.imag, doubled.real)))


def read_obs_samples(source: int | str, calibration: dict, count: int = 5) -> tuple[np.ndarray, list[float], list[float]]:
    capture = cv2.VideoCapture(source)
    if not capture.isOpened():
        raise RuntimeError(f"could not open OBS/video source: {source}")
    if isinstance(source, int):
        width, height = calibration["_image_size"]
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    selected_frame: np.ndarray | None = None
    angles: list[float] = []
    spreads: list[float] = []
    try:
        for _ in range(240):
            ok, frame = capture.read()
            if not ok:
                continue
            validate_image_size(frame, calibration, "OBS frame")
            try:
                angle, spread = estimate_grid_angle(frame, calibration)
            except ValueError:
                continue
            selected_frame = frame.copy()
            angles.append(angle)
            spreads.append(spread)
            if len(angles) == count:
                break
    finally:
        capture.release()

    if selected_frame is None or len(angles) != count:
        raise RuntimeError(
            f"only {len(angles)} valid checkerboard frames found; need {count}; no UART packet sent"
        )
    return selected_frame, angles, spreads


def read_ack(port: serial.Serial, expected_sequence: int, expected_request: bytes) -> bytes:
    deadline = time.monotonic() + 3.0
    response = bytearray()
    while len(response) < PACKET_LENGTH and time.monotonic() < deadline:
        response.extend(port.read(PACKET_LENGTH - len(response)))
    if len(response) != PACKET_LENGTH:
        raise TimeoutError(
            f"sent one packet, but received only {len(response)}/{PACKET_LENGTH} ACK bytes; not retrying"
        )
    if response[:4] != bytes((0xA5, 0x5A, 0x02, 0x81)):
        raise ValueError(f"unexpected UART response header: {response[:4].hex(' ')}")
    sequence = response[4] | (response[5] << 8)
    if sequence != expected_sequence:
        raise ValueError(f"ACK sequence {sequence} does not match request {expected_sequence}")
    expected_crc = crc16_ccitt_false(response[2:63])
    received_crc = (response[63] << 8) | response[64]
    if received_crc != expected_crc:
        raise ValueError("UART response CRC mismatch")
    if response[7:43] != expected_request[7:43]:
        raise ValueError("FPGA response coefficients do not match the sent matrix")
    if response[43:63] != expected_request[43:63]:
        raise ValueError("FPGA response extension does not match the sent extension")
    if response[6] != 0:
        raise ValueError(f"FPGA rejected the packet with status 0x{response[6]:02X}")
    return bytes(response)


def main() -> int:
    args = parse_args()
    if not FIXED_REFERENCE.is_file():
        raise SystemExit(f"Fixed reference image not found: {FIXED_REFERENCE}")
    if args.sequence is not None and not 0 <= args.sequence <= 0xFFFF:
        raise SystemExit("--sequence must be in 0..65535")

    try:
        calibration = load_calibration(args.calibration)
        reference_image = read_image(FIXED_REFERENCE)
        validate_image_size(reference_image, calibration, "Fixed reference image")
        reference_angle, reference_spread = estimate_grid_angle(reference_image, calibration)
        frame, samples, spreads = read_obs_samples(args.source, calibration)
        current_angle = mean_half_turn(samples)
        relative_angle = wrap_half_turn(current_angle - reference_angle)

        K, _ = load_rotation_calibration(args.calibration)
        homography = rotation_homography(
            relative_angle, float(K[0, 2]), float(K[1, 2])
        )
        rows = quantize(homography)["integer_rows"]
        validate_stage8_profile(rows, *calibration["_image_size"])
        sequence = args.sequence if args.sequence is not None else (int(time.time()) & 0xFFFF)
        packet = make_request(sequence, rows)
    except (OSError, ValueError, RuntimeError, cv2.error) as exc:
        raise SystemExit(str(exc)) from exc

    if args.save_frame:
        args.save_frame.parent.mkdir(parents=True, exist_ok=True)
        if not cv2.imwrite(str(args.save_frame), frame):
            raise SystemExit(f"could not save OBS frame: {args.save_frame}")

    print(f"reference: {FIXED_REFERENCE}")
    print(f"reference grid angle: {reference_angle:+.3f} deg; row spread {reference_spread:.3f} deg")
    print(f"OBS samples: {len(samples)}; sample angles: " + ", ".join(f"{v:+.3f}" for v in samples))
    print(f"OBS middle-row spread median: {float(np.median(spreads)):.3f} deg")
    print(f"measured image-plane angle relative to 00.png: {relative_angle:+.3f} deg")
    print("mapping: reference output ideal pixels -> current OBS source ideal pixels")
    print(f"sequence/version: {sequence}; UART packet: {len(packet)} bytes")
    print("UART_HEX: " + packet.hex(" ").upper())

    if args.dry_run:
        print("dry run: serial port was not opened; no packet sent")
        return 0

    try:
        with serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0) as port:
            port.reset_input_buffer()
            port.reset_output_buffer()
            written = port.write(packet)  # exactly one write; no retry path
            port.flush()
            if written != PACKET_LENGTH:
                raise IOError(f"serial write accepted {written}/{PACKET_LENGTH} bytes")
            response = read_ack(port, sequence, packet)
    except (serial.SerialException, OSError, TimeoutError, ValueError) as exc:
        raise SystemExit(f"UART operation failed: {exc}") from exc

    print(f"FPGA ACK: accepted, status=0x{response[6]:02X}, response CRC={response[63]:02X} {response[64]:02X}")
    print("sent exactly one request; serial port closed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
