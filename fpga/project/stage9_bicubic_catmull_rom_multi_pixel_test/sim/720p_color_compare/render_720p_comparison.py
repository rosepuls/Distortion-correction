from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
WIDTH, HEIGHT = 1280, 720


def load_hex_capture(path: Path) -> np.ndarray:
    raw = path.read_bytes().replace(b"\r", b"").replace(b"\n", b"").strip()
    if len(raw) != WIDTH * HEIGHT * 6:
        raise ValueError(f"{path.name}: expected {WIDTH * HEIGHT} RGB words, found {len(raw) // 6}")
    pixels = np.frombuffer(bytes.fromhex(raw.decode("ascii")), dtype=np.uint8)
    return pixels.reshape(HEIGHT, WIDTH, 3).copy()


def main() -> None:
    OUT.mkdir(exist_ok=True)
    source = np.asarray(Image.open(ROOT / "input_chart_1280x720.png").convert("RGB"))
    bilinear = load_hex_capture(OUT / "stage8_bilinear.hex")
    bicubic = load_hex_capture(OUT / "stage9_catmull_rom.hex")
    delta = np.abs(bilinear.astype(np.int16) - bicubic.astype(np.int16))
    diff = delta.max(axis=2)
    changed = diff > 0
    changed_pct = float(changed.mean() * 100)
    mae = float(delta.mean())
    maximum = int(delta.max())

    Image.fromarray(bilinear, "RGB").save(OUT / "stage8_bilinear_1280x720.png")
    Image.fromarray(bicubic, "RGB").save(OUT / "stage9_catmull_rom_1280x720.png")
    diff_scale = np.minimum((diff.astype(np.uint16) * 5), 255).astype(np.uint8)
    diff_rgb = np.stack((diff_scale, np.minimum(diff_scale * 3, 255), 255 - diff_scale), axis=2)
    Image.fromarray(diff_rgb, "RGB").save(OUT / "difference_x5_1280x720.png")

    fig, axes = plt.subplots(2, 3, figsize=(15.5, 10), layout="constrained")
    fig.suptitle("720p FPGA RTL interpolation comparison", fontsize=16, fontweight="bold")
    fig.text(
        0.5, 0.955,
        f"Same RGB input, source (x+0.5, y+0.5)  ·  changed {changed_pct:.2f}%  ·  "
        f"mean |RGB delta| {mae:.2f}/255  ·  max {maximum}/255",
        ha="center", fontsize=10,
    )
    top = [
        (source, "Input chart · 1280×720"),
        (bilinear, "Stage 8 · bilinear RTL"),
        (bicubic, "Stage 9 · Catmull–Rom RTL"),
    ]
    for ax, (data, title) in zip(axes[0], top):
        ax.imshow(data, interpolation="nearest")
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_aspect("equal")
        ax.add_patch(plt.Rectangle((48, 48), 64, 64, fill=False,
                                   edgecolor="white", linewidth=1.3))

    crop = np.s_[48:112, 48:112]
    bilinear_crop = bilinear[crop]
    bicubic_crop = bicubic[crop]
    diff_crop = diff[crop]
    axes[1, 0].imshow(bilinear_crop, interpolation="nearest")
    axes[1, 0].set_title("Bilinear · checker detail")
    axes[1, 1].imshow(bicubic_crop, interpolation="nearest")
    axes[1, 1].set_title("Catmull–Rom · same detail")
    image = axes[1, 2].imshow(diff_crop, cmap="turbo", vmin=0, vmax=max(1, maximum), interpolation="nearest")
    axes[1, 2].set_title("Max RGB channel difference · local crop")
    fig.colorbar(image, ax=axes[1, 2], label=f"absolute channel difference (0–{maximum})")
    for ax in axes[1]:
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_aspect("equal")

    fig.savefig(OUT / "720p_interpolation_comparison.png", dpi=150, facecolor="white")
    plt.close(fig)

    print(f"Figure: {OUT / '720p_interpolation_comparison.png'}")
    print(f"Bilinear output: {OUT / 'stage8_bilinear_1280x720.png'}")
    print(f"Catmull-Rom output: {OUT / 'stage9_catmull_rom_1280x720.png'}")
    print(f"Difference x5: {OUT / 'difference_x5_1280x720.png'}")
    print(f"Changed pixels: {np.count_nonzero(changed)}/{diff.size} ({changed_pct:.3f}%)")
    print(f"Mean absolute RGB-channel difference: {mae:.4f}/255; max={maximum}/255")


if __name__ == "__main__":
    main()
