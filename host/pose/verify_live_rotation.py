"""Measure one signed turntable position per SPACE press after zero setup."""

from __future__ import annotations

import argparse
from collections import deque
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import queue
import sys
import threading
import time

import cv2
import numpy as np
import serial

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.device_config import load_device_config

from analyze_parallel_rotation import quantize, rotation_homography
from encode_rotation_images_uart import make_request, validate_stage8_profile
from measure_obs_rotation_send_uart import (
    DEFAULT_CALIBRATION, FIXED_REFERENCE, UART_BAUD, estimate_grid_angle,
    read_ack, wrap_half_turn,
)
from pose_geometry import load_calibration, read_image, validate_image_size
from track_obs_rotation_continuous import unwrap_near_reference


ROOT = Path(__file__).resolve().parents[2]
COUNTERS = ("raw_input_vsync_count", "input_published_count", "copied_count", "display_take_count")


class LatestCamera:
    def __init__(self, index: int, width: int, height: int, name: str):
        self.name = name
        self.cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
        if not self.cap.isOpened():
            raise RuntimeError(f"Cannot open {name} DirectShow index {index}")
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self.lock = threading.Lock()
        self.frame = None
        self.timestamp = 0.0
        self.count = 0
        self.failures = 0
        self.frame_times = deque(maxlen=600)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        while not self.stop.is_set():
            ok, frame = self.cap.read()
            with self.lock:
                if ok and frame is not None:
                    self.frame = frame
                    self.timestamp = time.monotonic()
                    self.frame_times.append(self.timestamp)
                    self.count += 1
                else:
                    self.failures += 1
            if not ok:
                time.sleep(0.02)

    def latest(self):
        with self.lock:
            return (None if self.frame is None else self.frame.copy(),
                    self.timestamp, self.count, self.failures)

    def stats(self):
        with self.lock:
            return self.timestamp, self.count, self.failures

    def recent_times(self, since: float):
        with self.lock:
            return [stamp for stamp in self.frame_times if stamp >= since]

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        self.cap.release()


class ProbeSnapshots:
    """Read user-exported Fabric Debugger snapshots without inventing counts."""
    def __init__(self, path: Path | None):
        self.path = path
        self.position = 0
        self.previous = None
        self.latest_window = None

    def poll(self):
        if self.path is None or not self.path.exists():
            return
        if self.path.stat().st_size < self.position:
            self.position = 0
            self.previous = None
        with self.path.open("r", encoding="utf-8") as stream:
            stream.seek(self.position)
            while True:
                start = stream.tell()
                line = stream.readline()
                if not line:
                    break
                try:
                    item = json.loads(line)
                    stamp = datetime.fromisoformat(item["time"].replace("Z", "+00:00"))
                    values = {key: int(str(item[key]), 0) for key in COUNTERS}
                except (ValueError, KeyError, TypeError):
                    # A writer may still be appending this line.
                    stream.seek(start)
                    break
                if self.previous is not None:
                    old_time, old = self.previous
                    seconds = (stamp - old_time).total_seconds()
                    if seconds > 0:
                        delta = {}
                        valid = True
                        for key in COUNTERS:
                            if key == "raw_input_vsync_count":
                                delta[key] = (values[key] - old[key]) & 0xFFFF
                            elif values[key] >= old[key] and values[key] != 0xFFFFFFFF:
                                delta[key] = values[key] - old[key]
                            else:
                                valid = False
                        self.latest_window = ({"seconds": seconds, "delta": delta,
                                               "end_time": stamp.isoformat()}
                                              if valid else {"error": "counter reset or saturated"})
                self.previous = (stamp, values)
                self.position = stream.tell()


def grid_angle_raw(frame: np.ndarray, board_size: tuple[int, int]) -> float | None:
    cols, rows = board_size
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    found, corners = cv2.findChessboardCornersSB(gray, (cols, rows),
                                                flags=cv2.CALIB_CB_EXHAUSTIVE | cv2.CALIB_CB_ACCURACY)
    if not found:
        return None
    grid = corners.reshape(rows, cols, 2)
    vectors = np.asarray([grid[row, cols - 2] - grid[row, 1] for row in range(1, rows - 1)])
    angles = np.arctan2(vectors[:, 1], vectors[:, 0])
    mean = np.mean(np.exp(2j * angles))
    return wrap_half_turn(math.degrees(0.5 * math.atan2(mean.imag, mean.real)))


def valid_area_percent(h: np.ndarray, calibration: dict, mesh: tuple[np.ndarray, np.ndarray]) -> float:
    """Predict strict 2x2 sample coverage from the sent homography and Brown model."""
    xx, yy = mesh
    den = h[2, 0] * xx + h[2, 1] * yy + h[2, 2]
    ix = (h[0, 0] * xx + h[0, 1] * yy + h[0, 2]) / den
    iy = (h[1, 0] * xx + h[1, 1] * yy + h[1, 2]) / den
    K = calibration["_camera_matrix"]
    d = calibration["_distortion"].ravel()
    k1, k2, p1, p2, k3 = (float(v) for v in d[:5])
    x = (ix - K[0, 2]) / K[0, 0]
    y = (iy - K[1, 2]) / K[1, 1]
    r2 = x*x + y*y
    radial = 1 + k1*r2 + k2*r2*r2 + k3*r2*r2*r2
    sx = K[0, 0] * (x*radial + 2*p1*x*y + p2*(r2+2*x*x)) + K[0, 2]
    sy = K[1, 1] * (y*radial + p1*(r2+2*y*y) + 2*p2*x*y) + K[1, 2]
    width, height = calibration["_image_size"]
    return 100 * float(np.mean(np.isfinite(sx) & np.isfinite(sy) &
                               (sx >= 0) & (sy >= 0) & (sx < width-1) & (sy < height-1)))


def parse_args():
    devices = load_device_config()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--obs-source", type=int, default=devices["obs_virtual_camera_index"])
    p.add_argument("--hdmi-source", type=int, default=devices["hdmi_capture_index"])
    p.add_argument("--port", default=devices["uart_port"])
    p.add_argument("--calibration", type=Path, default=DEFAULT_CALIBRATION)
    p.add_argument("--out", type=Path, default=ROOT / "host" / "verification" / "live_rotation")
    p.add_argument("--probe-snapshots", type=Path,
                   help="JSONL with time and four Fabric Debugger counters; see README")
    p.add_argument("--settle-seconds", type=float, default=0.5,
                   help="wait after UART ACK before measuring HDMI output (default 0.5)")
    return p.parse_args()


def write_jsonl(path: Path, value: dict):
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, allow_nan=False) + "\n")


def save_png(path: Path, frame: np.ndarray):
    ok, encoded = cv2.imencode(".png", frame)
    if not ok:
        raise ValueError(f"PNG encoding failed: {path}")
    encoded.tofile(str(path))


def put(frame, lines):
    for i, line in enumerate(lines):
        cv2.putText(frame, line, (15, 35 + 30*i), cv2.FONT_HERSHEY_SIMPLEX,
                    0.73, (0, 255, 255), 2, cv2.LINE_AA)


def main():
    args = parse_args()
    if args.settle_seconds < 0:
        raise SystemExit("--settle-seconds must be nonnegative")
    calibration = load_calibration(args.calibration)
    width, height = calibration["_image_size"]
    reference = read_image(FIXED_REFERENCE)
    validate_image_size(reference, calibration, "reference")
    reference_angle, _ = estimate_grid_angle(reference, calibration)
    K = calibration["_camera_matrix"]
    mesh = np.meshgrid(np.arange(width, dtype=np.float32),
                       np.arange(height, dtype=np.float32))
    args.out.mkdir(parents=True, exist_ok=True)
    log_file = args.out / "measurements.jsonl"
    probe = ProbeSnapshots(args.probe_snapshots)
    obs = hdmi = port = None
    sequence = int(time.time()) & 0xFFFF
    previous_angle = None
    last = {"estimated_angle_deg": None, "output_residual_deg": None,
            "valid_area_percent_predicted": None, "uart": "not sent", "matrix_q": None}
    checkpoint = 0
    zero_output_angle = None
    window = "OBS input | FPGA HDMI output"
    actual_angle = 0.0
    terminal_commands = queue.Queue()

    try:
        obs = LatestCamera(args.obs_source, width, height, "OBS")
        hdmi = LatestCamera(args.hdmi_source, width, height, "HDMI")
        port = serial.Serial(args.port, UART_BAUD, timeout=0.2, write_timeout=2.0)
        port.reset_input_buffer()
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        print(f"OBS={args.obs_source}, HDMI={args.hdmi_source}, UART={args.port}")
        def read_terminal_commands():
            while True:
                try:
                    command = input("角度(度)/z设零/m测量/q退出 > ").strip().lower()
                except EOFError:
                    terminal_commands.put("q")
                    return
                terminal_commands.put(command)
                if command == "q":
                    return

        threading.Thread(target=read_terminal_commands, daemon=True).start()
        print("终端输入角度并回车设置；输入 z 设置零位，m 测量一次，q 退出。")
        print("在预览窗口中也可用 z、空格、q 操作。")
        print(f"Measurements are written only after m/SPACE: {log_file}")
        while True:
            now = time.monotonic()
            obs_frame, obs_ts, obs_count, obs_fail = obs.latest()
            hdmi_frame, hdmi_ts, hdmi_count, hdmi_fail = hdmi.latest()
            probe.poll()
            left = np.zeros((height, width, 3), np.uint8) if obs_frame is None else obs_frame.copy()
            right = np.zeros((height, width, 3), np.uint8) if hdmi_frame is None else hdmi_frame.copy()
            put(left, [f"OBS frames: {obs_count}", f"Actual: {actual_angle:+.2f} deg",
                       f"Last estimate: {last['estimated_angle_deg']} deg"])
            put(right, [f"HDMI frames: {hdmi_count}", f"Residual: {last['output_residual_deg']} deg",
                        f"Valid area: {last['valid_area_percent_predicted']}%", f"UART: {last['uart']}",
                        "ZERO SET" if zero_output_angle is not None else "SET ZERO: press z at 0 deg"])
            cv2.imshow(window, np.hstack((left, right)))
            key = cv2.waitKey(1) & 0xFF
            try:
                command = terminal_commands.get_nowait()
            except queue.Empty:
                command = None
            if command is not None:
                if command in ("z", "m", "q"):
                    key = {"z": ord("z"), "m": 32, "q": ord("q")}[command]
                else:
                    try:
                        entered_angle = float(command)
                        if not math.isfinite(entered_angle):
                            raise ValueError("angle must be finite")
                        actual_angle = entered_angle
                        print(f"Actual angle set: {actual_angle:+.2f} deg", flush=True)
                    except ValueError:
                        print("输入无效。请输入角度数字（如 -12.5）、z、m 或 q。", flush=True)
            if key in (ord("q"), 27):
                break
            if key == ord("z"):
                if abs(actual_angle) > 0.1:
                    print("输入并确认 0 度后再设置零位。", flush=True)
                elif hdmi_frame is None or now-hdmi_ts >= 2:
                    print("No fresh HDMI frame; zero not set.", flush=True)
                elif hdmi_frame.shape[:2] != (height, width):
                    print("HDMI resolution is not 1280x720; zero not set.", flush=True)
                else:
                    angle = grid_angle_raw(hdmi_frame, calibration["_board_size"])
                    if angle is None:
                        print("Full checkerboard not found in HDMI output; zero not set.", flush=True)
                    else:
                        zero_output_angle = angle
                        print(f"Output zero set: {zero_output_angle:+.3f} deg. No measurement sent yet.", flush=True)
            if key == 32:
                if zero_output_angle is None:
                    print("First set the zero position with z; no measurement made.", flush=True)
                    continue
                if obs_frame is None or now-obs_ts >= 2 or obs_frame.shape[:2] != (height, width):
                    print("No fresh 1280x720 OBS frame; no measurement made.", flush=True)
                    continue
                if hdmi_frame is None or now-hdmi_ts >= 2 or hdmi_frame.shape[:2] != (height, width):
                    print("No fresh 1280x720 HDMI frame; no measurement made.", flush=True)
                    continue
                try:
                    angle, spread = estimate_grid_angle(obs_frame, calibration)
                    estimated = unwrap_near_reference(wrap_half_turn(angle-reference_angle), previous_angle)
                    h = rotation_homography(estimated, float(K[0, 2]), float(K[1, 2]))
                    rows = quantize(h)["integer_rows"]
                    validate_stage8_profile(rows, width, height)
                    area = valid_area_percent(h, calibration, mesh)
                except (ValueError, cv2.error) as exc:
                    print(f"Input angle measurement failed: {exc}; no UART request or log entry.", flush=True)
                    continue
                measurement_start = datetime.now(timezone.utc)
                request = make_request(sequence, rows)
                uart_state = "ACK"
                try:
                    if port.write(request) != len(request):
                        raise IOError("short UART write")
                    port.flush()
                    read_ack(port, sequence, request)
                except (OSError, ValueError, TimeoutError, serial.SerialException) as exc:
                    uart_state = f"ERROR: {exc}"
                if uart_state == "ACK":
                    previous_angle = estimated
                    sequence = (sequence + 1) & 0xFFFF
                    time.sleep(args.settle_seconds)
                output_frame, output_ts, output_count, output_fail = hdmi.latest()
                output_angle = (grid_angle_raw(output_frame, calibration["_board_size"])
                                if uart_state == "ACK" and output_frame is not None
                                and time.monotonic()-output_ts < 2 else None)
                residual = (None if output_angle is None else
                            round(wrap_half_turn(output_angle-zero_output_angle), 3))
                probe.poll()
                probe_window = probe.latest_window
                if probe_window is not None and "end_time" in probe_window:
                    probe_end = datetime.fromisoformat(probe_window["end_time"])
                    probe_start = probe_end.timestamp() - probe_window["seconds"]
                    if (probe_start < measurement_start.timestamp()
                            or probe_end > datetime.now(timezone.utc)):
                        probe_window = None
                else:
                    probe_window = None
                checkpoint += 1
                image_paths = {"obs_input_png": None, "hdmi_output_png": None}
                image_errors = []
                image_dir = args.out / "frames"
                image_stem = (f"checkpoint_{checkpoint:03d}_"
                              f"{measurement_start.strftime('%Y%m%d_%H%M%S_%f')}")
                for field, suffix, image in (
                    ("obs_input_png", "obs", obs_frame),
                    ("hdmi_output_png", "hdmi", output_frame),
                ):
                    if image is None:
                        image_errors.append(f"{suffix} frame unavailable")
                        continue
                    try:
                        image_dir.mkdir(parents=True, exist_ok=True)
                        image_path = image_dir / f"{image_stem}_{suffix}.png"
                        save_png(image_path, image)
                        image_paths[field] = str(image_path.resolve())
                    except (OSError, ValueError, cv2.error) as exc:
                        image_errors.append(f"{suffix}: {exc}")
                entry = {"time": datetime.now(timezone.utc).isoformat(), "checkpoint": checkpoint,
                         "actual_angle_deg": actual_angle, "estimated_angle_deg": round(estimated, 3),
                         "input_grid_spread_deg": round(spread, 3),
                         "output_grid_angle_deg": output_angle, "output_residual_deg": residual,
                         "valid_area_percent_predicted": round(area, 3), "matrix_q": rows,
                         "uart": uart_state, "sequence": (sequence-1) & 0xFFFF if uart_state == "ACK" else sequence,
                         "obs_captured_frames": obs_count, "hdmi_captured_frames": output_count,
                         "fpga_counter_window": probe_window,
                         **image_paths, "image_save_errors": image_errors}
                write_jsonl(log_file, entry)
                print(f"measurement {checkpoint}: {json.dumps(entry, ensure_ascii=False)}", flush=True)
                if image_errors:
                    print(f"Image save warning: {'; '.join(image_errors)}", flush=True)
                last = entry
    except KeyboardInterrupt:
        pass
    finally:
        if obs is not None:
            obs.close()
        if hdmi is not None:
            hdmi.close()
        if port is not None:
            port.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
