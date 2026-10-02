"""Deterministic source-pixel cache models for the pixel-fetch study.

The model deliberately works in logical RGB888 pixels.  It estimates the
number of source pixels and row bursts loaded from DDR for a single-region
cache; physical byte packing and DDR controller scheduling remain board-layer
concerns.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence

from address_trace_model import BilinearAddressRequest


RGB_BYTES_PER_PIXEL = 3


@dataclass(frozen=True)
class CacheConfig:
    name: str
    tile_width: int
    tile_height: int
    burst_length: int
    set_count: int = 1
    ways: int = 1
    pixel_bytes: int = RGB_BYTES_PER_PIXEL
    burst_beats: int = 1
    set_hash: str = "linear"


@dataclass(frozen=True)
class CacheMetrics:
    policy: str
    output_requests: int
    source_pixel_requests: int
    cache_hits: int
    cache_misses: int
    cache_hit_rate: float
    ddr_read_pixels: int
    ddr_read_bytes: int
    ddr_bursts: int
    ddr_beats: int
    average_burst_length: float
    average_burst_beats: float
    cache_capacity_pixels: int


NO_CACHE = CacheConfig("no_cache", 1, 1, 1)
ROW_WINDOW = CacheConfig("row_window", 4, 2, 4)
TILE_16X4 = CacheConfig("tile_16x4", 16, 4, 16)


def _validate_dimensions(width: int, height: int) -> None:
    if isinstance(width, bool) or isinstance(height, bool):
        raise TypeError("width and height must be integers")
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")


def _validate_config(config: CacheConfig) -> None:
    if not config.name:
        raise ValueError("cache policy name must not be empty")
    if config.tile_width <= 0 or config.tile_height <= 0:
        raise ValueError("cache tile dimensions must be positive")
    if config.burst_length <= 0:
        raise ValueError("burst_length must be positive")
    if config.set_count <= 0:
        raise ValueError("set_count must be positive")
    if config.ways <= 0:
        raise ValueError("ways must be positive")
    if config.pixel_bytes <= 0:
        raise ValueError("pixel_bytes must be positive")
    if config.burst_beats <= 0:
        raise ValueError("burst_beats must be positive")
    if config.set_hash not in {"linear", "skewed_x_minus_y"}:
        raise ValueError("set_hash must be linear or skewed_x_minus_y")


def _aligned_origin(coordinate: int, tile_size: int) -> int:
    return (coordinate // tile_size) * tile_size


def _tile_key(x: int, y: int, config: CacheConfig) -> tuple[int, int]:
    return (
        _aligned_origin(x, config.tile_width),
        _aligned_origin(y, config.tile_height),
    )


def _tile_load_cost(
    origin_x: int,
    origin_y: int,
    width: int,
    height: int,
    config: CacheConfig,
) -> tuple[int, int]:
    """Return in-bounds pixels and row bursts loaded for one aligned tile."""

    loaded_pixels = 0
    bursts = 0
    for row in range(origin_y, min(origin_y + config.tile_height, height)):
        del row
        row_pixels = max(0, min(origin_x + config.tile_width, width) - origin_x)
        loaded_pixels += row_pixels
        if row_pixels:
            bursts += math.ceil(row_pixels / config.burst_length)
    return loaded_pixels, bursts


def _neighbor_coordinates(request: BilinearAddressRequest) -> tuple[tuple[int, int], ...]:
    return (
        (request.x0, request.y0),
        (request.x0 + 1, request.y0),
        (request.x0, request.y0 + 1),
        (request.x0 + 1, request.y0 + 1),
    )


def _set_index(
    tile: tuple[int, int],
    width: int,
    config: CacheConfig,
) -> int:
    tiles_per_row = max(1, math.ceil(width / config.tile_width))
    tile_x = tile[0] // config.tile_width
    tile_y = tile[1] // config.tile_height
    if config.set_hash == "linear":
        raw_index = tile_y * tiles_per_row + tile_x
    else:
        raw_index = tile_x - tile_y + (tile_x >> 2)
    return raw_index % config.set_count


def simulate_cache(
    requests: Sequence[BilinearAddressRequest],
    width: int,
    height: int,
    config: CacheConfig,
) -> CacheMetrics:
    """Estimate cache reuse and DDR row-burst traffic for bilinear requests.

    The cache holds one aligned region at a time.  A source pixel is a hit when
    its aligned region is resident; a miss loads the complete in-bounds region
    and evicts the previous one.  This intentionally conservative policy makes
    the comparison deterministic and keeps capacity accounting explicit.
    """

    _validate_dimensions(width, height)
    _validate_config(config)

    source_pixel_requests = 0
    cache_hits = 0
    cache_misses = 0
    ddr_read_pixels = 0
    ddr_bursts = 0
    resident_sets: list[dict[tuple[int, int], None]] = [
        {} for _ in range(config.set_count)
    ]
    ddr_beats = 0

    for request in requests:
        for x, y in _neighbor_coordinates(request):
            if not (0 <= x < width and 0 <= y < height):
                raise ValueError("requests must contain in-bounds source neighbors")

            source_pixel_requests += 1
            tile = _tile_key(x, y, config)
            set_index = _set_index(tile, width, config)
            resident_set = resident_sets[set_index]
            if config.name != NO_CACHE.name and tile in resident_set:
                cache_hits += 1
                resident_set.pop(tile)
                resident_set[tile] = None
                continue

            cache_misses += 1
            loaded_pixels, bursts = _tile_load_cost(
                tile[0], tile[1], width, height, config
            )
            ddr_read_pixels += loaded_pixels
            ddr_bursts += bursts
            ddr_beats += bursts * config.burst_beats
            if config.name != NO_CACHE.name:
                resident_set.pop(tile, None)
                resident_set[tile] = None
                while len(resident_set) > config.ways:
                    oldest_tile = next(iter(resident_set))
                    resident_set.pop(oldest_tile)

    cache_hit_rate = (
        float(cache_hits) / float(source_pixel_requests)
        if source_pixel_requests
        else 0.0
    )
    average_burst_length = (
        float(ddr_read_pixels) / float(ddr_bursts) if ddr_bursts else 0.0
    )
    average_burst_beats = (
        float(ddr_beats) / float(ddr_bursts) if ddr_bursts else 0.0
    )

    return CacheMetrics(
        policy=config.name,
        output_requests=len(requests),
        source_pixel_requests=source_pixel_requests,
        cache_hits=cache_hits,
        cache_misses=cache_misses,
        cache_hit_rate=cache_hit_rate,
        ddr_read_pixels=ddr_read_pixels,
        ddr_read_bytes=ddr_read_pixels * config.pixel_bytes,
        ddr_bursts=ddr_bursts,
        ddr_beats=ddr_beats,
        average_burst_length=average_burst_length,
        average_burst_beats=average_burst_beats,
        cache_capacity_pixels=(
            config.tile_width
            * config.tile_height
            * config.set_count
            * config.ways
        ),
    )
