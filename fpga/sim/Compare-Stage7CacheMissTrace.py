"""Compare ordered Stage 7 cache miss events from the model and project RTL."""

from __future__ import annotations

import csv
import sys
from pathlib import Path


FIELDS = ("frame", "tile_x", "tile_y", "set", "victim_way", "miss_index")


def load(path: Path) -> list[tuple[int, ...]]:
    with path.open(newline="", encoding="ascii") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError(f"Unexpected miss-trace header in {path}")
        return [tuple(int(row[field]) for field in FIELDS) for row in reader]


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: Compare-Stage7CacheMissTrace.py MODEL.csv RTL.csv", file=sys.stderr)
        return 2
    model_path, rtl_path = map(Path, sys.argv[1:])
    model, rtl = load(model_path), load(rtl_path)
    common = min(len(model), len(rtl))
    for index in range(common):
        if model[index] != rtl[index]:
            print(
                f"MISMATCH at miss {index}: model={model[index]} rtl={rtl[index]}"
            )
            print(f"event counts: model={len(model)} rtl={len(rtl)}")
            return 1
    if len(model) != len(rtl):
        print(
            f"MISMATCH after {common} matching events: "
            f"model={len(model)} RTL={len(rtl)}"
        )
        return 1
    print(f"MATCH: all {len(model)} ordered 16x8 multi-frame cache miss events agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
