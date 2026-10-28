"""Continuously send live OBS image-plane rotation matrices to Stage 8."""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

import cv2
import serial

from analyze_parallel_rotation import load_calibration as load_rotation_calibration
from analyze_parallel_rotation import quantize, rotation_homography
from encode_rotation_images_uart import make_request, validate_stage8_profile
from measure_obs_rotation_send_uart import (
    DEFAULT_CALIBRATION,
    FIXED_REFERENCE,
    UART_BAUD,
    estimate_grid_angle,
    read_ack,
    wrap_half_turn,
)
from pose_geometry import load_calibration, read_image, validate_image_size


def parse_source(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=parse_source, default=2,
                        help="OBS Virtual Camera device index (default 2) or video path")
    parser.add_argument("--port", default="COM7", help="USB-UART port (default COM7)")
    parser.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION,
                        help="camera calibration JSON; defaults to the fixed one-shot script's calibration")
    parser.add_argument("--sequence", type=int,
                        help="initial 16-bit parameter sequence; defaults to current Unix time")
    return parser.parse_args()


def unwrap_near_reference(angle_mod_180: float, previous_angle: float | None) -> float:
    """Choose the 180°-equivalent angle closest to the previous live sample."""
    if previous_angle is None:
        return wrap_half_turn(angle_mod_180)
    return angle_mod_180 + 180.0 * round((previous_angle - angle_mod_180) / 180.0)


def main() -> int:
    args = parse_args()
    if not FIXED_REFERENCE.is_file():
        raise SystemExit(f"Fixed reference image not found: {FIXED_REFERENCE}")
    if args.sequence is not None and not 0 <= args.sequence <= 0xFFFF:
        raise SystemExit("--sequence must be in 0..65535")

    calibration_path = args.calibration
    try:
        calibration = load_calibration(calibration_path)
        K, _ = load_rotation_calibration(calibration_path)
        reference = read_image(FIXED_REFERENCE)
        validate_image_size(reference, calibration, "Fixed reference image")
        reference_angle, _ = estimate_grid_angle(reference, calibration)
    except (OSError, ValueError, cv2.error) as exc:
        raise SystemExit(str(exc)) from exc

    capture = cv2.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"could not open OBS/video source: {args.source}")
    if isinstance(args.source, int):
        width, height = calibration["_image_size"]
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    sequence = args.sequence if args.sequence is not None else (int(time.time()) & 0xFFFF)
    previous_angle: float | None = None
    target_was_visible = False
    sent_count = 0
    last_angle = math.nan
    report_at = time.monotonic() + 1.0
    report_count = 0
    port: serial.Serial | None = None

    print(f"fixed reference: {FIXED_REFERENCE}")
    print(f"reference grid angle: {reference_angle:+.3f} deg")
    print(f"stream: source={args.source}, UART={args.port} at {UART_BAUD} baud")
    print("one valid OBS frame -> one request -> wait for ACK; Ctrl+C stops updates")

    try:
        port = serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0)
        port.reset_input_buffer()
        port.reset_output_buffer()

        while True:
            ok, frame = capture.read()
            if not ok:
                continue
            validate_image_size(frame, calibration, "OBS frame")

            try:
                current_angle, _spread = estimate_grid_angle(frame, calibration)
            except ValueError:
                if target_was_visible:
                    print("checkerboard lost; holding FPGA's last accepted matrix")
                    target_was_visible = False
                continue

            target_was_visible = True
            relative_mod_180 = wrap_half_turn(current_angle - reference_angle)
            relative_angle = unwrap_near_reference(relative_mod_180, previous_angle)
            homography = rotation_homography(
                relative_angle, float(K[0, 2]), float(K[1, 2])
            )
            rows = quantize(homography)["integer_rows"]
            validate_stage8_profile(rows, *calibration["_image_size"])
            packet = make_request(sequence, rows)

            written = port.write(packet)  # exactly one request for this valid frame
            port.flush()
            if written != len(packet):
                raise IOError(f"serial write accepted {written}/{len(packet)} bytes")
            read_ack(port, sequence, packet)  # stop on timeout/NACK; never retry a request

            previous_angle = relative_angle
            last_angle = relative_angle
            sequence = (sequence + 1) & 0xFFFF
            sent_count += 1
            report_count += 1

            now = time.monotonic()
            if now >= report_at:
                print(f"accepted updates/s={report_count}; angle={last_angle:+.3f} deg; total={sent_count}")
                report_count = 0
                report_at = now + 1.0

    except KeyboardInterrupt:
        print(f"stopped by user; accepted updates={sent_count}; last angle={last_angle:+.3f} deg")
    except (serial.SerialException, OSError, TimeoutError, ValueError, cv2.error) as exc:
        raise SystemExit(f"continuous correction stopped: {exc}; no request was retried") from exc
    finally:
        capture.release()
        if port is not None and port.is_open:
            port.close()
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    sys.exit(main())
