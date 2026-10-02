"""Compare two same-sized raster RGB888 ``.mem`` frame files."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence


def _normalise_words(words: Sequence[str]) -> list[str]:
    normalised = [word.strip().upper() for word in words if word.strip()]
    for word in normalised:
        if len(word) != 6 or any(character not in "0123456789ABCDEF" for character in word):
            raise ValueError(f"invalid RGB888 memory word: {word!r}")
    return normalised


def compare_rgb888_frames(
    expected_words: Sequence[str], actual_words: Sequence[str], *, width: int, height: int
) -> list[tuple[int, int, str, str]]:
    """Return ``(x, y, expected, actual)`` for each differing pixel."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")
    expected = _normalise_words(expected_words)
    actual = _normalise_words(actual_words)
    pixel_count = width * height
    if len(expected) != pixel_count:
        raise ValueError(f"expected frame has {len(expected)} words; expected {pixel_count}")
    if len(actual) != pixel_count:
        raise ValueError(f"actual frame has {len(actual)} words; expected {pixel_count}")

    return [
        (index % width, index // width, expected_word, actual_word)
        for index, (expected_word, actual_word) in enumerate(zip(expected, actual))
        if expected_word != actual_word
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected_mem", type=Path)
    parser.add_argument("actual_mem", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    arguments = parser.parse_args()

    mismatches = compare_rgb888_frames(
        arguments.expected_mem.read_text(encoding="ascii").splitlines(),
        arguments.actual_mem.read_text(encoding="ascii").splitlines(),
        width=arguments.width,
        height=arguments.height,
    )
    if mismatches:
        for x, y, expected, actual in mismatches[:20]:
            print(f"MISMATCH x={x} y={y} expected={expected} actual={actual}")
        print(f"FAIL: {len(mismatches)} RGB888 pixels differ")
        return 1

    print(f"PASS: RGB888 frames match ({arguments.width}x{arguments.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
