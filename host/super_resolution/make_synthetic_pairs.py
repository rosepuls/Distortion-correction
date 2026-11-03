"""Generate moving high-frequency charts with known 1080p/720p pairs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def make_frame(index: int, count: int, width: int = 1920, height: int = 1080) -> np.ndarray:
    yy, xx = np.mgrid[0:height, 0:width]
    t = 2.0 * np.pi * index / count
    shift = 8.0 * np.sin(t)
    image = np.full((height, width, 3), 28, np.uint8)
    # Moving, phase-shifted fine gratings expose detail recovery and shimmer.
    for k, period in enumerate((3.0, 4.0, 5.0, 7.0, 11.0)):
        x0, y0 = 80 + k * 360, 110 + (k % 2) * 400
        xx0, yy0 = xx - x0 - shift, yy - y0
        mask = (np.abs(xx0) < 230) & (np.abs(yy0) < 150)
        bars = ((np.floor((xx0 + 230) / period) % 2) == 0)
        value = np.where(bars, 235, 35).astype(np.uint8)
        for channel in range(3):
            image[:, :, channel] = np.where(mask, value, image[:, :, channel])
    # Moving slanted edges and a high-frequency checker block.
    edge_x = 920 + 140 * np.sin(t)
    image[:, :] = np.where((xx > edge_x + (yy - 540) * 0.12)[..., None],
                           np.array([225, 225, 225], np.uint8), image)
    checker = (((xx // 6 + yy // 6 + index // 2) % 2) * 190 + 30).astype(np.uint8)
    mask = (xx > 1450) & (yy > 650)
    image = np.where(mask[..., None], checker[..., None], image)
    cv2.putText(image, f"MOTION SR {index:03d}", (60, 1030),
                cv2.FONT_HERSHEY_SIMPLEX, 1.5, (30, 230, 230), 3, cv2.LINE_AA)
    # Subpixel motion followed by camera-like blur and area sampling.
    matrix = np.float32([[1, 0, shift], [0, 1, 0.35 * np.sin(t)]])
    image = cv2.warpAffine(image, matrix, (width, height), flags=cv2.INTER_CUBIC,
                           borderMode=cv2.BORDER_REFLECT101)
    return image


def generate(output: Path, frames: int) -> None:
    lr_dir, hr_dir = output / "lr720", output / "hr1080"
    lr_dir.mkdir(parents=True, exist_ok=True)
    hr_dir.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        hr = make_frame(i, frames)
        camera = cv2.GaussianBlur(hr, (0, 0), 0.55)
        lr = cv2.resize(camera, (1280, 720), interpolation=cv2.INTER_AREA)
        noise = np.random.default_rng(6000 + i).normal(0, 0.7, lr.shape)
        lr = np.clip(lr.astype(np.float32) + noise, 0, 255).astype(np.uint8)
        name = f"{i:08d}.png"
        cv2.imwrite(str(hr_dir / name), hr)
        cv2.imwrite(str(lr_dir / name), lr)
    (output / "metadata.json").write_text(json.dumps({
        "generator": "make_synthetic_pairs.py", "frame_count": frames,
        "lr_size": [1280, 720], "hr_size": [1920, 1080],
        "fps": 30, "purpose": "pipeline smoke data only; not natural-scene validation",
    }, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frames", type=int, default=24)
    args = parser.parse_args()
    if args.frames < 4:
        parser.error("at least four frames are required")
    generate(args.output, args.frames)
    print(f"generated {args.frames} paired frames in {args.output}")


if __name__ == "__main__":
    main()
