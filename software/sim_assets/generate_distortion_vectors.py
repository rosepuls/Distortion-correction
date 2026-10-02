"""Generate RTL coordinate vectors and a fixed-point RGB888 golden frame."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


SOFTWARE_DIR = Path(__file__).resolve().parents[1]
if str(SOFTWARE_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_DIR))

from bitaccurate_distortion import (
    FixedPointCameraModel,
    InternalFormat,
    bilinear_remap_fixed,
    build_distortion_map_fixed,
    source_coordinates_horner_quantized,
    split_source_coordinates,
)
from image_to_mem import rgb888_mem_words


Q18_RTL_FORMAT = InternalFormat(
    centered_width=23,
    centered_frac_bits=12,
    inverse_width=26,
    inverse_frac_bits=24,
    normalized_width=20,
    normalized_frac_bits=18,
    coefficient_width=20,
    coefficient_frac_bits=18,
    radius_width=20,
    radius_frac_bits=18,
    radial_width=21,
    radial_frac_bits=18,
    distorted_width=21,
    distorted_frac_bits=18,
    focal_width=24,
    focal_frac_bits=12,
)


def build_distortion_map_optimized_q18(
    width: int, height: int, camera: FixedPointCameraModel
) -> tuple[np.ndarray, np.ndarray]:
    """Build the exact source-coordinate map used by distortion_core_optimized."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be greater than zero")
    output_y, output_x = np.indices((height, width), dtype=np.int64)
    return source_coordinates_horner_quantized(
        output_x,
        output_y,
        camera,
        Q18_RTL_FORMAT,
    )


def pack_coordinate_word(
    *, x0: int, y0: int, dx_q16: int, dy_q16: int, coord_valid: bool
) -> str:
    """Pack ``coord_valid/x0/y0/dx/dy`` into one 65-bit Verilog memory word."""

    packed = (
        (int(bool(coord_valid)) << 64)
        | ((int(x0) & 0xFFFF) << 48)
        | ((int(y0) & 0xFFFF) << 32)
        | ((int(dx_q16) & 0xFFFF) << 16)
        | (int(dy_q16) & 0xFFFF)
    )
    return f"{packed:017X}"


def coordinate_vector_words(
    source_x: np.ndarray, source_y: np.ndarray, *, width: int, height: int
) -> list[str]:
    """Convert Q13.19 source maps to raster-ordered pixel-fetch input words."""

    x0, y0, dx, dy, valid = split_source_coordinates(
        source_x, source_y, width=width, height=height
    )
    return [
        pack_coordinate_word(
            x0=int(x0.flat[index]),
            y0=int(y0.flat[index]),
            dx_q16=int(dx.flat[index]),
            dy_q16=int(dy.flat[index]),
            coord_valid=bool(valid.flat[index]),
        )
        for index in range(x0.size)
    ]


def write_mem_words(path: Path, words: list[str]) -> None:
    """Write one Verilog memory word per line using deterministic newlines."""

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(words) + "\n", encoding="ascii", newline="\n")


def generate_distortion_artifacts(
    image: Image.Image,
    camera: FixedPointCameraModel,
    *,
    optimized_q18: bool = False,
) -> tuple[list[str], list[str]]:
    """Return packed coordinates and the matching bit-accurate golden pixels."""

    source = np.asarray(image.convert("RGB"), dtype=np.uint8)
    height, width = source.shape[:2]
    if optimized_q18:
        source_x, source_y = build_distortion_map_optimized_q18(width, height, camera)
    else:
        source_x, source_y = build_distortion_map_fixed(width, height, camera)
    coordinates = coordinate_vector_words(source_x, source_y, width=width, height=height)
    golden = bilinear_remap_fixed(source, source_x, source_y)
    golden_image = Image.fromarray(golden, mode="RGB")
    return coordinates, rgb888_mem_words(golden_image)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_image", type=Path, help="RGB source PNG")
    parser.add_argument(
        "--output-prefix",
        type=Path,
        default=Path("result/sim_assets/barrel_256x192"),
        help="prefix for <prefix>_coords.mem and golden_<prefix-name>.mem",
    )
    parser.add_argument("--fx", type=float, default=180.0)
    parser.add_argument("--fy", type=float, default=180.0)
    parser.add_argument("--cx", type=float, default=127.5)
    parser.add_argument("--cy", type=float, default=95.5)
    parser.add_argument("--k1", type=float, default=-0.25)
    parser.add_argument("--k2", type=float, default=0.05)
    parser.add_argument("--p1", type=float, default=0.001)
    parser.add_argument("--p2", type=float, default=-0.001)
    parser.add_argument(
        "--optimized-q18",
        action="store_true",
        help="use the exact narrowed arithmetic of distortion_core_optimized",
    )
    arguments = parser.parse_args()

    camera = FixedPointCameraModel.from_parameters(
        fx=arguments.fx,
        fy=arguments.fy,
        cx=arguments.cx,
        cy=arguments.cy,
        k1=arguments.k1,
        k2=arguments.k2,
        p1=arguments.p1,
        p2=arguments.p2,
    )
    with Image.open(arguments.input_image) as image:
        coordinates, golden = generate_distortion_artifacts(
            image,
            camera,
            optimized_q18=arguments.optimized_q18,
        )

    coords_path = arguments.output_prefix.with_name(arguments.output_prefix.name + "_coords.mem")
    golden_path = arguments.output_prefix.with_name("golden_" + arguments.output_prefix.name + ".mem")
    write_mem_words(coords_path, coordinates)
    write_mem_words(golden_path, golden)
    valid_count = sum(word[0] == "1" for word in coordinates)
    print(f"Created coordinate vectors: {coords_path} ({valid_count}/{len(coordinates)} valid)")
    print(f"Created fixed-point golden frame: {golden_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
