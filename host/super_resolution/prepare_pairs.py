"""Prepare clip-separated 1080p reference / 720p degraded frame pairs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def prepare_video(source: Path, output: Path, stride: int, blur_sigma: float,
                  noise_sigma: float, jpeg_quality: int,
                  start_sec: float = 0.0, duration_sec: float | None = None) -> int:
    cap = cv2.VideoCapture(str(source))
    if not cap.isOpened():
        raise RuntimeError(f"cannot open video: {source}")
    output.mkdir(parents=True, exist_ok=True)
    lr_dir = output / "lr720"
    hr_dir = output / "hr1080"
    lr_dir.mkdir(exist_ok=True)
    hr_dir.mkdir(exist_ok=True)
    source_fps = cap.get(cv2.CAP_PROP_FPS)
    source_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    source_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    start_frame = max(0, int(round(start_sec * source_fps)))
    end_frame = (int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) if duration_sec is None else
                 min(int(cap.get(cv2.CAP_PROP_FRAME_COUNT)),
                     int(round((start_sec + duration_sec) * source_fps))))
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    count = 0
    frame_index = start_frame
    rng = np.random.default_rng(20261030)
    while True:
        if frame_index >= end_frame:
            break
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % stride == 0:
            hr = cv2.resize(frame, (1920, 1080), interpolation=cv2.INTER_AREA)
            degraded = hr
            if blur_sigma > 0:
                degraded = cv2.GaussianBlur(degraded, (0, 0), blur_sigma)
            lr = cv2.resize(degraded, (1280, 720), interpolation=cv2.INTER_AREA)
            if noise_sigma > 0:
                noise = rng.normal(0.0, noise_sigma, lr.shape)
                lr = np.clip(lr.astype(np.float32) + noise, 0, 255).astype(np.uint8)
            if jpeg_quality < 100:
                ok, encoded = cv2.imencode(
                    ".jpg", lr, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality]
                )
                if not ok:
                    raise RuntimeError("JPEG degradation encoding failed")
                lr = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
            name = f"{count:08d}.png"
            cv2.imwrite(str(hr_dir / name), hr)
            cv2.imwrite(str(lr_dir / name), lr)
            count += 1
        frame_index += 1
    cap.release()
    metadata = {
        "source": str(source.resolve()), "source_size": [source_width, source_height],
        "source_fps": source_fps, "input_size": [1280, 720],
        "target_size": [1920, 1080], "frame_stride": stride,
        "start_sec": start_sec, "duration_sec": duration_sec,
        "blur_sigma": blur_sigma, "noise_sigma": noise_sigma,
        "jpeg_quality": jpeg_quality, "color_order": "BGR",
        "frame_count": count,
    }
    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8"
    )
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--stride", type=int, default=1)
    parser.add_argument("--blur-sigma", type=float, default=0.55)
    parser.add_argument("--noise-sigma", type=float, default=1.0)
    parser.add_argument("--jpeg-quality", type=int, default=95)
    parser.add_argument("--start-sec", type=float, default=0.0)
    parser.add_argument("--duration-sec", type=float)
    args = parser.parse_args()
    if args.stride < 1 or args.blur_sigma < 0 or args.noise_sigma < 0 or args.start_sec < 0:
        parser.error("stride must be positive; blur/noise must be nonnegative")
    if args.duration_sec is not None and args.duration_sec <= 0:
        parser.error("duration-sec must be positive")
    if not 1 <= args.jpeg_quality <= 100:
        parser.error("jpeg-quality must be in [1, 100]")
    n = prepare_video(args.video, args.output, args.stride, args.blur_sigma,
                      args.noise_sigma, args.jpeg_quality,
                      args.start_sec, args.duration_sec)
    print(f"prepared {n} paired frames in {args.output}")


if __name__ == "__main__":
    main()
