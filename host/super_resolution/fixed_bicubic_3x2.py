"""Bit-exact Catmull-Rom 3:2 luma resize reference for RTL deployment."""

from __future__ import annotations

import json
import math

import numpy as np


COEFF_FRAC_BITS = 14
COEFF_SCALE = 1 << COEFF_FRAC_BITS
PHASE_DENOMINATOR = 6


def round_away_from_zero(numerator: int, denominator: int) -> int:
    """Round an integer ratio to nearest, with exact ties away from zero."""
    sign = -1 if numerator < 0 else 1
    magnitude = abs(numerator)
    return sign * ((magnitude + denominator // 2) // denominator)


def _keys_weight(distance: float, a: float = -0.75) -> float:
    x = abs(distance)
    if x < 1.0:
        return (a + 2.0) * x**3 - (a + 3.0) * x**2 + 1.0
    if x < 2.0:
        return a * x**3 - 5.0 * a * x**2 + 8.0 * a * x - 4.0 * a
    return 0.0


def phase_weights_q14() -> dict:
    """Return output-x phase coefficients; y uses the same three phases."""
    phases = []
    # For align_corners=False 3:2 resize, fractional source phases repeat
    # as 5/6, 1/2, 1/6. Taps are floor(src)-1 through floor(src)+2.
    for numerator in (5, 3, 1):
        fraction = numerator / PHASE_DENOMINATOR
        weights = [_keys_weight(fraction - tap) for tap in (-1, 0, 1, 2)]
        quantized = [int(math.floor(w * COEFF_SCALE + 0.5)) if w >= 0
                     else -int(math.floor(-w * COEFF_SCALE + 0.5))
                     for w in weights]
        # Put quantization residue in the largest-magnitude center coefficient
        # so every phase has exact unity DC gain in Q2.14.
        center = max(range(4), key=lambda i: abs(weights[i]))
        quantized[center] += COEFF_SCALE - sum(quantized)
        phases.append({"fraction": f"{numerator}/6", "weights_q14": quantized})
    return {
        "kernel": "Keys cubic a=-0.75 (PyTorch bicubic compatible)",
        "scale": "3:2 center aligned: src=(dst+0.5)*2/3-0.5",
        "coefficient_format": "signed Q2.14",
        "phase_order": ["5/6", "1/2", "1/6"],
        "edge_rule": "replicate nearest edge sample for each tap",
        "rounding": "nearest, exact ties away from zero, once after 2D sum",
        "phases": phases,
    }


def resize_bicubic_3x2_q14(image: np.ndarray) -> np.ndarray:
    """Resize a uint8 HxW plane (even dimensions) using Q14 separable weights.

    The 2D numerator is accumulated before rounding, matching a separable RTL
    pipeline that retains the horizontal Q14 intermediate without truncation.
    """
    if image.ndim != 2 or image.dtype != np.uint8:
        raise ValueError("image must be a uint8 HxW plane")
    h, w = image.shape
    if h % 2 or w % 2:
        raise ValueError("3:2 resize requires even input dimensions")
    table = phase_weights_q14()["phases"]
    fractions = (5, 3, 1)
    out = np.empty((h * 3 // 2, w * 3 // 2), dtype=np.int32)
    for oy in range(out.shape[0]):
        sy_num = (2 * oy + 1) * 2 - 3  # source coordinate numerator / 6
        sy_floor = sy_num // 6
        py = fractions[oy % 3]
        wy = table[oy % 3]["weights_q14"]
        ys = [min(max(sy_floor + tap, 0), h - 1) for tap in (-1, 0, 1, 2)]
        for ox in range(out.shape[1]):
            sx_num = (2 * ox + 1) * 2 - 3
            sx_floor = sx_num // 6
            wx = table[ox % 3]["weights_q14"]
            xs = [min(max(sx_floor + tap, 0), w - 1) for tap in (-1, 0, 1, 2)]
            accum = 0
            for iy in range(4):
                for ix in range(4):
                    accum += int(image[ys[iy], xs[ix]]) * wy[iy] * wx[ix]
            value = round_away_from_zero(accum, COEFF_SCALE * COEFF_SCALE)
            # Keep Catmull-Rom overshoot until after the learned residual join;
            # the final RGB/Y output stage performs the uint8 saturation.
            out[oy, ox] = value
    return out


def write_phase_table(path) -> None:
    from pathlib import Path
    Path(path).write_text(json.dumps(phase_weights_q14(), indent=2) + "\n",
                          encoding="utf-8")
