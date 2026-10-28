from pathlib import Path
import csv

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
from PIL import Image


ROOT = Path(__file__).resolve().parent / "comparison_output"
WIDTH = HEIGHT = 128


def load_capture(path: Path) -> np.ndarray:
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != WIDTH * HEIGHT:
        raise ValueError(f"{path.name}: expected {WIDTH * HEIGHT} pixels, got {len(rows)}")
    image = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)
    for expected, row in enumerate(rows):
        idx = int(row["idx"])
        x, y = int(row["x"]), int(row["y"])
        if idx != expected or idx != y * WIDTH + x:
            raise ValueError(f"{path.name}: out-of-order pixel at row {expected}: {row}")
        image[y, x] = [int(row["r"]), int(row["g"]), int(row["b"])]
    return image


def source_chart() -> np.ndarray:
    image = np.zeros((20, 20), dtype=np.uint8)
    for y in range(20):
        for x in range(20):
            if y < 10 and x < 10:
                value = 24 if (x + y) % 2 == 0 else 232
            elif y < 10:
                value = 32 if x % 2 == 0 else 224
            elif x < 10:
                value = 28 if x < ((y - 10) // 2 + 2) else 228
            elif x < 14:
                value = 32
            else:
                value = 224
            image[y, x] = value
    return image


def main() -> None:
    bilinear = load_capture(ROOT / "stage8_bilinear.csv")
    bicubic = load_capture(ROOT / "stage9_catmull_rom.csv")
    difference = np.max(np.abs(bilinear.astype(np.int16) - bicubic.astype(np.int16)), axis=2)
    changed = difference != 0
    mae = float(np.mean(np.abs(bilinear.astype(np.int16) - bicubic.astype(np.int16))))
    changed_pct = 100.0 * float(np.count_nonzero(changed)) / difference.size

    # These regions cover the 1-pixel checkerboard and diagonal / hard edges.
    crop = np.s_[18:78, 18:78]
    chart = source_chart()
    raw_rgb = np.repeat(chart[:, :, None], 3, axis=2)
    scaled_rgb = np.repeat(np.repeat(raw_rgb, 32, axis=0), 32, axis=1)
    Image.fromarray(raw_rgb, mode="RGB").save(ROOT / "input_chart_20x20.png")
    Image.fromarray(scaled_rgb, mode="RGB").save(ROOT / "input_chart_640x640.png")
    Image.fromarray(scaled_rgb, mode="RGB").save(ROOT / "input_chart_640x640.bmp")
    np.savetxt(ROOT / "input_chart_values.csv", chart, delimiter=",", fmt="%d")
    fig = plt.figure(figsize=(15.5, 11.5), constrained_layout=True)
    grid = fig.add_gridspec(3, 3, height_ratios=(1.0, 1.0, 0.52))
    axes = np.array([[fig.add_subplot(grid[r, c]) for c in range(3)] for r in range(2)])
    fig.suptitle(
        "RTL interpolation comparison · same Q0.16 coordinates · 8× enlargement",
        fontsize=16,
        fontweight="bold",
    )

    panels = [
        (axes[0, 0], chart, "Shared 20×20 source chart", "gray", "nearest"),
        (axes[0, 1], bilinear, "Stage 8 · bilinear RTL", "gray", "nearest"),
        (axes[0, 2], bicubic, "Stage 9 · Catmull–Rom RTL", "gray", "nearest"),
    ]
    for ax, data, title, cmap, interpolation in panels:
        ax.imshow(data, cmap=cmap, vmin=0, vmax=255, interpolation=interpolation)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_aspect("equal")

    # Outline the high-frequency patch enlarged in the second row.
    for ax in axes[0, 1:]:
        ax.add_patch(Rectangle((18, 18), 60, 60, fill=False, edgecolor="#ff3b30", linewidth=1.5))

    axes[1, 0].imshow(bilinear[crop], cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    axes[1, 0].set_title("Bilinear · enlarged detail")
    axes[1, 1].imshow(bicubic[crop], cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    axes[1, 1].set_title("Catmull–Rom · same detail")
    for ax in axes[1, :2]:
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_aspect("equal")

    heat = axes[1, 2].imshow(difference, cmap="magma", vmin=0, vmax=max(1, int(difference.max())), interpolation="nearest")
    axes[1, 2].set_title(f"Absolute RGB difference\n{changed_pct:.1f}% pixels differ · MAE {mae:.2f}")
    axes[1, 2].set_xticks([])
    axes[1, 2].set_yticks([])
    axes[1, 2].set_aspect("equal")
    fig.colorbar(heat, ax=axes[1, 2], fraction=0.046, pad=0.04, label="max |channel delta| (0–255)")

    # Plot a scanline that crosses the hard edge in the bottom-right chart tile.
    profile_ax = fig.add_subplot(grid[2, :])
    profile_y = 100
    profile_x = np.arange(82, 111)
    profile_ax.plot(profile_x, bilinear[profile_y, profile_x, 0], "o-", ms=3,
                    label="Stage 8 bilinear RTL")
    profile_ax.plot(profile_x, bicubic[profile_y, profile_x, 0], "o-", ms=3,
                    label="Stage 9 Catmull–Rom RTL")
    profile_ax.set_title("Output intensity across the hard edge (one simulated scanline)")
    profile_ax.set_xlabel("Output pixel x")
    profile_ax.set_ylabel("Gray value (0–255)")
    profile_ax.set_ylim(0, 255)
    profile_ax.grid(True, alpha=0.25)
    profile_ax.legend(loc="center left", bbox_to_anchor=(1.01, 0.5))
    for ax in axes[0, 1:]:
        ax.plot([profile_x[0], profile_x[-1]], [profile_y, profile_y],
                color="#00d5ff", linewidth=1.2, linestyle="--")

    output = ROOT / "interpolation_comparison.png"
    fig.savefig(output, dpi=180, facecolor="white")
    plt.close(fig)
    print(f"Image: {output}")
    print(f"Input chart: {ROOT / 'input_chart_640x640.png'}")
    print(f"Differing pixels: {np.count_nonzero(changed)}/{difference.size} ({changed_pct:.2f}%)")
    print(f"Mean absolute RGB channel difference: {mae:.3f}/255")
    print(f"Maximum channel difference: {int(np.max(np.abs(bilinear.astype(np.int16) - bicubic.astype(np.int16))))}/255")


if __name__ == "__main__":
    main()
