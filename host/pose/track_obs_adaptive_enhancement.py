"""Select Stage 11 enhancement profiles from raw OBS frames and send UART updates.

By default, angle tracking and lighting share the same 65-byte request. Use
--identity for a lighting-only trial that explicitly selects identity geometry.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import cv2
import serial

from analyze_parallel_rotation import load_calibration as load_rotation_calibration
from analyze_parallel_rotation import quantize, rotation_homography
from encode_rotation_images_uart import crc16_ccitt_false, make_request, validate_stage8_profile
from lighting_profile import PROFILE_NAMES, LightingSelector, analyze_bgr, classify_lighting
from measure_obs_rotation_send_uart import (
    DEFAULT_CALIBRATION,
    FIXED_REFERENCE,
    UART_BAUD,
    estimate_grid_angle,
    read_ack,
    wrap_half_turn,
)
from pose_geometry import load_calibration, read_image, validate_image_size
from track_obs_rotation_continuous import (
    PartialBoardAngleTracker,
    parse_source,
    unwrap_near_reference,
)


IDENTITY_ROWS = [
    [0x00010000, 0, 0],
    [0, 0x00010000, 0],
    [0, 0, 0x40000000],
]
FRAME_WIDTH = 1280
FRAME_HEIGHT = 720


def make_stage11_request(sequence: int, rows: list[list[int]], profile_id: int) -> bytes:
    """Keep Stage 8's matrix format and assign byte 43 to the Stage 11 curve."""
    if profile_id not in PROFILE_NAMES:
        raise ValueError(f"unsupported enhancement profile: {profile_id}")
    validate_stage8_profile(rows, FRAME_WIDTH, FRAME_HEIGHT)
    packet = bytearray(make_request(sequence, rows))
    packet[43] = profile_id
    crc = crc16_ccitt_false(packet[2:63])
    packet[63] = crc >> 8
    packet[64] = crc & 0xFF
    return bytes(packet)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=parse_source, default=2,
                        help="raw OBS Virtual Camera index (default 2) or video file")
    parser.add_argument("--port", default="COM7", help="USB-UART port (default COM7)")
    parser.add_argument("--identity", action="store_true",
                        help="lighting only: send identity geometry instead of tracking angle")
    parser.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION,
                        help="camera calibration for combined angle+lighting mode")
    parser.add_argument("--sequence", type=int,
                        help="initial 16-bit sequence; defaults to current Unix time")
    parser.add_argument("--sample-stride", type=int, default=8,
                        help="sample every Nth row and column (default 8)")
    parser.add_argument("--stable-frames", type=int, default=3,
                        help="consecutive classifications required to switch (default 3)")
    parser.add_argument("--report-every", type=int, default=15,
                        help="print brightness statistics every N frames (default 15)")
    args = parser.parse_args(argv)
    if args.sequence is not None and not 0 <= args.sequence <= 0xFFFF:
        parser.error("--sequence must be in 0..65535")
    if min(args.sample_stride, args.stable_frames, args.report_every) < 1:
        parser.error("--sample-stride, --stable-frames and --report-every must be positive")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    calibration = None
    reference_angle = None
    tracker = None
    cx = cy = 0.0
    if not args.identity:
        if not FIXED_REFERENCE.is_file():
            raise SystemExit(f"fixed reference image not found: {FIXED_REFERENCE}")
        calibration = load_calibration(args.calibration)
        K, _ = load_rotation_calibration(args.calibration)
        reference = read_image(FIXED_REFERENCE)
        validate_image_size(reference, calibration, "fixed reference image")
        reference_angle, _ = estimate_grid_angle(reference, calibration)
        cx, cy = float(K[0, 2]), float(K[1, 2])
        tracker = PartialBoardAngleTracker(calibration)

    capture = cv2.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"could not open raw OBS/video source: {args.source}")
    if isinstance(args.source, int):
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    selector = LightingSelector(stable_frames=args.stable_frames)
    sequence = args.sequence if args.sequence is not None else (int(time.time()) & 0xFFFF)
    previous_angle: float | None = None
    last_accepted_rows: list[list[int]] | None = None
    last_sent_profile: int | None = None
    streak_candidate: int | None = None
    streak_count = 0
    frame_count = 0
    accepted_count = 0
    read_failures = 0
    port: serial.Serial | None = None

    matrix_mode = "identity (lighting-only)" if args.identity else "live angle + lighting"
    print(f"raw source={args.source}; UART={args.port} at {UART_BAUD} baud; mode={matrix_mode}")
    if args.identity:
        print("identity mode sends an identity matrix and replaces any active angle correction")
    else:
        print("waiting for a full checkerboard lock; lost tracking holds the last ACKed matrix")
    print("Ctrl+C stops the sender; the FPGA retains its last accepted profile")

    try:
        port = serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0)
        port.reset_input_buffer()
        port.reset_output_buffer()

        while True:
            ok, frame = capture.read()
            if not ok:
                if not isinstance(args.source, int):
                    break
                read_failures += 1
                if read_failures >= 30:
                    raise OSError("OBS source failed to deliver 30 consecutive frames")
                continue
            read_failures = 0
            frame_count += 1
            if frame.shape[:2] != (FRAME_HEIGHT, FRAME_WIDTH):
                raise ValueError(
                    f"OBS source must be {FRAME_WIDTH}x{FRAME_HEIGHT}; "
                    f"got {frame.shape[1]}x{frame.shape[0]}"
                )

            metrics = analyze_bgr(frame, sample_stride=args.sample_stride)
            candidate = classify_lighting(metrics)
            if candidate == streak_candidate:
                streak_count += 1
            else:
                streak_candidate = candidate
                streak_count = 1
            active_profile = selector.update(candidate)

            angle_estimate = None
            rows = IDENTITY_ROWS if args.identity else last_accepted_rows
            if tracker is not None:
                angle_estimate = tracker.update(frame)
                if angle_estimate is not None:
                    current_angle, tracked_count, inlier_count = angle_estimate
                    relative_mod_180 = wrap_half_turn(current_angle - reference_angle)
                    relative_angle = unwrap_near_reference(relative_mod_180, previous_angle)
                    homography = rotation_homography(relative_angle, cx, cy)
                    rows = quantize(homography)["integer_rows"]

            # The first packet waits for a stable classification, including bypass.
            ready_to_send = last_sent_profile is not None or streak_count >= args.stable_frames
            profile_changed = active_profile != last_sent_profile
            send_angle = angle_estimate is not None
            if ready_to_send and rows is not None and (profile_changed or send_angle):
                packet = make_stage11_request(sequence, rows, active_profile)
                written = port.write(packet)
                port.flush()
                if written != len(packet):
                    raise OSError(f"serial write accepted {written}/{len(packet)} bytes")
                read_ack(port, sequence, packet)
                last_accepted_rows = [list(row) for row in rows]
                last_sent_profile = active_profile
                accepted_count += 1
                if angle_estimate is not None:
                    previous_angle = relative_angle
                if profile_changed:
                    print(
                        f"ACK seq={sequence} profile={active_profile}:"
                        f"{PROFILE_NAMES[active_profile]} frame={frame_count} "
                        f"matrix={'identity' if args.identity else ('tracked' if send_angle else 'held')}"
                    )
                sequence = (sequence + 1) & 0xFFFF

            if frame_count == 1 or frame_count % args.report_every == 0:
                print(
                    f"frame={frame_count} candidate={candidate}:{PROFILE_NAMES[candidate]} "
                    f"stable={active_profile}:{PROFILE_NAMES[active_profile]} "
                    f"median={metrics.median:.0f} dark={metrics.dark_ratio:.1%} "
                    f"highlight={metrics.highlight_ratio:.1%} "
                    f"local_dark={metrics.local_dark_ratio:.1%} "
                    f"local_highlight={metrics.local_highlight_ratio:.1%} "
                    f"ACKs={accepted_count}"
                )
    except KeyboardInterrupt:
        print("stopped by user")
    except (serial.SerialException, OSError, TimeoutError, ValueError, cv2.error) as exc:
        raise SystemExit(f"adaptive enhancement stopped: {exc}; request was not retried") from exc
    finally:
        capture.release()
        if port is not None and port.is_open:
            port.close()

    print(f"frames={frame_count}; accepted updates={accepted_count}; last profile={last_sent_profile}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
