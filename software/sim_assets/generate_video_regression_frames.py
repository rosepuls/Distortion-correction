"""Generate distinct 720p RGB888 frames and matching optimized-Q18 goldens."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


SOFTWARE_DIR = Path(__file__).resolve().parents[1]
if str(SOFTWARE_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_DIR))

from distortion_float import CameraModel
from bitaccurate_distortion import FixedPointCameraModel, bilinear_remap_fixed
from generate_distorted_input import inverse_distortion_map
from generate_distortion_vectors import (
    build_distortion_map_optimized_q18,
)
from image_to_mem import rgb888_mem_words


PALETTE = np.asarray(
    (
        (8, 12, 24),
        (224, 48, 48),
        (32, 192, 80),
        (48, 96, 224),
        (224, 176, 32),
        (32, 192, 208),
        (192, 48, 208),
        (236, 236, 236),
    ),
    dtype=np.uint8,
)


def write_mem(path: Path, pixels: np.ndarray) -> None:
    """Write one raster-ordered RGB888 word per line for ``$readmemh``."""

    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.fromarray(pixels, mode="RGB")
    path.write_text("\n".join(rgb888_mem_words(image)) + "\n", encoding="ascii")


def make_clean_frame(width: int, height: int, frame_index: int) -> np.ndarray:
    """Create a moving color pattern with a five-bit frame marker."""

    y, x = np.indices((height, width), dtype=np.int32)
    tile_x = (x // 80 + frame_index) % len(PALETTE)
    tile_y = (y // 80) % len(PALETTE)
    frame = PALETTE[(tile_x + 3 * tile_y) % len(PALETTE)].copy()

    block_width = 192
    block_height = 112
    block_x = 24 + ((frame_index * 37) % (width - block_width - 48))
    block_y = 96 + ((frame_index * 19) % (height - block_height - 120))
    block_color = PALETTE[(frame_index + 3) % len(PALETTE)]
    frame[block_y : block_y + block_height, block_x : block_x + block_width] = block_color

    # Encode the frame index as five high-contrast bars in the top-left area.
    frame[20:68, 20:36] = 0
    for bit in range(5):
        color = 255 if ((frame_index >> bit) & 1) else 24
        frame[20:68, 44 + bit * 24 : 60 + bit * 24] = color

    # Keep the marker visually obvious after distortion and correction.
    frame[72:80, 20:180] = np.asarray((255, 255, 255), dtype=np.uint8)
    return frame


def generate_frames(frame_count: int, width: int, height: int, output_directory: Path) -> None:
    camera = CameraModel(
        fx=600.0,
        fy=600.0,
        cx=(width - 1) / 2.0,
        cy=(height - 1) / 2.0,
        k1=-0.25,
        k2=0.05,
        p1=0.001,
        p2=-0.001,
    )
    fixed_camera = FixedPointCameraModel.from_camera_model(camera)
    inverse_x, inverse_y = inverse_distortion_map(width, height, camera)
    correction_x, correction_y = build_distortion_map_optimized_q18(
        width, height, fixed_camera
    )

    output_directory.mkdir(parents=True, exist_ok=True)
    for frame_index in range(frame_count):
        clean = make_clean_frame(width, height, frame_index)
        distorted = bilinear_remap_fixed(clean, inverse_x, inverse_y)
        golden = bilinear_remap_fixed(distorted, correction_x, correction_y)

        write_mem(
            output_directory / f"input_frame_{frame_index:02d}.mem",
            distorted,
        )
        write_mem(
            output_directory / f"golden_frame_{frame_index:02d}.mem",
            golden,
        )
        if frame_index in (0, frame_count // 2, frame_count - 1):
            Image.fromarray(clean, mode="RGB").save(
                output_directory / f"clean_preview_frame_{frame_index:02d}.png"
            )
            Image.fromarray(distorted, mode="RGB").save(
                output_directory / f"input_preview_frame_{frame_index:02d}.png"
            )
            Image.fromarray(golden, mode="RGB").save(
                output_directory / f"golden_preview_frame_{frame_index:02d}.png"
            )
        print(f"Generated frame {frame_index + 1}/{frame_count}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frame-count", type=int, default=30)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--output-directory", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.frame_count <= 0 or arguments.width <= 1 or arguments.height <= 1:
        raise ValueError("frame-count, width and height must be positive")
    generate_frames(
        arguments.frame_count,
        arguments.width,
        arguments.height,
        arguments.output_directory,
    )
    print(
        f"Generated {arguments.frame_count} RGB888 frames and goldens: "
        f"{arguments.width}x{arguments.height}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
