"""Measure trained CNN residuals added to the already deployed phase-filter base."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from evaluate_video import luma
from fixed_point_reference import integer_emulated
from fit_phase_filter import neighbors
from metrics import psnr, temporal_error
from model import ResidualSR32


def phase_base(lr: np.ndarray, weights: np.ndarray) -> np.ndarray:
    h, w = lr.shape
    out = np.empty((h * 3 // 2, w * 3 // 2), dtype=np.uint8)
    for yp in range(3):
        for xp in range(3):
            samples = neighbors(lr, xp, yp)
            out[yp::3, xp::3] = np.clip(np.rint(samples @ weights[yp * 3 + xp]),
                                         0, 255).astype(np.uint8)
    return out


@torch.no_grad()
def evaluate(root: Path, model: ResidualSR32, scales: dict,
             q7_weights: np.ndarray, device: torch.device, limit: int) -> dict:
    lr_files = sorted((root / "lr720").glob("*.png"))[:limit or None]
    previous = {}
    totals = {name: {"sse": 0.0, "count": 0, "temporal": []}
              for name in ("bicubic", "phase_filter", "phase_plus_cnn")}
    for path in lr_files:
        lr = cv2.cvtColor(cv2.imread(str(path)), cv2.COLOR_BGR2YCrCb)[:, :, 0]
        hr = cv2.cvtColor(cv2.imread(str(root / "hr1080" / path.name)),
                          cv2.COLOR_BGR2YCrCb)[:, :, 0]
        x = torch.from_numpy(lr.copy()).to(device=device, dtype=torch.float32)[None, None]
        cnn = np.rint(integer_emulated(model, x, scales).squeeze().cpu().numpy()).clip(0, 255).astype(np.uint8)
        bicubic = np.rint(F.interpolate(x, size=(1080, 1920), mode="bicubic",
                                       align_corners=False).squeeze().cpu().numpy()).clip(0, 255).astype(np.uint8)
        phase = phase_base(lr, q7_weights)
        delta = cnn.astype(np.int16) - bicubic.astype(np.int16)
        combined = np.clip(phase.astype(np.int16) + delta, 0, 255).astype(np.uint8)
        for name, image in (("bicubic", bicubic), ("phase_filter", phase),
                            ("phase_plus_cnn", combined)):
            error = hr.astype(np.int16) - image.astype(np.int16)
            totals[name]["sse"] += float(np.sum(error.astype(np.float64) ** 2))
            totals[name]["count"] += error.size
            if name in previous:
                old_ref, old_out = previous[name]
                totals[name]["temporal"].append(temporal_error(old_ref, hr, old_out, image))
            previous[name] = (hr, image)
    result = {}
    for name, stats in totals.items():
        mse = stats["sse"] / stats["count"]
        result[name] = {"frames": len(lr_files),
                        "y_psnr": float(10 * np.log10(255.0**2 / mse)),
                        "temporal_error": float(np.mean(stats["temporal"]))}
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("checkpoint", type=Path)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("phase_filter_weights", type=Path)
    ap.add_argument("clips", type=Path, nargs="+")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--device", default="cuda")
    args = ap.parse_args()
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().eval().to(args.device)
    model.load_state_dict(saved["state_dict"])
    scales = json.loads(args.manifest.read_text(encoding="utf-8"))["activation_scales"]
    weights = np.asarray(json.loads(args.phase_filter_weights.read_text(encoding="utf-8"))[
        "hardware_weights_q7"], dtype=np.float64) / 128.0
    for clip in args.clips:
        print(clip.name, evaluate(clip, model, scales, weights,
                                  torch.device(args.device), args.limit), flush=True)


if __name__ == "__main__":
    main()
