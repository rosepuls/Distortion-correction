"""Inspect and update shared OBS, HDMI capture, and UART device settings."""

from __future__ import annotations

import argparse
import json

import cv2
from serial.tools import list_ports

from device_config import CONFIG_PATH, load_device_config


def inspect_video(index: int, preview: bool) -> None:
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print(f"DirectShow index {index}: unavailable")
        return
    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        frame = None
        for _ in range(5):
            ok, candidate = cap.read()
            if ok and candidate is not None:
                frame = candidate
        if frame is None:
            print(f"DirectShow index {index}: opened but no frame")
            return
        print(f"DirectShow index {index}: {frame.shape[1]}x{frame.shape[0]}")
        if preview:
            view = cv2.resize(frame, (960, 540))
            cv2.putText(view, f"DirectShow index {index}", (20, 45),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2, cv2.LINE_AA)
            cv2.imshow("Identify OBS and HDMI capture", view)
            cv2.waitKey(2000)
    finally:
        cap.release()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scan", action="store_true", help="probe DirectShow indices 0 through --max-index")
    parser.add_argument("--max-index", type=int, default=9,
                        help="highest DirectShow index to probe (default 9)")
    parser.add_argument("--preview", action="store_true",
                        help="show a 2-second image from each available scanned index")
    parser.add_argument("--set-hdmi", type=int, metavar="INDEX")
    parser.add_argument("--set-obs", type=int, metavar="INDEX")
    parser.add_argument("--set-com", metavar="COMx")
    args = parser.parse_args()
    if args.max_index < 0:
        parser.error("--max-index must be nonnegative")
    devices = load_device_config()
    if args.set_hdmi is not None:
        devices["hdmi_capture_index"] = args.set_hdmi
    if args.set_obs is not None:
        devices["obs_virtual_camera_index"] = args.set_obs
    if args.set_com is not None:
        devices["uart_port"] = args.set_com.upper()
    if args.set_hdmi is not None or args.set_obs is not None or args.set_com is not None:
        if (devices["obs_virtual_camera_index"] < 0 or devices["hdmi_capture_index"] < 0
                or devices["obs_virtual_camera_index"] == devices["hdmi_capture_index"]):
            parser.error("OBS and HDMI must use distinct nonnegative indices")
        if not devices["uart_port"].startswith("COM"):
            parser.error("UART port must look like COM7")
        CONFIG_PATH.write_text(json.dumps(devices, indent=2, ensure_ascii=False) + "\n",
                               encoding="utf-8")
    print(f"Shared config: {CONFIG_PATH}")
    print(json.dumps(devices, indent=2, ensure_ascii=False))
    print("Serial ports currently present:")
    for port in list_ports.comports():
        print(f"  {port.device}: {port.description}")
    if args.scan:
        for index in range(args.max_index + 1):
            inspect_video(index, args.preview)
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
