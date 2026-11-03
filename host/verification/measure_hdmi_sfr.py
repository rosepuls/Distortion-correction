"""Capture one FPGA HDMI frame and measure grid straightness, black border and SFR.

This is a bounded engineering measurement, not an ISO 12233 certification.
The algorithm rejects frames without a suitable isolated slanted edge.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
import json
import math
from pathlib import Path
import sys

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from device_config import load_device_config


SFR_FREQUENCIES = (0.10, 0.20, 0.30, 0.40, 0.50)
GRID_PATTERNS = ((9, 6), (8, 5), (7, 5), (6, 5), (6, 4),
                 (5, 4), (4, 4), (4, 3))


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def parse_args() -> argparse.Namespace:
    devices = load_device_config()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-id", type=int, required=True, metavar="N",
                        help="Number of the OBS verification image currently displayed (0..7 for current grid set)")
    parser.add_argument("--source", type=int, default=devices["hdmi_capture_index"],
                        help="DirectShow HDMI capture index from device_config.json")
    parser.add_argument("--width", type=positive_int, default=devices["width"])
    parser.add_argument("--height", type=positive_int, default=devices["height"])
    parser.add_argument("--warmup-frames", type=positive_int, default=30)
    parser.add_argument("--out", type=Path, default=HERE / "capture_results")
    parser.add_argument("--input-image", type=Path,
                        help="Read an existing image instead of the USB device (offline inspection)")
    parser.add_argument("--reference-image", type=Path,
                        help="Original OBS photo for discounting pre-existing black content (default: image-id.png)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print the measurement without saving a capture or appending the record")
    return parser.parse_args()


def capture_frame(args: argparse.Namespace) -> tuple[np.ndarray, dict]:
    if args.input_image:
        encoded = np.fromfile(str(args.input_image), dtype=np.uint8)
        frame = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError(f"Could not read image: {args.input_image}")
        return frame, {"source": str(args.input_image), "source_type": "file"}

    cap = cv2.VideoCapture(args.source, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise ValueError(
            f"Could not open DirectShow device {args.source}. Close the preview script "
            "and check --source."
        )
    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        frame = None
        for _ in range(args.warmup_frames):
            ok, frame = cap.read()
            if not ok or frame is None:
                raise ValueError("USB capture failed during warmup")
        return frame, {"source": args.source, "source_type": "DirectShow"}
    finally:
        cap.release()


def measure_grid_straightness(frame: np.ndarray) -> dict:
    """Fit visible chessboard corner rows and columns, including partial boards."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    for cols, rows in GRID_PATTERNS:
        flags = cv2.CALIB_CB_EXHAUSTIVE
        if (cols, rows) == (9, 6):
            flags |= cv2.CALIB_CB_ACCURACY
        found, corners = cv2.findChessboardCornersSB(gray, (cols, rows), flags=flags)
        if found:
            break
    else:
        raise ValueError("no visible checkerboard subgrid of at least 4x3 inner corners")
    grid = corners.reshape(rows, cols, 2).astype(np.float64)
    spacings = np.concatenate((np.linalg.norm(np.diff(grid, axis=0), axis=2).ravel(),
                               np.linalg.norm(np.diff(grid, axis=1), axis=2).ravel()))
    pitch = float(np.median(spacings))
    if pitch < 8:
        raise ValueError("checkerboard squares too small for straightness measurement")
    residuals = []
    for line in list(grid) + [grid[:, col, :] for col in range(cols)]:
        centered = line - np.mean(line, axis=0)
        _, _, basis = np.linalg.svd(centered, full_matrices=False)
        direction = basis[0]
        residuals.extend(np.abs(centered[:, 0] * direction[1] -
                                centered[:, 1] * direction[0]).tolist())
    values = np.asarray(residuals)
    return {
        "inner_corners": [cols, rows],
        "coverage": "full" if (cols, rows) == (9, 6) else "partial",
        "line_count": cols + rows,
        "point_to_line_count": int(values.size),
        "mean_px": float(np.mean(values)),
        "p95_px": float(np.percentile(values, 95)),
        "max_px": float(np.max(values)),
        "p95_percent_of_grid_pitch": float(100 * np.percentile(values, 95) / pitch),
        "grid_pitch_px": pitch,
        "corners_xy": grid.reshape(-1, 2).round(2).tolist(),
    }


def measure_black_border(frame: np.ndarray, threshold: int = 12,
                         reference_input: np.ndarray | None = None) -> tuple[dict, np.ndarray]:
    """Count near-black regions connected to any of the four image boundaries."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    dark = (gray <= threshold).astype(np.uint8)
    count, labels, _, _ = cv2.connectedComponentsWithStats(dark, 8)
    height, width = gray.shape
    boundary = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    mask = np.zeros_like(gray, dtype=np.uint8)
    for label in boundary:
        if 0 < label < count:
            mask[labels == label] = 255
    candidate_pixels = int(np.count_nonzero(mask))
    if candidate_pixels > 0.75 * width * height:
        raise ValueError("most of frame is black; check HDMI signal before measuring borders")
    if reference_input is not None:
        reference = cv2.cvtColor(reference_input, cv2.COLOR_BGR2GRAY)
        reference = cv2.resize(reference, (width, height), interpolation=cv2.INTER_LINEAR)
        mask[reference <= 25] = 0
    pixels = int(np.count_nonzero(mask))
    return ({"pixels": pixels, "percent": 100.0 * pixels / (width * height),
             "candidate_pixels": candidate_pixels,
             "candidate_percent": 100.0 * candidate_pixels / (width * height),
             "threshold_8bit": threshold,
             "reference_used": reference_input is not None,
             "method": "boundary-connected near-black pixels; original dark pixels discounted"}, mask)


def fit_edge(gray: np.ndarray, orientation: str) -> dict:
    """Fit one near-axis edge in a small ROI using row/column gradient peaks."""
    vertical = orientation == "vertical"
    gradient = cv2.Sobel(gray, cv2.CV_32F, 1 if vertical else 0,
                         0 if vertical else 1, ksize=3)
    n_along = gray.shape[0] if vertical else gray.shape[1]
    n_across = gray.shape[1] if vertical else gray.shape[0]
    if n_along < 32 or n_across < 20:
        raise ValueError("edge ROI too small")
    coordinate = []
    peak_position = []
    strengths = []
    for along in range(3, n_along - 3):
        row = np.abs(gradient[along, :] if vertical else gradient[:, along])
        search = row[5:n_across - 5]
        if search.size == 0:
            continue
        cross = int(np.argmax(search)) + 5
        strength = float(row[cross])
        if strength < 45.0:
            continue
        # Gradient centroid gives subpixel edge location without relying on binary threshold.
        lo, hi = max(0, cross - 2), min(n_across, cross + 3)
        weights = row[lo:hi]
        subpixel = float(np.dot(np.arange(lo, hi), weights) / weights.sum())
        coordinate.append(along)
        peak_position.append(subpixel)
        strengths.append(strength)
    if len(coordinate) < max(28, int(0.65 * (n_along - 6))):
        raise ValueError("edge does not span enough of ROI")
    along = np.asarray(coordinate, dtype=np.float64)
    across = np.asarray(peak_position, dtype=np.float64)
    keep = np.ones(len(along), dtype=bool)
    for _ in range(3):
        slope, offset = np.polyfit(along[keep], across[keep], 1)
        residual = across - (slope * along + offset)
        keep = np.abs(residual) < 1.5
        if keep.sum() < max(25, int(0.60 * len(along))):
            raise ValueError("multiple edges or corners inside ROI")
    slope, offset = np.polyfit(along[keep], across[keep], 1)
    rms = float(np.sqrt(np.mean((across[keep] - (slope * along[keep] + offset)) ** 2)))
    angle = math.degrees(math.atan(abs(slope)))
    if not 2.0 <= angle <= 25.0:
        raise ValueError(f"edge slant {angle:.2f} deg outside 2-25 deg")
    if rms > 0.75:
        raise ValueError(f"edge fit residual {rms:.2f} px too high")
    return {"orientation": orientation, "slope": float(slope), "offset": float(offset),
            "angle_deg": angle, "fit_rms_px": rms, "edge_length_px": int(keep.sum()),
            "gradient": float(np.median(np.asarray(strengths)[keep]))}


def compute_sfr(gray: np.ndarray, edge: dict) -> tuple[np.ndarray, np.ndarray, float]:
    """Build a 4x oversampled edge spread function, then its normalized SFR."""
    yy, xx = np.indices(gray.shape, dtype=np.float64)
    slope, offset = edge["slope"], edge["offset"]
    if edge["orientation"] == "vertical":
        distance = (xx - slope * yy - offset) / math.sqrt(1 + slope * slope)
    else:
        distance = (yy - slope * xx - offset) / math.sqrt(1 + slope * slope)
    # Twenty-four source/captured pixels across the edge, sampled at quarter-pixel bins.
    bins = np.floor((distance + 12.0) * 4.0).astype(np.int32)
    valid = (bins >= 0) & (bins < 96)
    counts = np.bincount(bins[valid].ravel(), minlength=96)
    sums = np.bincount(bins[valid].ravel(), weights=gray[valid].ravel(), minlength=96)
    good = counts >= 4
    if good.sum() < 80:
        raise ValueError("too few samples in edge spread bins")
    position = np.arange(96, dtype=np.float64)
    esf = np.interp(position, position[good], (sums / np.maximum(counts, 1))[good])
    contrast = float(abs(np.mean(esf[-8:]) - np.mean(esf[:8])))
    if contrast < 35.0:
        raise ValueError(f"edge contrast {contrast:.1f}/255 too low")
    if np.sum(np.abs(np.diff(esf))) > 1.35 * contrast:
        raise ValueError("edge has multiple transitions, such as an outlined gray square")
    # A light smoothing suppresses bin occupancy noise; window limits FFT leakage.
    esf = cv2.GaussianBlur(esf.reshape(1, -1), (5, 1), 0.65).ravel()
    lsf = np.gradient(esf, 0.25) * np.hamming(len(esf))
    spectrum = np.abs(np.fft.rfft(lsf, n=4096))
    if spectrum[0] <= 1e-9:
        raise ValueError("invalid zero-frequency SFR")
    frequencies = np.fft.rfftfreq(4096, d=0.25)
    sfr = spectrum / spectrum[0]
    within = frequencies <= 0.5
    f, s = frequencies[within], sfr[within]
    return f, s, contrast


def calculate_mtf50(frequencies: np.ndarray, sfr: np.ndarray) -> float | None:
    """Return the first descending SFR=0.5 crossing within Nyquist, if present."""
    crossing = np.flatnonzero((sfr[:-1] > 0.5) & (sfr[1:] <= 0.5))
    if crossing.size == 0:
        return None
    index = int(crossing[0] + 1)
    f0, f1 = float(frequencies[index - 1]), float(frequencies[index])
    s0, s1 = float(sfr[index - 1]), float(sfr[index])
    if abs(s1 - s0) < 1e-12:
        return f1
    return f0 + (0.5 - s0) * (f1 - f0) / (s1 - s0)


def find_best_edge(frame: np.ndarray) -> tuple[dict, np.ndarray, np.ndarray]:
    gray_full = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    height, width = gray_full.shape
    scale = min(1.0, 1280.0 / width)
    small = cv2.resize(gray_full, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    # Candidate edges must belong to one of many similar dark checker squares.
    # This prevents a high-contrast desk, clothing, or screen border from winning.
    _, dark = cv2.threshold(small, 145, 255, cv2.THRESH_BINARY_INV)
    contours, _ = cv2.findContours(dark, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    squares = []
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        area = cv2.contourArea(contour)
        if not (25 <= w <= 160 and 25 <= h <= 160 and 500 <= area <= 18000):
            continue
        if not (0.48 <= area / (w * h) <= 0.98 and 0.55 <= w / h <= 1.8):
            continue
        squares.append((contour, x + w / 2, y + h / 2, (w + h) / 2))
    candidates = []
    for contour, cx_small, cy_small, size_small in squares:
        neighbors = sum(math.hypot(cx_small - other[1], cy_small - other[2])
                        < 3.5 * max(size_small, other[3]) for other in squares)
        if neighbors < 5:
            continue
        corners = cv2.boxPoints(cv2.minAreaRect(contour)) / scale
        for index in range(4):
            first, second = corners[index], corners[(index + 1) % 4]
            dx, dy = second - first
            length = float(math.hypot(dx, dy))
            if length < 42:
                continue
            orientation = "vertical" if abs(dy) > abs(dx) else "horizontal"
            slant = math.degrees(math.atan2(min(abs(dx), abs(dy)), max(abs(dx), abs(dy))))
            if not 2.0 <= slant <= 25.0:
                continue
            cx, cy = np.rint((first + second) / 2).astype(int)
            half_along = max(18, min(45, int(length * 0.32)))
            half_across = max(18, min(29, int(length * 0.22)))
            half_w, half_h = ((half_across, half_along) if orientation == "vertical"
                              else (half_along, half_across))
            x0, x3 = cx - half_w, cx + half_w
            y0, y3 = cy - half_h, cy + half_h
            if x0 < 5 or y0 < 5 or x3 >= width - 5 or y3 >= height - 5:
                continue
            crop = gray_full[y0:y3, x0:x3]
            try:
                fit = fit_edge(crop, orientation)
                f, s, contrast = compute_sfr(crop, fit)
            except ValueError:
                continue
            if float(np.max(s[(f >= 0.05) & (f <= 0.40)])) > 1.20:
                continue
            # Prefer long, clean, high-contrast segments.
            score = fit["edge_length_px"] * contrast / (1.0 + 3.0 * fit["fit_rms_px"])
            candidates.append((score, (x0, y0, x3 - x0, y3 - y0), fit, f, s, contrast))
    # A dedicated slanted-edge chart has one large dark region, not a grid of squares.
    if not candidates and len(squares) < 6:
        lines = cv2.HoughLinesP(cv2.Canny(small, 60, 150), 1, np.pi / 1800,
                                threshold=35, minLineLength=40, maxLineGap=5)
        if lines is not None:
            for line in lines[:, 0, :]:
                x1, y1, x2, y2 = (int(round(v / scale)) for v in line)
                dx, dy = x2 - x1, y2 - y1
                length = math.hypot(dx, dy)
                if length < 45:
                    continue
                orientation = "vertical" if abs(dy) > abs(dx) else "horizontal"
                slant = math.degrees(math.atan2(min(abs(dx), abs(dy)), max(abs(dx), abs(dy))))
                if not 2.0 <= slant <= 25.0:
                    continue
                cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
                half_along = min(45, int(length * 0.32))
                half_across = 25
                half_w, half_h = ((half_across, half_along) if orientation == "vertical"
                                  else (half_along, half_across))
                x0, x3 = cx - half_w, cx + half_w
                y0, y3 = cy - half_h, cy + half_h
                if x0 < 5 or y0 < 5 or x3 >= width - 5 or y3 >= height - 5:
                    continue
                crop = gray_full[y0:y3, x0:x3]
                try:
                    fit = fit_edge(crop, orientation)
                    f, s, contrast = compute_sfr(crop, fit)
                except ValueError:
                    continue
                if float(np.max(s[(f >= 0.05) & (f <= 0.40)])) > 1.20:
                    continue
                score = fit["edge_length_px"] * contrast / (1.0 + 3.0 * fit["fit_rms_px"])
                candidates.append((score, (x0, y0, x3 - x0, y3 - y0), fit,
                                   f, s, contrast))
    if not candidates:
        raise ValueError("no checkerboard edge passed isolation, slant, contrast and SFR checks; use a slanted-edge chart")
    _, roi, fit, f, s, contrast = max(candidates, key=lambda item: item[0])
    fit.update({"roi_xywh": list(roi), "contrast_8bit": contrast,
                "candidate_count": len(candidates)})
    return fit, f, s


def save_png(path: Path, frame: np.ndarray) -> None:
    ok, encoded = cv2.imencode(".png", frame)
    if not ok:
        raise ValueError(f"PNG encoding failed: {path}")
    encoded.tofile(str(path))


def main() -> int:
    args = parse_args()
    stamp = datetime.now().astimezone()
    stem = f"image_{args.image_id}_{stamp.strftime('%Y%m%d_%H%M%S_%f')}"
    try:
        frame, source = capture_frame(args)
    except ValueError as exc:
        print(f"Capture failed: {exc}", file=sys.stderr)
        return 2
    height, width = frame.shape[:2]
    record = {"timestamp": stamp.isoformat(timespec="seconds"), "image_id": args.image_id,
              "capture_size": [width, height], "requested_size": [args.width, args.height], **source}
    if (width, height) != (args.width, args.height) and source["source_type"] == "DirectShow":
        print(f"WARNING: requested {args.width}x{args.height}, received {width}x{height}.")
    if not args.dry_run:
        args.out.mkdir(parents=True, exist_ok=True)
        capture_path = args.out / f"{stem}_fpga.png"
        save_png(capture_path, frame)
        record["capture_png"] = str(capture_path.resolve())
        print(f"FPGA HDMI 原始截图（可插入 Word）：{capture_path.resolve()}")
    try:
        grid = measure_grid_straightness(frame)
        record["grid_straightness"] = grid
        print(f"Image {args.image_id} grid straightness ({grid['coverage']} "
              f"{grid['inner_corners'][0]}x{grid['inner_corners'][1]} corners): "
              f"mean={grid['mean_px']:.3f} px, P95={grid['p95_px']:.3f} px, "
              f"max={grid['max_px']:.3f} px, P95/pitch={grid['p95_percent_of_grid_pitch']:.2f}%")
        if not args.dry_run:
            marked = frame.copy()
            for x, y in grid["corners_xy"]:
                cv2.circle(marked, (round(x), round(y)), 3, (0, 0, 255), -1)
            path = args.out / f"{stem}_grid.png"
            save_png(path, marked)
            record["grid_png"] = str(path.resolve())
    except ValueError as exc:
        record["grid_straightness"] = {"status": "unavailable", "reason": str(exc)}
        print(f"Image {args.image_id} grid straightness: unavailable ({exc})")

    try:
        reference_path = args.reference_image or HERE / f"{args.image_id}.png"
        reference = None
        if reference_path.is_file():
            encoded = np.fromfile(str(reference_path), dtype=np.uint8)
            reference = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
            if reference is None:
                raise ValueError(f"could not read original photo: {reference_path}")
            record["reference_image"] = str(reference_path.resolve())
        elif args.reference_image:
            raise ValueError(f"original photo does not exist: {reference_path}")
        border, mask = measure_black_border(frame, reference_input=reference)
        record["black_border"] = border
        label = "black border estimate" if reference is not None else "black border candidate"
        print(f"Image {args.image_id} {label}: "
              f"{border['percent']:.3f}% ({border['pixels']} pixels; "
              f"raw dark-edge candidate {border['candidate_percent']:.3f}%; "
              f"gray<={border['threshold_8bit']})")
        if not args.dry_run:
            path = args.out / f"{stem}_black_border_mask.png"
            save_png(path, mask)
            record["black_border_mask_png"] = str(path.resolve())
    except ValueError as exc:
        record["black_border"] = {"status": "unavailable", "reason": str(exc)}
        print(f"Image {args.image_id} black border: unavailable ({exc})")

    try:
        fit, frequencies, sfr = find_best_edge(frame)
        mtf50 = calculate_mtf50(frequencies, sfr)
        samples = {f"{frequency:.2f}": float(np.interp(frequency, frequencies, sfr))
                   for frequency in SFR_FREQUENCIES}
        record["sfr"] = {"status": "ok", "edge": fit, "samples": samples,
                         "mtf50_cycles_per_captured_pixel": mtf50}
        if mtf50 is None:
            record["sfr"]["mtf50_status"] = "unavailable: no 0.5 crossing before Nyquist"
            print("MTF50: unavailable (SFR does not cross 0.5 before Nyquist)")
        else:
            print(f"MTF50 = {mtf50:.4f} cycles/captured-pixel")
        print("SFR (cycles/captured-pixel): " + ", ".join(
            f"{freq:.2f}={samples[f'{freq:.2f}']:.3f}" for freq in SFR_FREQUENCIES))
        print(f"SFR edge ROI={fit['roi_xywh']}, slant={fit['angle_deg']:.2f} deg")
        if not args.dry_run:
            sfr_path = args.out / f"{stem}_sfr.csv"
            with sfr_path.open("w", newline="", encoding="utf-8") as output:
                writer = csv.writer(output)
                writer.writerow(["frequency_cycles_per_captured_pixel", "sfr_normalized"])
                writer.writerows((f"{freq:.6f}", f"{value:.6f}") for freq, value in zip(frequencies, sfr))
            record["sfr_csv"] = str(sfr_path.resolve())
            marked = frame.copy()
            x, y, w, h = fit["roi_xywh"]
            cv2.rectangle(marked, (x, y), (x + w, y + h), (0, 0, 255), 2)
            path = args.out / f"{stem}_edge.png"
            save_png(path, marked)
            record["edge_png"] = str(path.resolve())
    except ValueError as exc:
        record["sfr"] = {"status": "unavailable", "reason": str(exc)}
        print(f"SFR: unavailable ({exc})")

    grid_ok = "status" not in record["grid_straightness"]
    border_ok = "status" not in record["black_border"]
    sfr_ok = record["sfr"]["status"] == "ok"
    record["status"] = "ok" if border_ok and (grid_ok or sfr_ok) else "partial"
    if not args.dry_run:
        record_path = args.out / "measurements.jsonl"
        with record_path.open("a", encoding="utf-8", newline="\n") as output:
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"测量记录：{record_path.resolve()}")
    return 0 if record["status"] == "ok" else 3


if __name__ == "__main__":
    raise SystemExit(main())
