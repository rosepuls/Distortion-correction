from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1280, 720


def make_chart() -> np.ndarray:
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH]
    image = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)

    # Upper left: saturated 4-pixel checker cells for a visible edge stress test.
    mask = (x < 640) & (y < 360)
    checker = ((x // 4 + y // 4) & 1) != 0
    image[mask & ~checker] = (24, 78, 220)
    image[mask & checker] = (245, 210, 32)

    # Upper right: narrow colored bars, useful for comparing edge transitions.
    mask = (x >= 640) & (y < 360)
    bar = ((x - 640) // 8) % 6
    colors = np.array([
        (235, 45, 35), (35, 210, 235), (245, 205, 30),
        (35, 205, 90), (185, 55, 220), (245, 245, 245),
    ], dtype=np.uint8)
    image[mask] = colors[bar[mask]]

    # Lower left: colored diagonal step edge over a smooth color field.
    mask = (x < 640) & (y >= 360)
    xx, yy = x.astype(np.int32), y.astype(np.int32)
    ramp = np.stack((
        35 + ((xx * 180) // 639),
        35 + (((yy - 360) * 180) // 359),
        220 - (((xx + yy - 360) * 120) // 998),
    ), axis=2).clip(0, 255).astype(np.uint8)
    image[mask] = ramp[mask]
    diagonal = (x < 640) & (y >= 360) & (x > ((y - 360) * 5 // 3 + 90))
    image[diagonal] = (20, 25, 40)

    # Lower right: hard color edges, nested squares, and fine one-pixel lines.
    mask = (x >= 640) & (y >= 360)
    local_x, local_y = x - 640, y - 360
    image[mask] = (235, 235, 235)
    image[mask & (local_x >= 320)] = (24, 28, 42)
    image[mask & (local_y >= 180)] = (25, 105, 215)
    image[mask & (local_x >= 320) & (local_y >= 180)] = (230, 45, 130)
    # Narrow white/cyan lines stress the one-pixel transition response.
    image[mask & ((local_x % 32) == 0)] = (255, 255, 255)
    image[mask & ((local_y % 24) == 0)] = (25, 245, 225)

    # Clear color separators between test regions.
    image[358:362, :] = (255, 255, 255)
    image[:, 638:642] = (255, 255, 255)
    return image


def main() -> None:
    rgb = make_chart()
    Image.fromarray(rgb, "RGB").save(ROOT / "input_chart_1280x720.png")
    Image.fromarray(rgb, "RGB").save(ROOT / "input_chart_1280x720.bmp")
    # One 6-hex-digit RGB word per row for $readmemh in the RTL testbench.
    with (ROOT / "source_rgb.mem").open("w", encoding="ascii", newline="\n") as stream:
        for row in rgb:
            stream.writelines(f"{r:02x}{g:02x}{b:02x}\n" for r, g, b in row)
    print(f"Input chart: {ROOT / 'input_chart_1280x720.png'} ({WIDTH}x{HEIGHT}, RGB)")
    print(f"RTL memory:  {ROOT / 'source_rgb.mem'}")


if __name__ == "__main__":
    main()
