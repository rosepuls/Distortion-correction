"""RGBX8888 DDR address, Tile-row burst, and frame traffic models."""

from __future__ import annotations

from dataclasses import dataclass
import math


BYTES_PER_PIXEL = 4
BYTES_PER_BEAT = 32
PIXELS_PER_BEAT = BYTES_PER_BEAT // BYTES_PER_PIXEL
TILE_WIDTH = 32
TILE_HEIGHT = 4


@dataclass(frozen=True)
class TrafficTotals:
    """Per-frame traffic fields and the resulting frame-rate bandwidth."""

    input_bytes: int
    source_bytes: int
    output_bytes: int
    display_bytes: int
    total_bytes: int
    bytes_per_second: int


def _validate_dimensions(width: int, height: int) -> None:
    if isinstance(width, bool) or isinstance(height, bool):
        raise TypeError("width and height must be integers")
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")


def _validate_frame_base(frame_base_byte: int) -> None:
    if isinstance(frame_base_byte, bool) or frame_base_byte < 0:
        raise ValueError("frame_base_byte must be non-negative")
    if frame_base_byte % BYTES_PER_BEAT:
        raise ValueError("frame_base_byte must be 32-byte aligned")


def rgbx_pixel_byte_address(
    x: int,
    y: int,
    width: int,
    frame_base_byte: int = 0,
) -> int:
    """Return the byte address of one in-bounds RGBX8888 pixel."""

    _validate_dimensions(width, 1)
    _validate_frame_base(frame_base_byte)
    if x < 0 or y < 0:
        raise ValueError("pixel coordinates must be non-negative")
    if x >= width:
        raise ValueError("x must be inside the image width")
    return frame_base_byte + ((y * width + x) * BYTES_PER_PIXEL)


def tile_row_bursts(
    tile_x: int,
    tile_y: int,
    width: int,
    height: int,
    frame_base_byte: int = 0,
) -> tuple[tuple[int, int], ...]:
    """Return aligned ``(byte_address, beat_count)`` bursts for one Tile.

    ``tile_x`` and ``tile_y`` are Tile indices.  A full 32×4 Tile produces
    four row bursts, each containing four 256-bit beats.  Edge Tiles contain
    only the in-bounds rows and beats.
    """

    _validate_dimensions(width, height)
    _validate_frame_base(frame_base_byte)
    if tile_x < 0 or tile_y < 0:
        raise ValueError("Tile coordinates must be non-negative")

    origin_x = tile_x * TILE_WIDTH
    origin_y = tile_y * TILE_HEIGHT
    valid_width = max(0, min(TILE_WIDTH, width - origin_x))
    valid_height = max(0, min(TILE_HEIGHT, height - origin_y))
    if valid_width == 0 or valid_height == 0:
        return ()

    beat_count = math.ceil(valid_width / PIXELS_PER_BEAT)
    return tuple(
        (
            frame_base_byte
            + ((origin_y + row) * width + origin_x) * BYTES_PER_PIXEL,
            beat_count,
        )
        for row in range(valid_height)
    )


def frame_traffic_totals(
    width: int,
    height: int,
    fps: int,
    *,
    source_bytes: int | None = None,
) -> TrafficTotals:
    """Return input/source/output/display traffic for one RGBX frame rate.

    By default the source stream is one full RGBX frame, producing the
    four-stream baseline used by the 1080P30 architecture report.  A measured
    or modeled cache-fill total can be supplied through ``source_bytes``.
    """

    _validate_dimensions(width, height)
    if isinstance(fps, bool) or fps <= 0:
        raise ValueError("fps must be positive")
    frame_bytes = width * height * BYTES_PER_PIXEL
    if source_bytes is None:
        source_bytes = frame_bytes
    if source_bytes < 0:
        raise ValueError("source_bytes must be non-negative")

    total_bytes = frame_bytes * 3 + source_bytes
    return TrafficTotals(
        input_bytes=frame_bytes,
        source_bytes=source_bytes,
        output_bytes=frame_bytes,
        display_bytes=frame_bytes,
        total_bytes=total_bytes,
        bytes_per_second=total_bytes * fps,
    )
