"""Estimate short-term camera shake from OBS frames and send Stage13 dx/dy."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import serial

from encode_rotation_images_uart import crc16_ccitt_false
from measure_obs_rotation_send_uart import read_ack
from track_obs_rotation_continuous import parse_source


UART_BAUD = 115200
PACKET_LENGTH = 65
FRAME_WIDTH = 1280
FRAME_HEIGHT = 720
IDENTITY_ROWS = [
    [0x00010000, 0, 0],
    [0, 0x00010000, 0],
    [0, 0, 0x40000000],
]


class ShakeOnlyCompensator:
    """Remove high-frequency translation while following sustained camera motion.

    dx/dy are apparent image displacement from the previous frame to the current
    frame. The low-pass trajectory follows deliberate, sustained movement. The
    high-frequency path residual becomes a source-coordinate sampling offset; it has
    the same sign as the apparent image displacement because the FPGA adds the offset
    to its source sample coordinates. This is a temporal heuristic, not an intent classifier.
    """

    def __init__(self, alpha: float = 0.18, max_correction_px: float = 8.0) -> None:
        if not 0.0 < alpha <= 1.0:
            raise ValueError("alpha must be in (0, 1]")
        if max_correction_px <= 0:
            raise ValueError("max_correction_px must be positive")
        self.alpha = alpha
        self.max_correction_px = max_correction_px
        self.path_x = 0.0
        self.path_y = 0.0
        self.trend_x = 0.0
        self.trend_y = 0.0

    def reset(self) -> None:
        self.path_x = self.path_y = 0.0
        self.trend_x = self.trend_y = 0.0

    def update(self, dx: float, dy: float) -> tuple[float, float, float, float]:
        if not np.isfinite(dx) or not np.isfinite(dy):
            raise ValueError("motion estimate must be finite")
        self.path_x += float(dx)
        self.path_y += float(dy)
        self.trend_x += self.alpha * (self.path_x - self.trend_x)
        self.trend_y += self.alpha * (self.path_y - self.trend_y)
        correction_x = float(np.clip(self.path_x - self.trend_x,
                                     -self.max_correction_px, self.max_correction_px))
        correction_y = float(np.clip(self.path_y - self.trend_y,
                                     -self.max_correction_px, self.max_correction_px))
        return correction_x, correction_y, self.trend_x, self.trend_y


def estimate_translation(previous_gray: np.ndarray, current_gray: np.ndarray
                         ) -> tuple[float, float, float, int]:
    """Estimate previous-to-current global translation from sparse LK flow.

    Forward/backward consistency rejects unstable tracks. A robust median-flow
    consensus then rejects independently moving objects and corner outliers.
    Returns dx, dy, inlier ratio, and inlier count.
    """
    if previous_gray.shape != current_gray.shape or previous_gray.ndim != 2:
        raise ValueError("input frames must be same-sized grayscale images")
    points = cv2.goodFeaturesToTrack(
        previous_gray, maxCorners=600, qualityLevel=0.01, minDistance=9,
        blockSize=7, useHarrisDetector=False,
    )
    if points is None or len(points) < 12:
        raise ValueError("not enough trackable features")
    forward, status_f, _ = cv2.calcOpticalFlowPyrLK(
        previous_gray, current_gray, points, None, winSize=(21, 21), maxLevel=3,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
    )
    if forward is None or status_f is None:
        raise ValueError("forward optical flow failed")
    backward, status_b, _ = cv2.calcOpticalFlowPyrLK(
        current_gray, previous_gray, forward, None, winSize=(21, 21), maxLevel=3,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
    )
    if backward is None or status_b is None:
        raise ValueError("backward optical flow failed")
    fb_error = np.linalg.norm(points.reshape(-1, 2) - backward.reshape(-1, 2), axis=1)
    good = (status_f.reshape(-1) != 0) & (status_b.reshape(-1) != 0) & (fb_error <= 1.25)
    flow = forward.reshape(-1, 2) - points.reshape(-1, 2)
    flow = flow[good]
    if len(flow) < 12:
        raise ValueError("too few forward/backward-consistent tracks")

    center = np.median(flow, axis=0)
    residual = np.linalg.norm(flow - center, axis=1)
    mad = float(np.median(np.abs(residual - np.median(residual))))
    threshold = max(0.75, float(np.median(residual)) + 3.0 * 1.4826 * mad)
    inliers = flow[residual <= threshold]
    if len(inliers) < 12:
        raise ValueError("global motion consensus is too small")
    confidence = len(inliers) / max(len(points), 1)
    return (float(np.median(inliers[:, 0])), float(np.median(inliers[:, 1])),
            float(confidence), int(len(inliers)))


def _signed_q16(value: float) -> bytes:
    scaled = int(round(value * 65536.0))
    if not -(1 << 31) <= scaled < (1 << 31):
        raise ValueError(f"translation outside signed Q16.16 range: {value}")
    return scaled.to_bytes(4, "little", signed=True)


def make_stage13_request(sequence: int, homography_rows: list[int], profile_id: int,
                         dx: float, dy: float, enabled: bool = True) -> bytes:
    """Build a v2 65-byte request; Stage13 assigns bytes 44..51 to Q16.16 dx/dy.

    Flag bit 0 requests a homography update. By default it is clear so a
    translation-only request leaves the active Stage13 homography untouched.
    Flag bit 1 enables translation compensation.
    """
    if not 0 <= sequence <= 0xFFFF:
        raise ValueError("sequence must be in 0..65535")
    if len(homography_rows) != 9:
        raise ValueError("homography_rows must contain nine signed 32-bit words")
    if not 0 <= profile_id <= 5:
        raise ValueError("profile_id must be in 0..5")
    if abs(dx) > 24.0 or abs(dy) > 24.0:
        raise ValueError("translation must be within ±24 source pixels")
    flags = (0x02 if enabled else 0x00)
    packet = bytearray((0xA5, 0x5A, 0x02, 0x01, sequence & 0xFF,
                        sequence >> 8, flags))
    for value in homography_rows:
        if not -(1 << 31) <= int(value) < (1 << 31):
            raise ValueError("homography coefficient outside signed 32-bit range")
        packet.extend((int(value) & 0xFFFFFFFF).to_bytes(4, "little"))
    packet.append(profile_id)
    packet.extend(_signed_q16(dx))
    packet.extend(_signed_q16(dy))
    packet.extend(bytes(11))
    crc = crc16_ccitt_false(packet[2:63])
    packet.extend((crc >> 8, crc & 0xFF))
    if len(packet) != PACKET_LENGTH:
        raise RuntimeError(f"internal packet length error: {len(packet)}")
    return bytes(packet)


def parse_source(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def resize_for_fpga(frame: np.ndarray, width: int, height: int) -> np.ndarray:
    """Fit capture frames to FPGA coordinates without changing their aspect ratio."""
    if frame is None or frame.ndim not in (2, 3):
        raise ValueError("frame must be a grayscale or color image")
    source_height, source_width = frame.shape[:2]
    if source_width == width and source_height == height:
        return frame
    scale = min(width / source_width, height / source_height)
    resized_width = max(1, min(width, int(round(source_width * scale))))
    resized_height = max(1, min(height, int(round(source_height * scale))))
    interpolation = (cv2.INTER_AREA
                     if resized_width < source_width or resized_height < source_height
                     else cv2.INTER_LINEAR)
    resized = cv2.resize(frame, (resized_width, resized_height), interpolation=interpolation)
    if frame.ndim == 2:
        fitted = np.zeros((height, width), dtype=frame.dtype)
    else:
        fitted = np.zeros((height, width, frame.shape[2]), dtype=frame.dtype)
    left = (width - resized_width) // 2
    top = (height - resized_height) // 2
    fitted[top:top + resized_height, left:left + resized_width] = resized
    return fitted


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=parse_source, default=2,
                        help="OBS Virtual Camera index (default 2) or video path")
    parser.add_argument("--port", default="COM7", help="USB-UART port (default COM7)")
    parser.add_argument("--profile", type=int, default=0,
                        help="Stage11 lighting profile to retain in the packet (0..5)")
    parser.add_argument("--width", type=int, default=FRAME_WIDTH,
                        help="FPGA source coordinate width (default 1280)")
    parser.add_argument("--height", type=int, default=FRAME_HEIGHT,
                        help="FPGA source coordinate height (default 720)")
    parser.add_argument("--sequence", type=int, default=int(time.time()) & 0xFFFF)
    parser.add_argument("--alpha", type=float, default=0.18,
                        help="low-pass response; lower values preserve slower motion")
    parser.add_argument("--max-correction", type=float, default=24.0,
                        help="maximum correction per axis in source pixels")
    parser.add_argument("--min-confidence", type=float, default=0.25,
                        help="reject global-flow estimates with weaker inlier support")
    parser.add_argument("--max-motion-per-frame", type=float, default=40.0,
                        help="reject implausible global displacement magnitude per frame in source pixels")
    parser.add_argument("--motion-deadband", type=float, default=0.10,
                        help="ignore per-frame optical-flow motion below this magnitude in source pixels")
    parser.add_argument("--report-every", type=int, default=10)
    parser.add_argument("--dry-run", action="store_true",
                        help="estimate and print packets without opening UART")
    parser.add_argument("--display", action="store_true", help="show tracking preview")
    args = parser.parse_args(argv)
    if not 0 <= args.sequence <= 0xFFFF:
        parser.error("--sequence must be in 0..65535")
    if not 0 <= args.profile <= 5:
        parser.error("--profile must be in 0..5")
    if args.width < 1 or args.height < 1:
        parser.error("--width and --height must be positive")
    if not 0.0 <= args.min_confidence <= 1.0:
        parser.error("--min-confidence must be in [0, 1]")
    if args.max_motion_per_frame <= 0:
        parser.error("--max-motion-per-frame must be positive")
    if args.motion_deadband < 0:
        parser.error("--motion-deadband must be non-negative")
    if not 0.0 < args.alpha <= 1.0:
        parser.error("--alpha must be in (0, 1]")
    if not 0.0 < args.max_correction <= 24.0:
        parser.error("--max-correction must be in (0, 24] source pixels")
    if args.report_every < 1:
        parser.error("--report-every must be positive")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    capture = cv2.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"could not open frame source: {args.source}")
    if isinstance(args.source, int):
        # Request the FPGA input raster instead of accepting OpenCV's common
        # 640x480 default camera mode. Some drivers may ignore this request.
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    port = None
    previous_gray = None
    compensator = ShakeOnlyCompensator(args.alpha, args.max_correction)
    sequence = args.sequence
    frame_index = accepted = invalid = 0
    tracking_rejects = confidence_rejects = motion_rejects = 0
    last_log = time.monotonic()
    aspect_warning_shown = False
    capture_size_reported = False
    try:
        if not args.dry_run:
            port = serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0)
            port.reset_input_buffer()
            port.reset_output_buffer()
        print("Stage13 shake-only translation tracker; sustained motion follows the low-pass trend")
        print(f"source={args.source}; UART={'dry-run' if args.dry_run else args.port}; max=+/-{args.max_correction:.1f}px")
        print(f"gates: confidence>={args.min_confidence:.2f}; motion<={args.max_motion_per_frame:.1f}px/frame; "
              f"deadband={args.motion_deadband:.2f}px/frame")
        while True:
            ok, frame = capture.read()
            if not ok:
                if isinstance(args.source, str):
                    break
                continue
            source_height, source_width = frame.shape[:2]
            if not capture_size_reported:
                if isinstance(args.source, int):
                    print(f"camera mode requested={args.width}x{args.height}, "
                          f"actual={source_width}x{source_height}")
                capture_size_reported = True
            if (not aspect_warning_shown and
                    abs(source_width / source_height - args.width / args.height) > 0.01):
                print(f"warning: preserving {source_width}x{source_height} aspect ratio inside "
                      f"{args.width}x{args.height} coordinates with black padding; "
                      "dx/dy use FPGA source-pixel units")
                aspect_warning_shown = True
            frame = resize_for_fpga(frame, args.width, args.height)
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            if previous_gray is None:
                previous_gray = gray
                continue
            try:
                motion_x, motion_y, confidence, inliers = estimate_translation(previous_gray, gray)
            except ValueError:
                invalid += 1
                tracking_rejects += 1
                previous_gray = gray
                if args.display and cv2.waitKey(1) & 0xFF == ord("q"):
                    break
                continue
            previous_gray = gray
            if confidence < args.min_confidence:
                invalid += 1
                confidence_rejects += 1
                continue
            if np.hypot(motion_x, motion_y) > args.max_motion_per_frame:
                invalid += 1
                motion_rejects += 1
                continue
            flow_x, flow_y = motion_x, motion_y
            if np.hypot(flow_x, flow_y) < args.motion_deadband:
                motion_x = motion_y = 0.0
            correction_x, correction_y, trend_x, trend_y = compensator.update(motion_x, motion_y)
            packet = make_stage13_request(
                sequence, [value for row in IDENTITY_ROWS for value in row],
                args.profile, correction_x, correction_y,
            )
            if port is not None:
                written = port.write(packet)
                port.flush()
                if written != len(packet):
                    raise OSError(f"UART accepted {written}/{len(packet)} bytes")
                read_ack(port, sequence, packet)
            sequence = (sequence + 1) & 0xFFFF
            frame_index += 1
            if args.display:
                preview = frame.copy()
                cv2.putText(preview, f"motion=({motion_x:+.2f},{motion_y:+.2f}) px  flow=({flow_x:+.2f},{flow_y:+.2f})",
                            (16, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                cv2.putText(preview, f"correction=({correction_x:+.2f},{correction_y:+.2f}) trend=({trend_x:+.2f},{trend_y:+.2f})",
                            (16, 54), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
                cv2.imshow("Stage13 motion stabilization", preview)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
            now = time.monotonic()
            if frame_index % args.report_every == 0 or now - last_log >= 1.0:
                print(f"motion=({motion_x:+.2f},{motion_y:+.2f}) flow=({flow_x:+.2f},{flow_y:+.2f}) "
                      f"correction=({correction_x:+.2f},{correction_y:+.2f}) "
                      f"trend=({trend_x:+.2f},{trend_y:+.2f}) confidence={confidence:.2f} inliers={inliers} "
                      f"seq={sequence:04X} accepted={frame_index} invalid={invalid} "
                      f"reject(track={tracking_rejects},confidence={confidence_rejects},motion={motion_rejects}) "
                      f"request={packet.hex(' ').upper()}")
                last_log = now
    except KeyboardInterrupt:
        pass
    except (serial.SerialException, OSError, TimeoutError, ValueError, cv2.error) as exc:
        raise SystemExit(f"motion stabilization stopped: {exc}") from exc
    finally:
        capture.release()
        if port is not None and port.is_open:
            port.close()
        cv2.destroyAllWindows()
    print(f"stopped; accepted updates={frame_index}, rejected estimates={invalid} "
          f"(track={tracking_rejects}, confidence={confidence_rejects}, motion={motion_rejects})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
