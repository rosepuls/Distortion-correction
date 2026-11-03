"""Preview a USB HDMI capture device with OpenCV on Windows."""

from __future__ import annotations

import argparse
import ctypes
import sys
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.device_config import load_device_config


def parse_args() -> argparse.Namespace:
    devices = load_device_config()
    parser = argparse.ArgumentParser(
        description="Show live video from an HDMI-to-USB capture device. Press q or Esc to quit."
    )
    parser.add_argument(
        "--source",
        type=int,
        default=devices["hdmi_capture_index"],
        help="DirectShow camera index from host/verification/device_config.json",
    )
    parser.add_argument("--width", type=int, default=devices["width"], help="Requested capture width")
    parser.add_argument("--height", type=int, default=devices["height"], help="Requested capture height")
    return parser.parse_args()


def show_window_on_screen(title: str) -> None:
    """Restore a HighGUI window if Windows inherited a minimized position."""
    if sys.platform != "win32":
        return
    user32 = ctypes.windll.user32
    user32.FindWindowW.argtypes = (ctypes.c_wchar_p, ctypes.c_wchar_p)
    user32.FindWindowW.restype = ctypes.c_void_p
    user32.ShowWindow.argtypes = (ctypes.c_void_p, ctypes.c_int)
    user32.SetForegroundWindow.argtypes = (ctypes.c_void_p,)
    hwnd = user32.FindWindowW(None, title)
    if hwnd:
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        user32.SetForegroundWindow(hwnd)


def main() -> int:
    args = parse_args()
    capture = cv2.VideoCapture(args.source, cv2.CAP_DSHOW)
    if not capture.isOpened():
        print(f"Could not open DirectShow camera index {args.source}.", file=sys.stderr)
        print("List video devices with: ffmpeg -list_devices true -f dshow -i dummy", file=sys.stderr)
        return 1

    capture.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    actual_width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(
        f"Opened camera index {args.source}; reported capture size: "
        f"{actual_width}x{actual_height}. Press q or Esc to quit."
    )

    window = "HDMI to USB Capture Preview"
    cv2.namedWindow(window, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(window, 960, 540)
    cv2.moveWindow(window, 80, 80)
    window_shown = False
    try:
        while True:
            ok, frame = capture.read()
            if not ok or frame is None:
                print("Frame capture failed; stopping preview.", file=sys.stderr)
                return 2

            frame_height, frame_width = frame.shape[:2]
            label = f"Resolution: {frame_width} x {frame_height}"
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.7
            thickness = 2
            label_width = cv2.getTextSize(label, font, font_scale, thickness)[0][0]
            cv2.rectangle(frame, (8, 8), (min(frame_width - 1, label_width + 24), 48),
                          (0, 0, 0), -1)
            cv2.putText(frame, label, (16, 35), font, font_scale,
                        (0, 255, 255), thickness, cv2.LINE_AA)

            cv2.imshow(window, frame)
            if not window_shown:
                show_window_on_screen(window)
                window_shown = True
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
    finally:
        capture.release()
        cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
