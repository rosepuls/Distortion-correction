"""Save one OBS input frame and one FPGA HDMI output frame after a profile ACK."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time

import cv2
import numpy as np

from device_config import load_device_config


HERE = Path(__file__).resolve().parent


def parse_args():
    devices = load_device_config()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sequence", type=int, required=True)
    parser.add_argument("--profile-id", type=int, required=True)
    parser.add_argument("--obs-source", type=int, default=devices["obs_virtual_camera_index"])
    parser.add_argument("--hdmi-source", type=int, default=devices["hdmi_capture_index"])
    parser.add_argument("--width", type=int, default=devices["width"])
    parser.add_argument("--height", type=int, default=devices["height"])
    parser.add_argument("--warmup-frames", type=int, default=15)
    parser.add_argument("--check-only", action="store_true",
                        help="verify both video sources before changing the FPGA profile")
    parser.add_argument("--out", type=Path, default=HERE / "enhancement_profiles")
    args = parser.parse_args()
    if not 0 <= args.sequence <= 65535 or not 0 <= args.profile_id <= 5:
        parser.error("sequence must be 0..65535 and profile-id must be 0..5")
    if args.obs_source < 0 or args.hdmi_source < 0 or args.obs_source == args.hdmi_source:
        parser.error("OBS and HDMI must have distinct nonnegative DirectShow indices")
    if args.width < 1 or args.height < 1 or args.warmup_frames < 1:
        parser.error("width, height, and warmup-frames must be positive")
    return args


def capture_one(name: str, index: int, width: int, height: int, warmup: int):
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise RuntimeError(f"{name}: cannot open DirectShow index {index}; "
                           "close the HDMI preview or other app using this device")
    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        frame = None
        for _ in range(warmup):
            ok, frame = cap.read()
            if not ok or frame is None:
                raise RuntimeError(f"{name}: frame read failed at DirectShow index {index}")
        return frame, time.monotonic()
    finally:
        cap.release()


def save_png(path: Path, frame: np.ndarray):
    ok, encoded = cv2.imencode(".png", frame)
    if not ok:
        raise RuntimeError(f"PNG encoding failed: {path}")
    encoded.tofile(str(path))


def main():
    args = parse_args()
    with ThreadPoolExecutor(max_workers=2) as pool:
        obs_future = pool.submit(capture_one, "OBS", args.obs_source, args.width,
                                 args.height, args.warmup_frames)
        hdmi_future = pool.submit(capture_one, "HDMI", args.hdmi_source, args.width,
                                  args.height, args.warmup_frames)
        obs_frame, obs_time = obs_future.result()
        hdmi_frame, hdmi_time = hdmi_future.result()

    if args.check_only:
        print(f"Video sources ready: OBS={args.obs_source}, HDMI={args.hdmi_source}")
        return

    stamp = datetime.now(timezone.utc)
    stem = f"profile_{args.profile_id}_seq_{args.sequence}_{stamp.strftime('%Y%m%d_%H%M%S_%f')}"
    args.out.mkdir(parents=True, exist_ok=True)
    obs_path = args.out / f"{stem}_obs.png"
    hdmi_path = args.out / f"{stem}_hdmi.png"
    save_png(obs_path, obs_frame)
    save_png(hdmi_path, hdmi_frame)
    record = {
        "time": stamp.isoformat(), "sequence": args.sequence, "profile_id": args.profile_id,
        "obs_source": args.obs_source, "hdmi_source": args.hdmi_source,
        "obs_size": [obs_frame.shape[1], obs_frame.shape[0]],
        "hdmi_size": [hdmi_frame.shape[1], hdmi_frame.shape[0]],
        "capture_skew_ms": round(abs(obs_time - hdmi_time) * 1000, 1),
        "obs_png": str(obs_path.resolve()), "hdmi_png": str(hdmi_path.resolve()),
    }
    log_path = args.out / "captures.jsonl"
    with log_path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"OBS input PNG: {obs_path.resolve()}")
    print(f"FPGA HDMI output PNG: {hdmi_path.resolve()}")
    print(f"Capture record: {log_path.resolve()}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, cv2.error) as exc:
        print(f"Capture failed: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc
