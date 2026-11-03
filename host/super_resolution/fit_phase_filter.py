"""Fit a small 3:2 four-tap luminance subpixel filter for the first FPGA trial."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def luma(bgr: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)[:, :, 0].astype(np.float64)


def neighbors(lr: np.ndarray, xp: int, yp: int) -> np.ndarray:
    h, w = lr.shape
    yy = np.arange(yp, 1080, 3)
    xx = np.arange(xp, 1920, 3)
    x0 = np.clip(np.floor((xx + .5) * 2 / 3 - .5).astype(int), 0, w - 1)
    y0 = np.clip(np.floor((yy + .5) * 2 / 3 - .5).astype(int), 0, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    return np.stack([lr[np.ix_(y0, x0)], lr[np.ix_(y0, x1)],
                     lr[np.ix_(y1, x0)], lr[np.ix_(y1, x1)]], axis=-1)


def fileset(root: Path, limit: int) -> list[tuple[Path, Path]]:
    names = sorted((root / "lr720").glob("*.png"))
    if len(names) > limit:
        names = [names[i] for i in np.linspace(0, len(names) - 1, limit, dtype=int)]
    return [(p, root / "hr1080" / p.name) for p in names]


def fit(roots: list[Path], limit: int) -> np.ndarray:
    gram = np.zeros((9, 4, 4))
    rhs = np.zeros((9, 4))
    for root in roots:
        for lr_path, hr_path in fileset(root, limit):
            lr = luma(cv2.imread(str(lr_path)))
            hr = luma(cv2.imread(str(hr_path)))
            for yp in range(3):
                for xp in range(3):
                    p = yp * 3 + xp
                    n = neighbors(lr, xp, yp)
                    # The target and center pixel are expressed as local differences.
                    # This forces a flat input to produce an exactly flat output.
                    x = (n - n[..., :1]).reshape(-1, 4)[:, 1:]
                    y = (hr[yp::3, xp::3] - n[..., 0]).ravel()
                    gram[p, 1:, 1:] += x.T @ x
                    rhs[p, 1:] += x.T @ y
    weights = np.zeros((9, 4))
    for p in range(9):
        # A small ridge penalty avoids unstable coefficients on low texture scenes.
        weights[p, 1:] = np.linalg.solve(gram[p, 1:, 1:] + 1e6 * np.eye(3), rhs[p, 1:])
        weights[p, 0] = 1 - weights[p, 1:].sum()
    return weights


def evaluate(root: Path, wq: np.ndarray, limit: int) -> dict:
    sse = np.zeros(3)
    count = 0
    for lr_path, hr_path in fileset(root, limit):
        lr_u8 = cv2.imread(str(lr_path))
        hr = luma(cv2.imread(str(hr_path)))
        lr = luma(lr_u8)
        out = np.empty_like(hr)
        for yp in range(3):
            for xp in range(3):
                n = neighbors(lr, xp, yp)
                out[yp::3, xp::3] = np.clip(np.rint(n @ wq[yp * 3 + xp]), 0, 255)
        bilinear = luma(cv2.resize(lr_u8, (1920, 1080), interpolation=cv2.INTER_LINEAR))
        cubic = luma(cv2.resize(lr_u8, (1920, 1080), interpolation=cv2.INTER_CUBIC))
        for i, frame in enumerate((out, bilinear, cubic)):
            sse[i] += np.sum((frame - hr) ** 2)
        count += hr.size
    return {k: float(10 * np.log10(255 ** 2 / (v / count)))
            for k, v in zip(("phase_filter", "bilinear", "bicubic"), sse)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", type=Path, nargs="+", required=True)
    ap.add_argument("--test", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--frames", type=int, default=4)
    ap.add_argument("--eval-frames", type=int, default=20)
    args = ap.parse_args()
    w = fit(args.train, args.frames)
    q = np.rint(w * 128).astype(int)
    q[:, 0] += 128 - q.sum(axis=1)
    fractions = [5 / 6, 1 / 2, 1 / 6]
    bilinear = np.array([
        [(1 - fractions[yp]) * (1 - fractions[xp]),
         (1 - fractions[yp]) * fractions[xp],
         fractions[yp] * (1 - fractions[xp]),
         fractions[yp] * fractions[xp]]
        for yp in range(3) for xp in range(3)])
    hardware_q = np.rint(.25 * q + .75 * 128 * bilinear).astype(int)
    hardware_q[:, 0] += 128 - hardware_q.sum(axis=1)
    result = {"raw_weights_q7": q.tolist(),
              "hardware_weights_q7": hardware_q.tolist(),
              "heldout_y_psnr_db": evaluate(args.test, hardware_q / 128,
                                              args.eval_frames)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
