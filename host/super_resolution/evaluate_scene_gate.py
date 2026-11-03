"""Evaluate frame-level CNN enable hysteresis using LR luminance texture."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from evaluate_video import luma
from metrics import psnr, ssim_global, temporal_error
from model import ResidualSR32


def texture_score(y: np.ndarray) -> float:
    y16 = y.astype(np.int16)
    dx = np.abs(np.diff(y16, axis=1)).mean()
    dy = np.abs(np.diff(y16, axis=0)).mean()
    return float((dx + dy) * 0.5)


def evaluate(root: Path, model: ResidualSR32, device: str,
             enable_threshold: float, disable_threshold: float,
             csv_path: Path) -> dict:
    lr_files = sorted((root / "lr720").glob("*.png"))
    hr_files = sorted((root / "hr1080").glob("*.png"))
    if not lr_files or [p.name for p in lr_files] != [p.name for p in hr_files]:
        raise RuntimeError(f"LR/HR mismatch in {root}")

    enabled = False
    prev: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    records = []
    for lp, hp in zip(lr_files, hr_files):
        lr, hr = cv2.imread(str(lp)), cv2.imread(str(hp))
        if lr is None or hr is None:
            raise RuntimeError(f"failed to read {lp.name}")
        y = luma(lr)
        score = texture_score(y)
        if not enabled and score >= enable_threshold:
            enabled = True
        elif enabled and score <= disable_threshold:
            enabled = False

        ycc = cv2.cvtColor(lr, cv2.COLOR_BGR2YCrCb)
        if enabled:
            x = torch.from_numpy(y.copy()).float()[None, None].to(device)
            with torch.no_grad():
                out_y = model(x).squeeze().cpu().numpy()
            out_y = np.clip(np.rint(out_y), 0, 255).astype(np.uint8)
        else:
            out_y = cv2.resize(y, (1920, 1080), interpolation=cv2.INTER_CUBIC)
        cr = cv2.resize(ycc[:, :, 1], (1920, 1080), interpolation=cv2.INTER_LINEAR)
        cb = cv2.resize(ycc[:, :, 2], (1920, 1080), interpolation=cv2.INTER_LINEAR)
        out = cv2.cvtColor(cv2.merge((out_y, cr, cb)), cv2.COLOR_YCrCb2BGR)
        ref_y, out_y_metric = luma(hr), luma(out)
        row = {"frame": lp.name, "texture_score": score, "cnn_enabled": int(enabled),
               "y_psnr": psnr(ref_y, out_y_metric),
               "y_ssim_global": ssim_global(ref_y, out_y_metric)}
        if "gate" in prev:
            old_ref, old_out = prev["gate"]
            row["temporal_error"] = temporal_error(old_ref, ref_y, old_out, out_y_metric)
        else:
            row["temporal_error"] = ""
        prev["gate"] = (ref_y, out_y_metric)
        records.append(row)

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=records[0].keys())
        writer.writeheader()
        writer.writerows(records)
    return {
        "frames": len(records),
        "enabled_fraction": float(np.mean([r["cnn_enabled"] for r in records])),
        "mean_texture": float(np.mean([r["texture_score"] for r in records])),
        "mean_y_psnr": float(np.mean([r["y_psnr"] for r in records])),
        "mean_temporal_error": float(np.mean([
            r["temporal_error"] for r in records if r["temporal_error"] != ""])),
        "mode_transitions": int(sum(records[i]["cnn_enabled"] != records[i-1]["cnn_enabled"]
                                     for i in range(1, len(records)))),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("checkpoint", type=Path)
    ap.add_argument("output_dir", type=Path)
    ap.add_argument("clips", type=Path, nargs="+")
    ap.add_argument("--enable-threshold", type=float, default=2.5)
    ap.add_argument("--disable-threshold", type=float, default=1.8)
    ap.add_argument("--device", default="cuda")
    args = ap.parse_args()
    if args.disable_threshold >= args.enable_threshold:
        ap.error("disable threshold must be lower than enable threshold")
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().to(args.device).eval()
    model.load_state_dict(saved["state_dict"])
    for root in args.clips:
        result = evaluate(root, model, args.device, args.enable_threshold,
                          args.disable_threshold,
                          args.output_dir / f"{root.name}.csv")
        print(root.name, result, flush=True)


if __name__ == "__main__":
    main()
