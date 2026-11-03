"""Image and temporal metrics used by the SR video comparison tool."""

from __future__ import annotations

import numpy as np


def psnr(reference: np.ndarray, estimate: np.ndarray) -> float:
    error = np.asarray(reference, dtype=np.float32) - np.asarray(estimate, dtype=np.float32)
    mse = float(np.mean(error * error))
    return float("inf") if mse == 0 else 10.0 * np.log10((255.0 * 255.0) / mse)


def ssim_global(reference: np.ndarray, estimate: np.ndarray) -> float:
    x = np.asarray(reference, dtype=np.float64)
    y = np.asarray(estimate, dtype=np.float64)
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    mx, my = x.mean(), y.mean()
    vx, vy = x.var(), y.var()
    cov = np.mean((x - mx) * (y - my))
    return float(((2 * mx * my + c1) * (2 * cov + c2)) /
                 ((mx * mx + my * my + c1) * (vx + vy + c2)))


def temporal_error(ref_prev: np.ndarray, ref_now: np.ndarray,
                   out_prev: np.ndarray, out_now: np.ndarray) -> float:
    """Difference between reference and output frame-to-frame changes."""
    ref_delta = ref_now.astype(np.float32) - ref_prev.astype(np.float32)
    out_delta = out_now.astype(np.float32) - out_prev.astype(np.float32)
    return float(np.mean(np.abs(ref_delta - out_delta)))
