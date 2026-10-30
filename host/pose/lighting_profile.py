"""Select a small FPGA enhancement curve from the raw OBS BGR frame."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


PROFILE_NAMES = {
    0: "bypass",
    1: "night",
    2: "night_strong",
    3: "highlight",
    4: "highlight_strong",
    5: "mixed",
}


@dataclass(frozen=True)
class LightingMetrics:
    mean: float
    p10: float
    median: float
    p90: float
    dark_ratio: float
    highlight_ratio: float
    local_dark_ratio: float
    local_highlight_ratio: float
    samples: int


def _local_exposure_ratios(luma: np.ndarray) -> tuple[float, float]:
    """Find the darkest and brightest neighboring tile windows in a frame."""
    height, width = luma.shape
    rows, cols = min(height, 8), min(width, 8)
    row_edges = np.linspace(0, height, rows + 1, dtype=np.intp)
    col_edges = np.linspace(0, width, cols + 1, dtype=np.intp)
    dark_counts = np.zeros((rows, cols), dtype=np.int64)
    highlight_counts = np.zeros((rows, cols), dtype=np.int64)
    pixel_counts = np.zeros((rows, cols), dtype=np.int64)

    for row in range(rows):
        for col in range(cols):
            tile = luma[row_edges[row]:row_edges[row + 1],
                        col_edges[col]:col_edges[col + 1]]
            dark_counts[row, col] = np.count_nonzero(tile <= 64)
            highlight_counts[row, col] = np.count_nonzero(tile >= 245)
            pixel_counts[row, col] = tile.size

    window_rows, window_cols = min(rows, 2), min(cols, 2)
    max_dark = 0.0
    max_highlight = 0.0
    for row in range(rows - window_rows + 1):
        for col in range(cols - window_cols + 1):
            area = pixel_counts[row:row + window_rows,
                                col:col + window_cols].sum()
            max_dark = max(max_dark, float(
                dark_counts[row:row + window_rows, col:col + window_cols].sum() / area
            ))
            max_highlight = max(max_highlight, float(
                highlight_counts[row:row + window_rows, col:col + window_cols].sum() / area
            ))
    return max_dark, max_highlight


def analyze_bgr(frame: np.ndarray, sample_stride: int = 8) -> LightingMetrics:
    """Measure BT.601-like 8-bit luma on a bounded grid of raw BGR pixels."""
    if not isinstance(frame, np.ndarray) or frame.ndim != 3 or frame.shape[2] != 3:
        raise ValueError("frame must be an HxWx3 BGR numpy array")
    if frame.dtype != np.uint8 or frame.shape[0] == 0 or frame.shape[1] == 0:
        raise ValueError("frame must be nonempty uint8 BGR")
    if sample_stride < 1:
        raise ValueError("sample_stride must be positive")

    sampled = frame[::sample_stride, ::sample_stride]
    blue = sampled[:, :, 0].astype(np.uint16)
    green = sampled[:, :, 1].astype(np.uint16)
    red = sampled[:, :, 2].astype(np.uint16)
    luma = ((29 * blue + 150 * green + 77 * red + 128) >> 8)
    flat_luma = luma.ravel()
    p10, median, p90 = np.percentile(flat_luma, (10, 50, 90))
    local_dark, local_highlight = _local_exposure_ratios(luma)
    return LightingMetrics(
        mean=float(np.mean(flat_luma)),
        p10=float(p10),
        median=float(median),
        p90=float(p90),
        dark_ratio=float(np.count_nonzero(flat_luma <= 64) / flat_luma.size),
        highlight_ratio=float(np.count_nonzero(flat_luma >= 245) / flat_luma.size),
        local_dark_ratio=local_dark,
        local_highlight_ratio=local_highlight,
        samples=int(flat_luma.size),
    )


def classify_lighting(metrics: LightingMetrics) -> int:
    """Return a provisional preset number; thresholds need real-scene tuning."""
    has_highlight = (
        metrics.median >= 185
        or metrics.highlight_ratio >= 0.1
        or metrics.local_highlight_ratio >= 0.3
    )
    has_dark = (
        (metrics.median <= 80 and metrics.dark_ratio >= 0.35)
        or metrics.local_dark_ratio >= 0.7
    )
    if has_highlight and has_dark:
        return 5
    if metrics.median >= 225 or metrics.highlight_ratio >= 0.3:
        return 4
    if metrics.median <= 40 and metrics.dark_ratio >= 0.55:
        return 2
    if has_highlight:
        return 3
    if has_dark:
        return 1
    return 0


class LightingSelector:
    """Change active profile only after consecutive agreeing frame candidates."""

    def __init__(self, stable_frames: int = 3) -> None:
        if stable_frames < 1:
            raise ValueError("stable_frames must be positive")
        self.stable_frames = stable_frames
        self.active = 0
        self._candidate = 0
        self._count = 0

    def update(self, candidate: int) -> int:
        if candidate not in PROFILE_NAMES:
            raise ValueError(f"unsupported lighting profile: {candidate}")
        if candidate == self.active:
            self._candidate = candidate
            self._count = 0
        else:
            if candidate != self._candidate:
                self._candidate = candidate
                self._count = 0
            self._count += 1
            if self._count >= self.stable_frames:
                self.active = candidate
                self._count = 0
        return self.active
