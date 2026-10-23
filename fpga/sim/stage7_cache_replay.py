"""Replay the Stage 6 RTL's tile indexing and LRU for one coordinate trace.

The trace comes from stage7_cache_trace_tb.sv. Each lookup fetches the first
missing neighbor, retries until all four tiles are present, then applies all
four LRU touches with the RTL's nonblocking assignment ordering.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


class TileCache:
    def __init__(self, sets: int, ways: int) -> None:
        self.sets = sets
        self.ways = ways
        self.tags: list[list[tuple[int, int] | None]] = [
            [None] * ways for _ in range(sets)
        ]
        self.rank = [list(range(ways)) for _ in range(sets)]
        self.misses = 0

    def set_index(self, tile: tuple[int, int]) -> int:
        x, y = tile
        return (x - y + (x >> 2)) & (self.sets - 1)

    def touch_group(self, set_index: int, touched_ways: list[int]) -> None:
        # All touch_lru calls in one RTL clock read the old ranks. Later
        # nonblocking assignments override earlier ones for the same rank.
        old = self.rank[set_index][:]
        scheduled: dict[int, int] = {}
        for touched in touched_ways:
            old_rank = old[touched]
            for way in range(self.ways):
                if way == touched:
                    scheduled[way] = 0
                elif self.tags[set_index][way] is not None and old[way] < old_rank:
                    scheduled[way] = old[way] + 1
        for way, value in scheduled.items():
            self.rank[set_index][way] = value

    def victim(self, set_index: int) -> int:
        worst_rank = max(self.rank[set_index])
        return max(way for way, rank in enumerate(self.rank[set_index]) if rank == worst_rank)

    def lookup(self, tiles: tuple[tuple[int, int], ...]) -> None:
        while True:
            hits_by_set: dict[int, list[int]] = {}
            missing: tuple[int, tuple[int, int]] | None = None
            for tile in tiles:
                set_index = self.set_index(tile)
                try:
                    way = self.tags[set_index].index(tile)
                except ValueError:
                    missing = (set_index, tile)
                    break
                hits_by_set.setdefault(set_index, []).append(way)
            if missing is None:
                for set_index, touched_ways in hits_by_set.items():
                    self.touch_group(set_index, touched_ways)
                return
            set_index, tile = missing
            try:
                way = self.tags[set_index].index(None)
            except ValueError:
                way = self.victim(set_index)
            self.touch_group(set_index, [way])
            self.tags[set_index][way] = tile
            self.misses += 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()
    caches = [TileCache(16, 4), TileCache(16, 8), TileCache(32, 4), TileCache(32, 8)]
    unique_tiles: set[tuple[int, int]] = set()
    pixels = 0
    with args.trace.open(newline="", encoding="ascii") as trace_file:
        for pixel_id, x0, y0, _valid in csv.reader(trace_file):
            if int(pixel_id) != pixels:
                raise ValueError(f"Trace pixel order mismatch at {pixels}")
            x = min(int(x0), 1278)
            y = min(int(y0), 718)
            tiles = (
                (x >> 5, y >> 2),
                ((x + 1) >> 5, y >> 2),
                (x >> 5, (y + 1) >> 2),
                ((x + 1) >> 5, (y + 1) >> 2),
            )
            unique_tiles.update(tiles)
            for cache in caches:
                cache.lookup(tiles)
            pixels += 1
    if pixels != 1280 * 720:
        raise ValueError(f"Expected 921600 pixels, got {pixels}")
    baseline = caches[0].misses
    result = {
        "pixels": pixels,
        "unique_tiles": len(unique_tiles),
        "configurations": [
            {
                "sets": cache.sets,
                "ways": cache.ways,
                "capacity_kib": cache.sets * cache.ways // 2,
                "misses": cache.misses,
                "miss_reduction_percent": round(
                    100 * (baseline - cache.misses) / baseline, 3
                ),
            }
            for cache in caches
        ],
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
