"""Track checkerboard corners and send live image-plane rotation matrices to Stage 8."""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

import cv2
import numpy as np
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


class PartialBoardAngleTracker:
    """Acquire a full board once, then estimate roll from tracked partial corners."""

    MIN_INLIERS = 8
    MIN_INLIER_RATIO = 0.60
    MAX_FORWARD_BACKWARD_ERROR = 1.5

    def __init__(self, calibration: dict) -> None:
        self.calibration = calibration
        self.previous_gray: object | None = None
        self.previous_points = None
        self.reference_points = None
        self.initial_angle: float | None = None
        self.last_mode = "waiting"

    def _gray(self, frame):
        return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    def _undistort(self, points):
        return cv2.undistortPoints(
            points.reshape(-1, 1, 2),
            self.calibration["_camera_matrix"],
            self.calibration["_distortion"],
            P=self.calibration["_camera_matrix"],
        ).reshape(-1, 2)

    def _acquire_full_board(self, gray):
        cols, rows = self.calibration["_board_size"]
        flags = cv2.CALIB_CB_EXHAUSTIVE | cv2.CALIB_CB_ACCURACY
        found, corners = cv2.findChessboardCornersSB(gray, (cols, rows), flags=flags)
        if not found:
            return None

        self.previous_gray = gray
        self.previous_points = corners.reshape(-1, 1, 2).astype("float32")
        self.reference_points = self._undistort(self.previous_points)
        undistorted = self.reference_points.reshape(rows, cols, 2)
        row_vectors = np.asarray([
            undistorted[row, cols - 2] - undistorted[row, 1]
            for row in range(1, rows - 1)
        ])
        row_angles = np.arctan2(row_vectors[:, 1], row_vectors[:, 0])
        doubled_mean = np.mean(np.exp(2j * row_angles))
        angle = math.degrees(0.5 * math.atan2(doubled_mean.imag, doubled_mean.real))
        self.initial_angle = ((angle + 90.0) % 180.0) - 90.0
        self.last_mode = "full-board lock"
        return self.initial_angle, len(self.previous_points), len(self.previous_points)

    def update(self, frame):
        """Return (angle, tracked_count, inlier_count), or None when confidence is low."""
        gray = self._gray(frame)
        if self.previous_gray is None or self.previous_points is None:
            result = self._acquire_full_board(gray)
            if result is None:
                self.last_mode = "waiting"
            return result

        next_points, forward_status, _ = cv2.calcOpticalFlowPyrLK(
            self.previous_gray,
            gray,
            self.previous_points,
            None,
            winSize=(21, 21),
            maxLevel=3,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
        )
        if next_points is None or forward_status is None:
            self._reset()
            return self._acquire_full_board(gray)

        backward_points, backward_status, _ = cv2.calcOpticalFlowPyrLK(
            gray,
            self.previous_gray,
            next_points,
            None,
            winSize=(21, 21),
            maxLevel=3,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
        )
        if backward_points is None or backward_status is None:
            self._reset()
            return self._acquire_full_board(gray)

        forward = next_points.reshape(-1, 2)
        backward = backward_points.reshape(-1, 2)
        fb_error = ((backward - self.previous_points.reshape(-1, 2)) ** 2).sum(axis=1) ** 0.5
        valid = (
            forward_status.reshape(-1).astype(bool)
            & backward_status.reshape(-1).astype(bool)
            & (fb_error <= self.MAX_FORWARD_BACKWARD_ERROR)
        )
        tracked = int(valid.sum())
        if tracked < self.MIN_INLIERS:
            self._reset()
            self.last_mode = "waiting for full-board reacquisition"
            return None

        current_ideal = self._undistort(next_points[valid])
        reference = self.reference_points[valid]
        matrix, ransac_mask = cv2.estimateAffinePartial2D(
            reference.astype("float32"),
            current_ideal.astype("float32"),
            method=cv2.RANSAC,
            ransacReprojThreshold=2.0,
            maxIters=200,
            confidence=0.99,
            refineIters=10,
        )
        inliers = int(ransac_mask.sum()) if ransac_mask is not None else 0
        if (
            matrix is None
            or inliers < self.MIN_INLIERS
            or inliers / tracked < self.MIN_INLIER_RATIO
        ):
            self._reset()
            self.last_mode = "waiting for full-board reacquisition"
            return None

        # Keep only RANSAC inliers and their original board-corner identities.
        valid_indices = valid.nonzero()[0]
        inlier_indices = valid_indices[ransac_mask.reshape(-1).astype(bool)]
        self.previous_gray = gray
        self.previous_points = next_points[inlier_indices].reshape(-1, 1, 2)
        self.reference_points = self.reference_points[inlier_indices]
        delta_angle = math.degrees(math.atan2(float(matrix[1, 0]), float(matrix[0, 0])))
        self.last_mode = "partial-board tracking"
        return self.initial_angle + delta_angle, tracked, inliers

    def _reset(self) -> None:
        self.previous_gray = None
        self.previous_points = None
        self.reference_points = None
        self.initial_angle = None


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
    angle_tracker = PartialBoardAngleTracker(calibration)
    target_was_visible = False
    sent_count = 0
    last_angle = math.nan
    report_at = time.monotonic() + 1.0
    report_count = 0
    port: serial.Serial | None = None

    print(f"fixed reference: {FIXED_REFERENCE}")
    print(f"reference grid angle: {reference_angle:+.3f} deg")
    print(f"stream: source={args.source}, UART={args.port} at {UART_BAUD} baud")
    print("full-board acquisition, then partial-corner tracking; confident estimate -> request -> ACK")
    print("low confidence holds the FPGA's last matrix until a full board can be reacquired")

    try:
        port = serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0)
        port.reset_input_buffer()
        port.reset_output_buffer()

        while True:
            ok, frame = capture.read()
            if not ok:
                continue
            validate_image_size(frame, calibration, "OBS frame")

            estimate = angle_tracker.update(frame)
            if estimate is None:
                if target_was_visible:
                    print("partial-board tracking lost; holding FPGA's last accepted matrix")
                    target_was_visible = False
                continue

            current_angle, tracked_count, inlier_count = estimate

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
                print(
                    f"accepted updates/s={report_count}; angle={last_angle:+.3f} deg; "
                    f"mode={angle_tracker.last_mode}; corners={inlier_count}/{tracked_count}; total={sent_count}"
                )
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
