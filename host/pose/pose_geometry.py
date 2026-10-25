"""Shared chessboard pose estimation helpers for the host-side tools."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

import cv2 as cv
import numpy as np

CALIBRATION_SCHEMA = "pango-camera-calibration-v1"
REFERENCE_SCHEMA = "pango-pose-reference-v1"


def load_calibration(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"Cannot read calibration JSON {path}: {exc}") from exc
    if data.get("schema") != CALIBRATION_SCHEMA:
        raise ValueError(f"Unsupported calibration schema in {path}")
    try:
        width, height = (int(value) for value in data["image_size"])
        cols, rows = (int(value) for value in data["chessboard"]["inner_corners"])
        square_mm = float(data["chessboard"]["square_edge_mm"])
        camera_matrix = np.asarray(data["camera_matrix"], dtype=np.float64)
        distortion = np.asarray(data["distortion_coefficients"], dtype=np.float64).reshape(-1, 1)
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"Calibration JSON is missing valid camera/board fields: {exc}") from exc
    if width < 1 or height < 1 or cols < 2 or rows < 2 or not math.isfinite(square_mm) or square_mm <= 0:
        raise ValueError("Calibration image size and chessboard dimensions must be positive")
    if camera_matrix.shape != (3, 3) or not np.isfinite(camera_matrix).all():
        raise ValueError("camera_matrix must be a finite 3x3 matrix")
    if distortion.size < 4 or not np.isfinite(distortion).all():
        raise ValueError("distortion_coefficients must contain finite k1, k2, p1, p2 values")
    data["_image_size"] = (width, height)
    data["_board_size"] = (cols, rows)
    data["_square_mm"] = square_mm
    data["_camera_matrix"] = camera_matrix
    data["_distortion"] = distortion
    data["_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return data


def read_image(path: Path) -> np.ndarray:
    encoded = np.fromfile(str(path), dtype=np.uint8)
    image = cv.imdecode(encoded, cv.IMREAD_COLOR) if encoded.size else None
    if image is None:
        raise ValueError(f"Could not decode image: {path}")
    return image


def chessboard_object_points(calibration: dict[str, Any]) -> np.ndarray:
    cols, rows = calibration["_board_size"]
    points = np.zeros((cols * rows, 3), dtype=np.float32)
    points[:, :2] = np.mgrid[0:cols, 0:rows].T.reshape(-1, 2) * calibration["_square_mm"]
    return points


def detect_chessboard(image: np.ndarray, calibration: dict[str, Any]) -> np.ndarray | None:
    cols, rows = calibration["_board_size"]
    gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY)
    if hasattr(cv, "findChessboardCornersSB"):
        found, corners = cv.findChessboardCornersSB(gray, (cols, rows))
    else:
        flags = cv.CALIB_CB_ADAPTIVE_THRESH + cv.CALIB_CB_NORMALIZE_IMAGE
        found, corners = cv.findChessboardCorners(gray, (cols, rows), flags)
        if found:
            criteria = (cv.TERM_CRITERIA_EPS + cv.TERM_CRITERIA_MAX_ITER, 40, 0.001)
            corners = cv.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
    return corners if found else None


def estimate_board_pose(
    image: np.ndarray, calibration: dict[str, Any]
) -> tuple[np.ndarray, np.ndarray, np.ndarray] | None:
    corners = detect_chessboard(image, calibration)
    if corners is None:
        return None
    success, rotation_vector, translation = cv.solvePnP(
        chessboard_object_points(calibration), corners,
        calibration["_camera_matrix"], calibration["_distortion"],
        flags=cv.SOLVEPNP_ITERATIVE,
    )
    if not success:
        return None
    rotation, _ = cv.Rodrigues(rotation_vector)
    return corners, rotation, translation.reshape(3)


def relative_pose(
    reference_rotation: np.ndarray,
    reference_translation: np.ndarray,
    current_rotation: np.ndarray,
    current_translation: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    """Return the reference-camera to current-camera rigid transform."""
    rotation = current_rotation @ reference_rotation.T
    translation = current_translation - rotation @ reference_translation
    return rotation, translation


def euler_xyz_degrees(rotation: np.ndarray) -> dict[str, float]:
    """Extract roll-X, pitch-Y, yaw-Z for R = Rz(yaw) Ry(pitch) Rx(roll)."""
    sy = math.hypot(float(rotation[0, 0]), float(rotation[1, 0]))
    if sy > 1e-8:
        roll = math.atan2(float(rotation[2, 1]), float(rotation[2, 2]))
        pitch = math.atan2(-float(rotation[2, 0]), sy)
        yaw = math.atan2(float(rotation[1, 0]), float(rotation[0, 0]))
    else:
        roll = math.atan2(-float(rotation[1, 2]), float(rotation[1, 1]))
        pitch = math.atan2(-float(rotation[2, 0]), sy)
        yaw = 0.0
    return {
        "roll_x_deg": math.degrees(roll),
        "pitch_y_deg": math.degrees(pitch),
        "yaw_z_deg": math.degrees(yaw),
    }


def validate_image_size(image: np.ndarray, calibration: dict[str, Any], label: str) -> None:
    expected_width, expected_height = calibration["_image_size"]
    height, width = image.shape[:2]
    if (width, height) != (expected_width, expected_height):
        raise ValueError(
            f"{label} is {width}x{height}; calibration requires {expected_width}x{expected_height}"
        )

