"""Create per-frame RGB comparison panels and a video from saved RTL output."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np


WIDTH = 1280
HEIGHT = 720
LABEL_HEIGHT = 24
DIFFERENCE_GAIN = 8


def load_mem(path: Path) -> np.ndarray:
    words = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    expected = WIDTH * HEIGHT
    if len(words) != expected:
        raise ValueError(f"{path} has {len(words)} words; expected {expected}")
    values = np.fromiter((int(word, 16) for word in words), dtype=np.uint32, count=expected)
    red = ((values >> 16) & 0xFF).astype(np.uint8)
    green = ((values >> 8) & 0xFF).astype(np.uint8)
    blue = (values & 0xFF).astype(np.uint8)
    return np.stack((blue, green, red), axis=1).reshape((HEIGHT, WIDTH, 3))


def labeled_tile(label: str, image: np.ndarray) -> np.ndarray:
    tile = np.zeros((HEIGHT + LABEL_HEIGHT, WIDTH, 3), dtype=np.uint8)
    tile[LABEL_HEIGHT:] = image
    cv2.putText(tile, label, (6, 17), cv2.FONT_HERSHEY_SIMPLEX, 0.55,
                (255, 255, 255), 1, cv2.LINE_AA)
    return tile


def create_panel(input_image: np.ndarray, golden: np.ndarray, rtl: np.ndarray, frame_index: int) -> np.ndarray:
    difference = cv2.absdiff(golden, rtl)
    difference = np.minimum(difference.astype(np.uint16) * DIFFERENCE_GAIN, 255).astype(np.uint8)
    top = np.concatenate((
        labeled_tile("INPUT", input_image),
        labeled_tile("PYTHON GOLDEN", golden),
    ), axis=1)
    bottom = np.concatenate((
        labeled_tile("RTL FULL CHAIN", rtl),
        labeled_tile(f"ABS DIFF x{DIFFERENCE_GAIN}", difference),
    ), axis=1)
    panel = np.concatenate((top, bottom), axis=0)
    cv2.putText(panel, f"frame {frame_index:02d}", (12, panel.shape[0] - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
    return panel


def create_comparison_video(asset_directory: Path, output_directory: Path, frame_count: int) -> tuple[int, Path, list[Path]]:
    output_directory.mkdir(parents=True, exist_ok=True)
    panels: list[Path] = []
    mismatch_pixels = 0
    video_writer = None
    video_path = output_directory / "realtime_video_comparison_720p30.mp4"

    for frame_index in range(frame_count):
        input_path = asset_directory / f"input_frame_{frame_index:02d}.mem"
        golden_path = asset_directory / f"golden_frame_{frame_index:02d}.mem"
        rtl_path = asset_directory / f"rtl_frame_{frame_index:02d}.mem"
        for path in (input_path, golden_path, rtl_path):
            if not path.exists():
                raise FileNotFoundError(f"missing comparison input: {path}")

        input_image = load_mem(input_path)
        golden = load_mem(golden_path)
        rtl = load_mem(rtl_path)
        mismatch_pixels += int(np.any(golden != rtl, axis=2).sum())
        panel = create_panel(input_image, golden, rtl, frame_index)
        panel_path = output_directory / f"comparison_frame_{frame_index:02d}.png"
        if not cv2.imwrite(str(panel_path), panel):
            raise IOError(f"failed to write panel: {panel_path}")
        panels.append(panel_path)

        if video_writer is None:
            height, width = panel.shape[:2]
            video_writer = cv2.VideoWriter(
                str(video_path),
                cv2.VideoWriter_fourcc(*"mp4v"),
                30.0,
                (width, height),
            )
            if not video_writer.isOpened():
                raise RuntimeError("OpenCV could not open an MP4 video writer")
        video_writer.write(panel)

    if video_writer is not None:
        video_writer.release()
    return mismatch_pixels, video_path, panels


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--frame-count", type=int, default=30)
    arguments = parser.parse_args()
    mismatch_pixels, video_path, panels = create_comparison_video(
        arguments.asset_directory,
        arguments.output_directory,
        arguments.frame_count,
    )
    print(f"Created comparison panels: {len(panels)}")
    print(f"Created comparison video: {video_path}")
    if mismatch_pixels:
        print(f"FAIL: RTL vs golden mismatch pixels={mismatch_pixels}")
        return 1
    print("PASS: RTL vs golden comparison has zero differing pixels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
