"""Planar output-to-source mapping from saved board-to-camera poses."""

from __future__ import annotations

import numpy as np


def _matrix(value: object, shape: tuple[int, ...], label: str) -> np.ndarray:
    matrix = np.asarray(value, dtype=np.float64)
    if matrix.shape != shape or not np.isfinite(matrix).all():
        raise ValueError(f"{label} must be a finite array with shape {shape}")
    return matrix


def homography_from_board_poses(
    camera_matrix: np.ndarray,
    reference_rotation: np.ndarray,
    reference_translation: np.ndarray,
    current_rotation: np.ndarray,
    current_translation: np.ndarray,
) -> np.ndarray:
    """Map ideal reference output pixels to ideal current source pixels.

    Board points have Z=0. Both poses map board coordinates into their
    respective camera frames, matching solvePnP and track_pose.py.
    """
    camera_matrix = _matrix(camera_matrix, (3, 3), "camera_matrix")
    reference_rotation = _matrix(reference_rotation, (3, 3), "reference_rotation")
    reference_translation = _matrix(reference_translation, (3,), "reference_translation")
    current_rotation = _matrix(current_rotation, (3, 3), "current_rotation")
    current_translation = _matrix(current_translation, (3,), "current_translation")

    reference_projection = camera_matrix @ np.column_stack(
        (reference_rotation[:, :2], reference_translation)
    )
    current_projection = camera_matrix @ np.column_stack(
        (current_rotation[:, :2], current_translation)
    )
    try:
        homography = current_projection @ np.linalg.inv(reference_projection)
    except np.linalg.LinAlgError as exc:
        raise ValueError("Reference plane projection is singular") from exc
    if not np.isfinite(homography).all():
        raise ValueError("Pose produces a non-finite planar homography")
    scale = float(homography[2, 2])
    if abs(scale) < 1e-12:
        scale = float(np.linalg.norm(homography))
    if not np.isfinite(scale) or abs(scale) < 1e-12:
        raise ValueError("Pose produces a degenerate planar homography")
    return homography / scale


def homography_from_relative_pose(
    camera_matrix: np.ndarray,
    reference_rotation: np.ndarray,
    reference_translation: np.ndarray,
    relative_rotation: np.ndarray,
    relative_translation: np.ndarray,
) -> np.ndarray:
    """Use track_pose.py's reference-camera to current-camera transform."""
    reference_rotation = _matrix(reference_rotation, (3, 3), "reference_rotation")
    reference_translation = _matrix(reference_translation, (3,), "reference_translation")
    relative_rotation = _matrix(relative_rotation, (3, 3), "relative_rotation")
    relative_translation = _matrix(relative_translation, (3,), "relative_translation")
    current_rotation = relative_rotation @ reference_rotation
    current_translation = relative_rotation @ reference_translation + relative_translation
    return homography_from_board_poses(
        camera_matrix,
        reference_rotation,
        reference_translation,
        current_rotation,
        current_translation,
    )
