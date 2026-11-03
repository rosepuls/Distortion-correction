"""Show OBS virtual camera and FPGA HDMI capture side by side.

The labels report each captured frame's dimensions, not the preview window size.
Press q or Esc to exit. This script only previews video; it does not use UART.
"""

from __future__ import annotations

import argparse
import sys

import cv2
import numpy as np

from device_config import load_device_config


def parse_args() -> argparse.Namespace:
    devices = load_device_config()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--obs-source", type=int,
                        default=devices["obs_virtual_camera_index"],
                        help="OBS DirectShow index from device_config.json")
    parser.add_argument("--hdmi-source", type=int,
                        default=devices["hdmi_capture_index"],
                        help="HDMI capture DirectShow index from device_config.json")
    parser.add_argument("--width", type=int, default=devices["width"],
                        help="Requested width for both sources")
    parser.add_argument("--height", type=int, default=devices["height"],
                        help="Requested height for both sources")
    parser.add_argument("--hdmi-width", type=int,
                        help="Requested HDMI capture width (overrides --width)")
    parser.add_argument("--hdmi-height", type=int,
                        help="Requested HDMI capture height (overrides --height)")
    return parser.parse_args()


def open_camera(index: int, width: int, height: int) -> cv2.VideoCapture:
    capture = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    if not capture.isOpened():
        capture.release()
        raise RuntimeError(f"Cannot open DirectShow video device {index}")
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    return capture


def label_frame(frame: np.ndarray, name: str) -> np.ndarray:
    height, width = frame.shape[:2]
    label = f"{name}  {width} x {height}"
    canvas = frame.copy()
    font = cv2.FONT_HERSHEY_SIMPLEX
    scale = 0.75
    thickness = 2
    text_width, text_height = cv2.getTextSize(label, font, scale, thickness)[0]
    cv2.rectangle(canvas, (0, 0),
                  (min(width - 1, text_width + 24), min(height - 1, text_height + 24)),
                  (0, 0, 0), -1)
    cv2.putText(canvas, label, (12, min(height - 1, text_height + 12)),
                font, scale, (0, 255, 255), thickness, cv2.LINE_AA)
    return canvas


def same_height(left: np.ndarray, right: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Match display heights only when capture formats differ; keep aspect ratios."""
    left_height = left.shape[0]
    right_height = right.shape[0]
    if left_height == right_height:
        return left, right
    target = min(left_height, right_height)
    if left_height != target:
        left = cv2.resize(left, (round(left.shape[1] * target / left_height), target),
                          interpolation=cv2.INTER_AREA)
    if right_height != target:
        right = cv2.resize(right, (round(right.shape[1] * target / right_height), target),
                           interpolation=cv2.INTER_AREA)
    return left, right


def main() -> int:
    args = parse_args()
    if args.obs_source < 0 or args.hdmi_source < 0 or args.obs_source == args.hdmi_source:
        print("OBS and HDMI must use different nonnegative DirectShow indices.", file=sys.stderr)
        return 2
    if args.width < 1 or args.height < 1:
        print("Width and height must be positive.", file=sys.stderr)
        return 2
    hdmi_width = args.hdmi_width if args.hdmi_width is not None else args.width
    hdmi_height = args.hdmi_height if args.hdmi_height is not None else args.height
    if hdmi_width < 1 or hdmi_height < 1:
        print("HDMI width and height must be positive.", file=sys.stderr)
        return 2

    obs = None
    hdmi = None
    window = "OBS (left) | FPGA HDMI (right) - q/Esc to quit"
    try:
        obs = open_camera(args.obs_source, args.width, args.height)
        hdmi = open_camera(args.hdmi_source, hdmi_width, hdmi_height)
        print(f"Requested OBS {args.width}x{args.height} (index {args.obs_source}); "
              f"HDMI capture {hdmi_width}x{hdmi_height} (index {args.hdmi_source}). "
              "On-screen labels show delivered frame dimensions. Press q or Esc to quit.")
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window, 1600, 500)
        while True:
            obs_ok, obs_frame = obs.read()
            hdmi_ok, hdmi_frame = hdmi.read()
            if not obs_ok or obs_frame is None or not hdmi_ok or hdmi_frame is None:
                raise RuntimeError("Could not read a frame from OBS or HDMI capture")
            left = label_frame(obs_frame, "OBS virtual camera")
            right = label_frame(hdmi_frame, "FPGA HDMI capture")
            left, right = same_height(left, right)
            cv2.imshow(window, np.hstack((left, right)))
            if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                return 0
    except RuntimeError as exc:
        print(f"Preview stopped: {exc}", file=sys.stderr)
        print("Check that OBS Virtual Camera is running and the HDMI capture index is correct.",
              file=sys.stderr)
        return 1
    finally:
        if obs is not None:
            obs.release()
        if hdmi is not None:
            hdmi.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    raise SystemExit(main())
