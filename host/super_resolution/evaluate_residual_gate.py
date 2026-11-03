"""Evaluate a local-contrast gate for CNN residual stability on held-out clips."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from metrics import psnr, temporal_error
from model import ResidualSR32


def evaluate(root: Path, model: ResidualSR32, device: str, frames: int) -> dict:
    thresholds = (0, 8, 16, 24, 32, 48, 64, 96, 128)
    errors = {t: [[], []] for t in thresholds}
    previous = {}
    paths = sorted((root / "lr720").glob("*.png"))[:frames]
    for path in paths:
        lr = cv2.cvtColor(cv2.imread(str(path)), cv2.COLOR_BGR2YCrCb)[:, :, 0]
        hr = cv2.cvtColor(cv2.imread(str(root / "hr1080" / path.name)),
                          cv2.COLOR_BGR2YCrCb)[:, :, 0]
        x = torch.from_numpy(lr.astype(np.float32))[None, None].to(device)
        with torch.no_grad():
            prediction = model(x).squeeze().cpu().numpy()
            base = F.interpolate(x, size=(1080, 1920), mode="bicubic",
                                 align_corners=False).squeeze().cpu().numpy()
        residual = prediction - base
        hi = cv2.dilate(lr, np.ones((3, 3), np.uint8)).astype(np.float32)
        lo = cv2.erode(lr, np.ones((3, 3), np.uint8)).astype(np.float32)
        contrast = cv2.resize(hi - lo, (1920, 1080),
                              interpolation=cv2.INTER_LINEAR)
        for threshold in thresholds:
            if threshold:
                gate = np.clip((contrast - 2.0) / (threshold - 2.0), 0, 1)
                out = np.clip(np.rint(base + residual * gate), 0, 255).astype(np.uint8)
            else:
                out = np.clip(np.rint(prediction), 0, 255).astype(np.uint8)
            errors[threshold][0].append(psnr(hr, out))
            if threshold in previous:
                errors[threshold][1].append(temporal_error(
                    previous[threshold][0], hr, previous[threshold][1], out))
            previous[threshold] = (hr, out)
    return {str(t): {"psnr": float(np.mean(e[0])),
                     "temporal": float(np.mean(e[1]))}
            for t, e in errors.items()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("clips", type=Path, nargs="+")
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--device", default="cuda")
    args = parser.parse_args()
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().to(args.device).eval()
    model.load_state_dict(saved["state_dict"])
    for clip in args.clips:
        print(clip.name, evaluate(clip, model, args.device, args.frames), flush=True)


if __name__ == "__main__":
    main()
