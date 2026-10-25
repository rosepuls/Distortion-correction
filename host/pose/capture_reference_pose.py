"""Estimate and save the camera's designated zero-pose from one raw frame."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import cv2 as cv

from pose_geometry import REFERENCE_SCHEMA, estimate_board_pose, load_calibration, read_image, validate_image_size


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calibration", type=Path, required=True, help="calibration.json from calibrate.py")
    parser.add_argument("--image", type=Path, required=True, help="raw UVC frame at the calibrated resolution")
    parser.add_argument("--out", type=Path, required=True, help="output zero-pose JSON")
    parser.add_argument("--display", action="store_true", help="show detected corners before saving")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        calibration = load_calibration(args.calibration)
        image = read_image(args.image)
        validate_image_size(image, calibration, "Reference image")
        pose = estimate_board_pose(image, calibration)
        if pose is None:
            raise ValueError("Chessboard was not detected or solvePnP failed")
        corners, rotation, translation = pose
        if args.display:
            cv.drawChessboardCorners(image, calibration["_board_size"], corners, True)
            cv.imshow("Zero-pose reference", image)
            cv.waitKey(0)
            cv.destroyAllWindows()
    except (OSError, ValueError, cv.error) as exc:
        raise SystemExit(str(exc)) from exc

    result = {
        "schema": REFERENCE_SCHEMA,
        "calibration_sha256": calibration["_sha256"],
        "calibration_image_size": list(calibration["_image_size"]),
        "reference_image": str(args.image.resolve()),
        "board_size_inner_corners": list(calibration["_board_size"]),
        "square_edge_mm": calibration["_square_mm"],
        "rotation_board_to_camera": rotation.tolist(),
        "translation_board_to_camera_mm": translation.tolist(),
        "coordinate_convention": "OpenCV camera axes; board XY on the printed plane; angles use Rz(yaw) Ry(pitch) Rx(roll)",
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved zero-pose reference: {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

