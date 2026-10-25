"""Track chessboard pose against a saved zero-pose and emit JSON Lines."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

import cv2 as cv
import numpy as np

from pose_geometry import (
    REFERENCE_SCHEMA,
    estimate_board_pose,
    euler_xyz_degrees,
    load_calibration,
    relative_pose,
    validate_image_size,
)


def parse_source(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", type=Path, required=True, help="calibration.json from calibrate.py")
    parser.add_argument("--reference", type=Path, required=True, help="zero-pose JSON from capture_reference_pose.py")
    parser.add_argument("--source", type=parse_source, default=0, help="UVC camera index (default 0) or video path")
    parser.add_argument("--output", type=Path, help="optional JSONL log; records are also printed to stdout")
    parser.add_argument("--display", action="store_true", help="show live image and detected corners")
    return parser.parse_args()


def load_reference(path: Path, calibration: dict) -> tuple:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") != REFERENCE_SCHEMA:
            raise ValueError("Unsupported zero-pose reference schema")
        if data.get("calibration_sha256") != calibration["_sha256"]:
            raise ValueError("Zero-pose reference was created with a different calibration file")
        if tuple(data.get("calibration_image_size", [])) != calibration["_image_size"]:
            raise ValueError("Zero-pose image size does not match the current calibration")
        reference_rotation = np.asarray(data["rotation_board_to_camera"], dtype=np.float64)
        reference_translation = np.asarray(data["translation_board_to_camera_mm"], dtype=np.float64).reshape(3)
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise ValueError(f"Cannot read zero-pose reference {path}: {exc}") from exc
    if reference_rotation.shape != (3, 3) or not np.isfinite(reference_rotation).all() or not np.isfinite(reference_translation).all():
        raise ValueError("Zero-pose reference contains invalid pose values")
    return reference_rotation, reference_translation


def invalid_record(frame_index: int, reason: str) -> dict:
    return {
        "timestamp_unix_ns": time.time_ns(),
        "frame_index": frame_index,
        "valid": False,
        "reason": reason,
    }


def main() -> int:
    args = parse_args()
    try:
        calibration = load_calibration(args.calibration)
        reference_rotation, reference_translation = load_reference(args.reference, calibration)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    capture = cv.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"Could not open video source: {args.source}")
    if isinstance(args.source, int):
        width, height = calibration["_image_size"]
        capture.set(cv.CAP_PROP_FRAME_WIDTH, width)
        capture.set(cv.CAP_PROP_FRAME_HEIGHT, height)

    output_stream = None
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        output_stream = args.output.open("a", encoding="utf-8", newline="\n")

    frame_index = 0
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            frame_index += 1
            try:
                validate_image_size(frame, calibration, "Video frame")
            except ValueError as exc:
                record = invalid_record(frame_index, str(exc))
                corners = None
            else:
                pose = estimate_board_pose(frame, calibration)
                if pose is None:
                    record = invalid_record(frame_index, "chessboard_not_detected_or_pose_failed")
                    corners = None
                else:
                    corners, current_rotation, current_translation = pose
                    delta_rotation, delta_translation = relative_pose(
                        reference_rotation, reference_translation, current_rotation, current_translation
                    )
                    record = {
                        "timestamp_unix_ns": time.time_ns(),
                        "frame_index": frame_index,
                        "valid": True,
                        "relative_rotation_matrix": delta_rotation.tolist(),
                        "relative_translation_mm": delta_translation.tolist(),
                        "euler_xyz_deg": euler_xyz_degrees(delta_rotation),
                        "board_to_camera_rotation": current_rotation.tolist(),
                        "board_to_camera_translation_mm": current_translation.tolist(),
                    }

            line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
            print(line, flush=True)
            if output_stream:
                output_stream.write(line + "\n")
                output_stream.flush()

            if args.display:
                if corners is not None:
                    cv.drawChessboardCorners(frame, calibration["_board_size"], corners, True)
                    angles = record["euler_xyz_deg"]
                    text = (
                        f"roll {angles['roll_x_deg']:+.1f}  "
                        f"pitch {angles['pitch_y_deg']:+.1f}  "
                        f"yaw {angles['yaw_z_deg']:+.1f} deg"
                    )
                else:
                    text = "Chessboard not detected"
                cv.putText(frame, text, (16, 32), cv.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv.imshow("Pose tracking", frame)
                if cv.waitKey(1) & 0xFF == ord("q"):
                    break
    except cv.error as exc:
        raise SystemExit(f"OpenCV pose tracking failed: {exc}") from exc
    finally:
        capture.release()
        if output_stream:
            output_stream.close()
        if args.display:
            cv.destroyAllWindows()

    return 0


if __name__ == "__main__":
    sys.exit(main())

