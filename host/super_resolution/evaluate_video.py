"""Compare 3:2 upscalers on paired video frames and write per-frame metrics."""

from __future__ import annotations

import argparse
import csv
import time
from pathlib import Path

import cv2
import numpy as np
import torch

from metrics import psnr, ssim_global, temporal_error
from model import ResidualSR32


def luma(bgr: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)[:, :, 0]


def adaptive_sharpen(lr: np.ndarray) -> np.ndarray:
    h, w = lr.shape[:2]
    dx = (np.arange(w * 3 // 2, dtype=np.float32) + 0.5) * (2.0 / 3.0) - 0.5
    dy = (np.arange(h * 3 // 2, dtype=np.float32) + 0.5) * (2.0 / 3.0) - 0.5
    x0 = np.floor(dx).astype(np.int32).clip(0, w - 1)
    y0 = np.floor(dy).astype(np.int32).clip(0, h - 1)
    x1, y1 = (x0 + 1).clip(0, w - 1), (y0 + 1).clip(0, h - 1)
    fx = (dx - np.floor(dx))[None, :, None]
    fy = (dy - np.floor(dy))[:, None, None]
    a, b = lr[y0[:, None], x0[None, :]].astype(np.float32), lr[y0[:, None], x1[None, :]].astype(np.float32)
    c, d = lr[y1[:, None], x0[None, :]].astype(np.float32), lr[y1[:, None], x1[None, :]].astype(np.float32)
    bilinear = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    mean = (a + b + c + d) * 0.25
    low = np.minimum(np.minimum(a, b), np.minimum(c, d))
    high = np.maximum(np.maximum(a, b), np.maximum(c, d))
    sharp = np.clip(bilinear + (bilinear - mean) * 0.25, low, high)
    sharp = np.where(high - low >= 12, sharp, bilinear)
    return np.clip(np.rint(sharp), 0, 255).astype(np.uint8)


def cnn_upscale(lr: np.ndarray, model: ResidualSR32, device: str) -> np.ndarray:
    ycc = cv2.cvtColor(lr, cv2.COLOR_BGR2YCrCb)
    y = torch.from_numpy(ycc[:, :, 0].copy()).float()[None, None].to(device)
    with torch.no_grad():
        out_y = model(y).squeeze().cpu().numpy()
    out_cr = cv2.resize(ycc[:, :, 1], (1920, 1080), interpolation=cv2.INTER_LINEAR)
    out_cb = cv2.resize(ycc[:, :, 2], (1920, 1080), interpolation=cv2.INTER_LINEAR)
    merged = cv2.merge((np.clip(np.rint(out_y), 0, 255).astype(np.uint8), out_cr, out_cb))
    return cv2.cvtColor(merged, cv2.COLOR_YCrCb2BGR)


def run(lr_dir: Path, hr_dir: Path, output_csv: Path,
        checkpoint: Path | None = None, device: str = "cpu",
        selected_methods: list[str] | None = None) -> int:
    lr_paths = sorted([*lr_dir.glob("*.png"), *lr_dir.glob("*.jpg")])
    hr_paths = sorted([*hr_dir.glob("*.png"), *hr_dir.glob("*.jpg")])
    if not lr_paths or [p.name for p in lr_paths] != [p.name for p in hr_paths]:
        raise RuntimeError("LR/HR directories must contain matching PNG frame names")
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    model = None
    if checkpoint:
        saved = torch.load(checkpoint, map_location="cpu", weights_only=False)
        model = ResidualSR32()
        model.load_state_dict(saved["state_dict"])
        model.eval().to(device)
    names = list(dict.fromkeys(selected_methods or ["bilinear", "adaptive_sharpener", "bicubic", "lanczos4"]))
    if model is not None and "cnn" not in names:
        names.append("cnn")
    if "cnn" in names and model is None:
        raise ValueError("CNN evaluation requires --checkpoint")
    previous: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    rows = []
    for index, (lp, hp) in enumerate(zip(lr_paths, hr_paths)):
        lr, hr = cv2.imread(str(lp)), cv2.imread(str(hp))
        if lr is None or hr is None or lr.shape[:2] != (720, 1280) or hr.shape[:2] != (1080, 1920):
            raise RuntimeError(f"invalid frame pair at {lp.name}")
        outputs = {}
        runtimes = {}
        for name in names:
            start = time.perf_counter()
            if name == "bilinear":
                image = cv2.resize(lr, (1920, 1080), interpolation=cv2.INTER_LINEAR)
            elif name == "adaptive_sharpener":
                image = adaptive_sharpen(lr)
            elif name == "bicubic":
                image = cv2.resize(lr, (1920, 1080), interpolation=cv2.INTER_CUBIC)
            elif name == "lanczos4":
                image = cv2.resize(lr, (1920, 1080), interpolation=cv2.INTER_LANCZOS4)
            else:
                image = cnn_upscale(lr, model, device)
            outputs[name] = image
            runtimes[name] = (time.perf_counter() - start) * 1000.0
        y_ref = luma(hr)
        for name in names:
            y_out = luma(outputs[name])
            row = {"frame": lp.name, "method": name,
                   "y_psnr": psnr(y_ref, y_out), "y_ssim_global": ssim_global(y_ref, y_out),
                   "runtime_ms": runtimes[name]}
            if name in previous:
                old_ref, old_out = previous[name]
                row["temporal_error"] = temporal_error(old_ref, y_ref, old_out, y_out)
            else:
                row["temporal_error"] = ""
            previous[name] = (y_ref, y_out)
            rows.append(row)
    with output_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} frame-method rows to {output_csv}")
    return len(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lr_dir", type=Path)
    parser.add_argument("hr_dir", type=Path)
    parser.add_argument("output_csv", type=Path)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--methods", nargs="+", choices=[
        "bilinear", "adaptive_sharpener", "bicubic", "lanczos4", "cnn"
    ])
    args = parser.parse_args()
    run(args.lr_dir, args.hr_dir, args.output_csv, args.checkpoint,
        args.device, args.methods)


if __name__ == "__main__":
    main()
