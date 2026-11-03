"""Offline, deterministic image simulation of rotation correction and shake filtering.

This exercises host estimation, coefficient quantization, and an ideal inverse
sampler. It does not simulate the FPGA RTL, UART timing, or HDMI capture.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

import cv2
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pose"))
from analyze_parallel_rotation import quantize, rotation_homography
from encode_rotation_images_uart import validate_stage8_profile
from measure_obs_rotation_send_uart import estimate_grid_angle, wrap_half_turn
from stage13_motion_stabilization import ShakeOnlyCompensator, estimate_translation
from verify_live_rotation import grid_angle_raw

WIDTH, HEIGHT = 1280, 720


def checkerboard() -> np.ndarray:
    image = np.full((HEIGHT, WIDTH, 3), 235, np.uint8)
    square = 50
    left = (WIDTH - 10 * square) // 2
    top = (HEIGHT - 7 * square) // 2
    for row in range(7):
        for col in range(10):
            if (row + col) % 2:
                x, y = left + col * square, top + row * square
                image[y:y + square, x:x + square] = 25
    return image


def quantized_matrix(rows: list[list[int]]) -> np.ndarray:
    matrix = np.asarray(rows, dtype=np.float64)
    matrix[:2] /= 65536.0
    matrix[2] /= float(1 << 30)
    return matrix


def rotation_run(out: Path) -> dict:
    base = checkerboard()
    rng = np.random.default_rng(20261103)
    calibration = {
        "_board_size": (9, 6), "_image_size": (WIDTH, HEIGHT),
        "_camera_matrix": np.asarray([[900, 0, WIDTH / 2],
                                       [0, 900, HEIGHT / 2], [0, 0, 1]], np.float64),
        "_distortion": np.zeros((5, 1), np.float64),
    }
    reference, _ = estimate_grid_angle(base, calibration)
    records = []
    xx, yy = np.meshgrid(np.arange(WIDTH), np.arange(HEIGHT))
    for index, actual in enumerate((0, -20, -10, -5, 5, 10, 20, 0)):
        truth = rotation_homography(actual, WIDTH / 2, HEIGHT / 2)
        current = cv2.warpPerspective(base, truth, (WIDTH, HEIGHT),
                                      borderValue=(235, 235, 235))
        detected, _ = estimate_grid_angle(current, calibration)
        degraded = cv2.GaussianBlur(current, (3, 3), 0.6)
        noise = rng.normal(0, 3, degraded.shape)
        degraded = np.clip(degraded.astype(np.float32) + noise, 0, 255).astype(np.uint8)
        noisy_detected, _ = estimate_grid_angle(degraded, calibration)
        noisy_estimate = wrap_half_turn(noisy_detected - reference)
        estimate = wrap_half_turn(detected - reference)
        matrix = rotation_homography(estimate, WIDTH / 2, HEIGHT / 2)
        rows = quantize(matrix)["integer_rows"]
        validate_stage8_profile(rows, WIDTH, HEIGHT)
        fixed = cv2.warpPerspective(current, quantized_matrix(rows), (WIDTH, HEIGHT),
                                    flags=cv2.WARP_INVERSE_MAP, borderValue=(0, 0, 0))
        residual = wrap_half_turn(grid_angle_raw(fixed, (9, 6)) -
                                  grid_angle_raw(base, (9, 6)))
        sx = matrix[0, 0] * xx + matrix[0, 1] * yy + matrix[0, 2]
        sy = matrix[1, 0] * xx + matrix[1, 1] * yy + matrix[1, 2]
        valid = float(np.mean((sx >= 0) & (sx < WIDTH - 1) &
                              (sy >= 0) & (sy < HEIGHT - 1)) * 100)
        records.append({"actual_deg": actual, "estimated_deg": round(estimate, 4),
                        "estimate_error_deg": round(wrap_half_turn(estimate - actual), 4),
                        "blur_noise_estimated_deg": round(noisy_estimate, 4),
                        "blur_noise_error_deg": round(wrap_half_turn(noisy_estimate - actual), 4),
                        "output_residual_deg": round(residual, 4),
                        "ideal_valid_area_percent": round(valid, 3)})
        stem = f"rotation_{index:02d}_{actual:+d}deg"
        cv2.imwrite(str(out / f"{stem}_input.png"), current)
        cv2.imwrite(str(out / f"{stem}_corrected.png"), fixed)
    errors = [abs(r["estimate_error_deg"]) for r in records]
    residuals = [abs(r["output_residual_deg"]) for r in records]
    noisy_errors = [abs(r["blur_noise_error_deg"]) for r in records]
    (out / "rotation_metrics.csv").write_text(
        "case,actual_deg,estimated_deg,estimate_error_deg,blur_noise_estimated_deg,"
        "blur_noise_error_deg,output_residual_deg,ideal_valid_area_percent\n" +
        "".join(f"{i},{r['actual_deg']},{r['estimated_deg']},{r['estimate_error_deg']},"
                f"{r['blur_noise_estimated_deg']},{r['blur_noise_error_deg']},"
                f"{r['output_residual_deg']},{r['ideal_valid_area_percent']}\n"
                for i, r in enumerate(records)), encoding="utf-8")
    return {"cases": records, "max_abs_estimate_error_deg": max(errors),
            "max_abs_blur_noise_error_deg": max(noisy_errors),
            "max_abs_output_residual_deg": max(residuals)}


def motion_run(out: Path, frames: int) -> dict:
    width, height = 640, 360
    rng = np.random.default_rng(20261103)
    texture = rng.integers(25, 230, (height, width), dtype=np.uint8)
    texture = cv2.GaussianBlur(texture, (5, 5), 0.8)
    filter_ = ShakeOnlyCompensator(alpha=0.18, max_correction_px=24.0)
    positions, corrected, corrections, estimation_errors, confidences = [], [], [], [], []
    previous = None
    previous_true = None
    invalid = 0
    for index in range(frames):
        t = index / 10.0
        true = np.asarray((6 * math.sin(2 * math.pi * 1.1 * t) +
                           2 * math.sin(2 * math.pi * 0.45 * t),
                           4 * math.sin(2 * math.pi * 0.9 * t)), dtype=np.float64)
        shifted = cv2.warpAffine(texture,
                                 np.float32([[1, 0, true[0]], [0, 1, true[1]]]),
                                 (width, height), borderMode=cv2.BORDER_REFLECT)
        if previous is None:
            correction = np.zeros(2)
        else:
            try:
                dx, dy, confidence, _ = estimate_translation(previous, shifted)
                delta = np.asarray((dx, dy))
                estimation_errors.append(float(np.linalg.norm(delta - (true - previous_true))))
                confidences.append(confidence)
                if confidence < 0.25 or np.linalg.norm(delta) > 40:
                    invalid += 1
                    correction = np.asarray(filter_.update(0, 0)[:2])
                else:
                    correction = np.asarray(filter_.update(dx, dy)[:2])
            except (ValueError, cv2.error):
                invalid += 1
                correction = np.asarray(filter_.update(0, 0)[:2])
        previous, previous_true = shifted, true
        positions.append(true)
        corrected.append(true - correction)
        corrections.append(correction)
    before = np.asarray(positions[10:])
    after = np.asarray(corrected[10:])
    before_var = float(np.var(before, axis=0).sum())
    after_var = float(np.var(after, axis=0).sum())
    result = {"frames": frames, "simulated_rate_fps": 10,
              "input_path_variance_px2": round(before_var, 4),
              "corrected_path_variance_px2": round(after_var, 4),
              "variance_ratio": round(after_var / before_var, 4),
              "variance_reduction_percent": round(100 * (1 - after_var / before_var), 2),
              "median_flow_error_px_per_step": round(float(np.median(estimation_errors)), 4),
              "median_flow_confidence": round(float(np.median(confidences)), 4),
              "invalid_estimates": invalid}
    (out / "motion_trajectory.csv").write_text(
        "frame,time_s,input_x,input_y,correction_x,correction_y,corrected_x,corrected_y\n" +
        "".join(f"{i},{i/10:.3f},{p[0]:.5f},{p[1]:.5f},{c[0]:.5f},{c[1]:.5f},"
                f"{q[0]:.5f},{q[1]:.5f}\n"
                for i, (p, c, q) in enumerate(zip(positions, corrections, corrected))), encoding="utf-8")
    return result


def save_figure(fig, out: Path, name: str) -> None:
    fig.savefig(out / name, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def plot_rotation(out: Path, records: list[dict]) -> None:
    fig, axes = plt.subplots(3, 2, figsize=(13, 11), layout="constrained")
    for row, (index, angle) in enumerate(((1, -20), (0, 0), (6, 20))):
        for col, kind in enumerate(("input", "corrected")):
            image = cv2.imread(str(out / f"rotation_{index:02d}_{angle:+d}deg_{kind}.png"))
            axes[row, col].imshow(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
            axes[row, col].set_title(f"{angle:+d} deg | {kind}", fontsize=12)
            axes[row, col].axis("off")
    fig.suptitle("Figure 1. Synthetic checkerboard: rotation and software correction", fontsize=15)
    save_figure(fig, out, "figure_1_rotation_examples.png")

    labels = [f"{i}: {r['actual_deg']:+d}" for i, r in enumerate(records)]
    x = np.arange(len(records))
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), layout="constrained")
    axes[0, 0].plot(x, [r["actual_deg"] for r in records], "k--o", label="Ground truth")
    axes[0, 0].plot(x, [r["estimated_deg"] for r in records], "o", label="Estimated")
    axes[0, 0].set_ylabel("Angle (deg)")
    axes[0, 0].legend()
    axes[0, 1].plot(x, [r["estimate_error_deg"] for r in records], "o-", label="Ideal image")
    axes[0, 1].plot(x, [r["blur_noise_error_deg"] for r in records], "s-", label="Blur + noise")
    axes[0, 1].set_ylabel("Estimation error (deg)")
    axes[0, 1].legend()
    axes[1, 0].plot(x, [r["output_residual_deg"] for r in records], "o-", color="#146c5a")
    axes[1, 0].set_ylabel("Residual grid angle (deg)")
    axes[1, 1].bar(x, [r["ideal_valid_area_percent"] for r in records], color="#3a72b8")
    axes[1, 1].set_ylim(75, 101)
    axes[1, 1].set_ylabel("Valid 2x2 sampling area (%)")
    for ax in axes.ravel():
        ax.set_xticks(x, labels, rotation=35, ha="right")
        ax.set_xlabel("Sequence: actual angle (deg)")
        ax.grid(alpha=0.25)
    fig.suptitle("Figure 2. Rotation estimates, correction residual and valid area", fontsize=15)
    save_figure(fig, out, "figure_2_rotation_metrics.png")


def plot_motion(out: Path, stats: dict) -> None:
    data = np.genfromtxt(out / "motion_trajectory.csv", delimiter=",", names=True)
    t = data["time_s"]
    fig, axes = plt.subplots(3, 1, figsize=(12, 9), layout="constrained")
    for ax, axis in zip(axes[:2], ("x", "y")):
        ax.plot(t, data[f"input_{axis}"], label="Input", color="#c15a35", linewidth=1.7)
        ax.plot(t, data[f"corrected_{axis}"], label="Corrected (ideal sampler)",
                color="#2169a3", linewidth=1.7)
        ax.set_ylabel(f"{axis.upper()} position (px)")
        ax.legend(loc="upper right")
        ax.grid(alpha=0.25)
    axes[2].bar(["Input", "Corrected"],
                [stats["input_path_variance_px2"], stats["corrected_path_variance_px2"]],
                color=["#c15a35", "#2169a3"])
    axes[2].set_ylabel("Trajectory variance (px$^2$)")
    axes[2].text(0.5, 0.9, f"Reduction: {stats['variance_reduction_percent']:.2f}%",
                 ha="center", transform=axes[2].transAxes)
    axes[2].grid(axis="y", alpha=0.25)
    axes[1].set_xlabel("Simulated time (s)")
    fig.suptitle("Figure 3. Synthetic periodic translation: before and after correction", fontsize=15)
    save_figure(fig, out, "figure_3_motion_time_series.png")

    fig, ax = plt.subplots(figsize=(7, 7), layout="constrained")
    ax.plot(data["input_x"], data["input_y"], color="#c15a35", label="Input", alpha=0.8)
    ax.plot(data["corrected_x"], data["corrected_y"], color="#2169a3",
            label="Corrected (ideal sampler)", alpha=0.9)
    ax.scatter([0], [0], marker="+", color="black", s=70, label="Nominal center")
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlabel("X displacement (px)")
    ax.set_ylabel("Y displacement (px)")
    ax.grid(alpha=0.25)
    ax.legend()
    ax.set_title("Figure 4. Synthetic background trajectory")
    save_figure(fig, out, "figure_4_motion_xy_path.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "simulation_results")
    parser.add_argument("--frames", type=int, default=120)
    args = parser.parse_args()
    if args.frames < 20:
        parser.error("--frames must be at least 20")
    args.out.mkdir(parents=True, exist_ok=True)
    result = {"type": "offline_idealized_simulation", "seed": 20261103,
              "rotation": rotation_run(args.out), "stabilization": motion_run(args.out, args.frames),
              "limitations": ["software ideal sampler; no FPGA RTL", "no UART ACK or HDMI capture",
                              "zero lens distortion and synthetic textures"]}
    plot_rotation(args.out, result["rotation"]["cases"])
    plot_motion(args.out, result["stabilization"])
    target = args.out / "summary.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"Saved: {target.resolve()}")


if __name__ == "__main__":
    main()
