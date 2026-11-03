"""Measure Stage13 stabilization from OBS input and captured FPGA HDMI output.

SPACE starts/stops a measurement. No measurements or log rows are produced
while waiting. Use separate runs with --control off/on for an A/B comparison.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time

import cv2
import numpy as np
import serial

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.device_config import load_device_config

from measure_obs_rotation_send_uart import read_ack
from stage13_motion_stabilization import (
    FRAME_HEIGHT, FRAME_WIDTH, IDENTITY_ROWS, ShakeOnlyCompensator,
    estimate_translation, make_stage13_request, resize_for_fpga,
)
from verify_live_rotation import LatestCamera, ProbeSnapshots, write_jsonl


ROOT = Path(__file__).resolve().parents[2]


def args_from_cli():
    devices = load_device_config()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--obs-source", type=int, default=devices["obs_virtual_camera_index"],
                   help="OBS Virtual Camera DirectShow index")
    p.add_argument("--hdmi-source", type=int, default=devices["hdmi_capture_index"],
                   help="USB HDMI capture DirectShow index")
    p.add_argument("--port", default=devices["uart_port"])
    p.add_argument("--mode", choices=("fixed", "perturbation", "continuous"), default="fixed")
    p.add_argument("--control", choices=("on", "off"), default="on",
                   help="on sends compensation; off sends disabled translation for A/B baseline")
    p.add_argument("--alpha", type=float, default=0.18)
    p.add_argument("--max-correction", type=float, default=24.0,
                   help="maximum correction per axis in source pixels (default 24)")
    p.add_argument("--min-confidence", type=float, default=0.25)
    p.add_argument("--max-motion-per-frame", type=float, default=40.0)
    p.add_argument("--motion-deadband", type=float, default=0.10)
    p.add_argument("--sample-interval", type=float, default=0.10,
                   help="minimum interval between optical flow evaluations")
    p.add_argument("--out", type=Path, default=ROOT / "host" / "verification" / "motion_stabilization")
    p.add_argument("--probe-snapshots", type=Path,
                   help="optional Fabric Debugger JSONL with four frame counters")
    a = p.parse_args()
    if not 0 < a.alpha <= 1 or not 0 < a.max_correction <= 24:
        p.error("--alpha must be in (0,1], --max-correction in (0,24]")
    if not 0 <= a.min_confidence <= 1 or a.max_motion_per_frame <= 0:
        p.error("confidence/motion thresholds are out of range")
    if a.motion_deadband < 0 or a.sample_interval <= 0:
        p.error("deadband must be nonnegative and sample interval positive")
    return a


def interval_stats(times: list[float]) -> dict:
    intervals = np.diff(np.asarray(times, dtype=np.float64))
    if len(intervals) == 0:
        return {"mean_ms": None, "p95_ms": None, "max_ms": None}
    return {"mean_ms": round(1000 * float(np.mean(intervals)), 2),
            "p95_ms": round(1000 * float(np.percentile(intervals, 95)), 2),
            "max_ms": round(1000 * float(np.max(intervals)), 2)}


def border_black_percent(frame: np.ndarray, threshold: int = 12) -> float:
    """Boundary-connected near-black candidate area; scene black may be included."""
    dark = (cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) <= threshold).astype(np.uint8)
    count, labels = cv2.connectedComponents(dark, connectivity=8)
    edges = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    edges = edges[(edges > 0) & (edges < count)]
    return round(100 * float(np.isin(labels, edges).mean()), 3)


class MotionTrack:
    def __init__(self):
        self.previous = None
        self.last_count = 0
        self.path = np.zeros(2, dtype=np.float64)
        self.samples = []
        self.moves = []
        self.invalid = 0
        self.last_confidence = None
        self.last_inliers = None

    def consume(self, frame: np.ndarray, count: int):
        if count == self.last_count:
            return None
        self.last_count = count
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if self.previous is None:
            self.previous = gray
            self.samples.append(self.path.copy())
            return None
        old = self.previous
        self.previous = gray
        try:
            dx, dy, confidence, inliers = estimate_translation(old, gray)
        except (ValueError, cv2.error):
            self.invalid += 1
            return None
        self.last_confidence, self.last_inliers = confidence, inliers
        motion = np.array((dx, dy), dtype=np.float64)
        self.path += motion
        self.samples.append(self.path.copy())
        self.moves.append(motion)
        return dx, dy, confidence, inliers

    def variance(self):
        if len(self.samples) < 2:
            return None
        return round(float(np.var(np.asarray(self.samples), axis=0).sum()), 4)


def preview_text(frame, lines):
    for index, line in enumerate(lines):
        cv2.putText(frame, line, (12, 30 + 27*index), cv2.FONT_HERSHEY_SIMPLEX,
                    0.65, (0, 255, 255), 2, cv2.LINE_AA)


def main():
    a = args_from_cli()
    a.out.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = a.out / f"{run_id}_{a.mode}_{a.control}.jsonl"
    obs = hdmi = port = None
    probe = ProbeSnapshots(a.probe_snapshots)
    sequence = int(time.time()) & 0xFFFF
    session = 0
    active = False
    start_wall = None
    start_mono = 0.0
    last_report = 0.0
    previous_obs = previous_hdmi = 0
    input_track = output_track = None
    compensator = None
    obs_window_start = hdmi_window_start = 0
    accepted = rejected = ack = nack = uart_other_error = 0
    session_obs_start = session_hdmi_start = 0
    last_flow = last_correction = None
    last_uart = "idle"
    uart_enabled = True
    window = "Stage13: OBS input | FPGA HDMI output (SPACE start/stop, q quit)"

    def emit(record):
        write_jsonl(log_path, record)
        print(json.dumps(record, ensure_ascii=False, allow_nan=False), flush=True)

    def summary(now):
        input_var = input_track.variance()
        output_var = output_track.variance()
        return {"type": "summary", "time": datetime.now(timezone.utc).isoformat(),
                "session": session, "mode": a.mode, "control": a.control,
                "duration_s": round(now-start_mono, 3), "resolution": [FRAME_WIDTH, FRAME_HEIGHT],
                "obs_captured_frames": obs_count-session_obs_start,
                "hdmi_captured_frames": hdmi_count-session_hdmi_start,
                "sources": {"obs": a.obs_source, "hdmi": a.hdmi_source, "uart": a.port},
                "observed_resolution": {
                    "obs": list(obs_frame.shape[1::-1]) if obs_frame is not None else None,
                    "hdmi": list(hdmi_frame.shape[1::-1]) if hdmi_frame is not None else None},
                "filters": {"alpha": a.alpha, "max_correction_px": a.max_correction,
                            "min_confidence": a.min_confidence,
                            "max_motion_per_frame": a.max_motion_per_frame,
                            "motion_deadband": a.motion_deadband},
                "valid_estimates": accepted,
                "invalid_estimates": rejected + input_track.invalid,
                "invalid_ratio": round((rejected + input_track.invalid) /
                                       max(accepted+rejected+input_track.invalid, 1), 4),
                "uart_ack": ack, "uart_nack": nack,
                "uart_other_error": uart_other_error,
                "input_background_path_variance_px2": input_var,
                "output_background_path_variance_px2": output_var,
                "variance_ratio_output_over_input": (
                    round(output_var/input_var, 4) if input_var and output_var is not None else None),
                "input_track_failures": input_track.invalid,
                "output_track_failures": output_track.invalid,
                "fpga_counter_window": matching_probe_window(probe, start_wall)}

    try:
        obs = LatestCamera(a.obs_source, FRAME_WIDTH, FRAME_HEIGHT, "OBS")
        hdmi = LatestCamera(a.hdmi_source, FRAME_WIDTH, FRAME_HEIGHT, "HDMI")
        port = serial.Serial(a.port, 115200, timeout=0.2, write_timeout=2.0)
        port.reset_input_buffer()
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        print(f"OBS DirectShow={a.obs_source}; HDMI DirectShow={a.hdmi_source}; UART={a.port}")
        print(f"Preview only. SPACE starts a {a.mode}/{a.control} measurement; SPACE again stops it. Log: {log_path}")
        while True:
            now = time.monotonic()
            obs_frame, obs_ts, obs_count, _ = obs.latest()
            hdmi_frame, hdmi_ts, hdmi_count, _ = hdmi.latest()
            if active:
                if obs_frame is not None and obs_count != previous_obs and now-obs_ts < 2:
                    previous_obs = obs_count
                    if now-last_input_sample >= a.sample_interval:
                        last_input_sample = now
                        fitted = resize_for_fpga(obs_frame, FRAME_WIDTH, FRAME_HEIGHT)
                        estimate = input_track.consume(fitted, obs_count)
                        if estimate is not None:
                            dx, dy, confidence, inliers = estimate
                            last_flow = [round(dx, 3), round(dy, 3)]
                            if (confidence < a.min_confidence or
                                    np.hypot(dx, dy) > a.max_motion_per_frame):
                                rejected += 1
                            else:
                                accepted += 1
                                if np.hypot(dx, dy) < a.motion_deadband:
                                    dx = dy = 0.0
                                cx, cy, _, _ = compensator.update(dx, dy)
                                last_correction = [round(cx, 3), round(cy, 3)]
                                if uart_enabled:
                                    request = make_stage13_request(
                                        sequence, [v for row in IDENTITY_ROWS for v in row],
                                        0, cx if a.control == "on" else 0.0,
                                        cy if a.control == "on" else 0.0,
                                        enabled=(a.control == "on"))
                                    try:
                                        if port.write(request) != len(request):
                                            raise OSError("short UART write")
                                        port.flush()
                                        read_ack(port, sequence, request)
                                        ack += 1
                                        last_uart = f"ACK seq={sequence}"
                                        sequence = (sequence + 1) & 0xFFFF
                                    except (OSError, ValueError, TimeoutError, serial.SerialException) as exc:
                                        if isinstance(exc, ValueError) and str(exc).startswith("FPGA rejected"):
                                            nack += 1
                                        else:
                                            uart_other_error += 1
                                        last_uart = f"ERROR {exc}"
                                        uart_enabled = False
                if hdmi_frame is not None and hdmi_count != previous_hdmi and now-hdmi_ts < 2:
                    previous_hdmi = hdmi_count
                    if now-last_output_sample >= a.sample_interval:
                        last_output_sample = now
                        if hdmi_frame.shape[:2] == (FRAME_HEIGHT, FRAME_WIDTH):
                            output_track.consume(hdmi_frame, hdmi_count)
                probe.poll()
                if now-last_report >= 1.0:
                    obs_n = obs_count-obs_window_start
                    hdmi_n = hdmi_count-hdmi_window_start
                    record = {"type": "second", "time": datetime.now(timezone.utc).isoformat(),
                              "session": session, "elapsed_s": round(now-start_mono, 2),
                              "mode": a.mode, "control": a.control,
                              "obs_captured_frames_window": obs_n,
                              "hdmi_captured_frames_window": hdmi_n,
                              "obs_frame_interval": interval_stats(obs.recent_times(last_report)),
                              "hdmi_frame_interval": interval_stats(hdmi.recent_times(last_report)),
                              "input_motion_px": last_flow,
                              "sent_correction_px": (last_correction if a.control == "on" else [0, 0]),
                              "output_residual_motion_px": (
                                  np.median(np.asarray(output_track.moves), axis=0).round(3).tolist()
                                  if output_track.moves else None),
                              "input_background_path_variance_px2": input_track.variance(),
                              "output_background_path_variance_px2": output_track.variance(),
                              "output_border_black_candidate_percent": (
                                  border_black_percent(hdmi_frame) if hdmi_frame is not None else None),
                              "valid_estimates": accepted,
                              "invalid_estimates": rejected + input_track.invalid,
                              "invalid_ratio": round((rejected+input_track.invalid) /
                                                     max(accepted+rejected+input_track.invalid, 1), 4),
                              "uart_ack": ack, "uart_nack": nack,
                              "uart_other_error": uart_other_error, "last_uart": last_uart,
                              "last_acked_sequence": ((sequence-1) & 0xFFFF) if ack else None,
                              "fpga_active_param_version": None,
                              "fpga_counter_window": matching_probe_window(probe, start_wall)}
                    emit(record)
                    obs_window_start, hdmi_window_start = obs_count, hdmi_count
                    output_track.moves.clear()
                    last_report = now
            left = (resize_for_fpga(obs_frame, FRAME_WIDTH, FRAME_HEIGHT).copy() if obs_frame is not None else
                    np.zeros((FRAME_HEIGHT, FRAME_WIDTH, 3), dtype=np.uint8))
            right = (resize_for_fpga(hdmi_frame, FRAME_WIDTH, FRAME_HEIGHT).copy() if hdmi_frame is not None else
                     np.zeros((FRAME_HEIGHT, FRAME_WIDTH, 3), dtype=np.uint8))
            preview_text(left, [f"OBS frames {obs_count}", f"Input dx/dy {last_flow}",
                                "MEASURING" if active else "SPACE to start"])
            preview_text(right, [f"HDMI frames {hdmi_count}", f"Correction {last_correction}",
                                 f"UART {last_uart}"])
            cv2.imshow(window, cv2.resize(np.hstack((left, right)), (1600, 450)))
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                if active:
                    emit(summary(time.monotonic()))
                break
            if key == 32:
                if active:
                    emit(summary(time.monotonic()))
                    active = False
                    last_flow = last_correction = None
                    last_uart = "idle"
                    print("Measurement stopped; preview continues. SPACE starts another session.", flush=True)
                elif (obs_frame is None or hdmi_frame is None or
                      now-obs_ts >= 2 or now-hdmi_ts >= 2):
                    print("Both video streams must have fresh frames before starting.", flush=True)
                elif hdmi_frame.shape[:2] != (FRAME_HEIGHT, FRAME_WIDTH):
                    print("HDMI capture must be 1280x720 before starting.", flush=True)
                elif not uart_enabled:
                    print("UART failed earlier; restart the script before another session.", flush=True)
                else:
                    # Establish a known translation state before measuring either branch.
                    reset_request = make_stage13_request(
                        sequence, [v for row in IDENTITY_ROWS for v in row],
                        0, 0.0, 0.0, enabled=(a.control == "on"))
                    try:
                        if port.write(reset_request) != len(reset_request):
                            raise OSError("short UART write")
                        port.flush()
                        read_ack(port, sequence, reset_request)
                    except (OSError, ValueError, TimeoutError, serial.SerialException) as exc:
                        uart_enabled = False
                        print(f"Could not establish initial FPGA translation state: {exc}", flush=True)
                        continue
                    reset_sequence = sequence
                    sequence = (sequence + 1) & 0xFFFF
                    time.sleep(0.5)
                    now = time.monotonic()
                    _, _, obs_count, _ = obs.latest()
                    _, _, hdmi_count, _ = hdmi.latest()
                    session += 1
                    active = True
                    start_wall = datetime.now(timezone.utc)
                    start_mono = last_report = now
                    last_input_sample = last_output_sample = 0.0
                    previous_obs, previous_hdmi = obs_count, hdmi_count
                    session_obs_start, session_hdmi_start = obs_count, hdmi_count
                    obs_window_start, hdmi_window_start = obs_count, hdmi_count
                    input_track, output_track = MotionTrack(), MotionTrack()
                    compensator = ShakeOnlyCompensator(a.alpha, a.max_correction)
                    accepted = rejected = nack = uart_other_error = 0
                    ack = 1
                    last_flow = last_correction = None
                    last_uart = f"ACK initial seq={reset_sequence}"
                    print(f"Measurement {session} started: {a.mode}/{a.control}", flush=True)
    except KeyboardInterrupt:
        if active:
            emit(summary(time.monotonic()))
    finally:
        if obs is not None:
            obs.close()
        if hdmi is not None:
            hdmi.close()
        if port is not None:
            port.close()
        cv2.destroyAllWindows()


def matching_probe_window(probe: ProbeSnapshots, start_wall: datetime | None):
    window = probe.latest_window
    if window is None or start_wall is None or "end_time" not in window:
        return None
    end = datetime.fromisoformat(window["end_time"])
    if end.timestamp()-window["seconds"] < start_wall.timestamp():
        return None
    return window


if __name__ == "__main__":
    main()
