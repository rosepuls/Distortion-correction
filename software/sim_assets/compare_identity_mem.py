"""Compare an RTL identity-remap memory image against its RGB888 source image."""

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


def compare_identity_frame(
    source_words: Sequence[str],
    rtl_words: Sequence[str],
    *,
    width: int,
    height: int,
    frame_stride_pixels: int | None = None,
) -> list[tuple[int, int, str, str]]:
    """Return mismatches for an identity map with the project's black border."""

    if width <= 1 or height <= 1:
        raise ValueError("width and height must both be greater than one")
    stride = width if frame_stride_pixels is None else frame_stride_pixels
    if stride < width:
        raise ValueError("frame_stride_pixels must be greater than or equal to width")

    source = _normalise_words(source_words)
    rtl = _normalise_words(rtl_words)
    required_source_words = stride * height
    required_rtl_words = width * height
    if len(source) < required_source_words:
        raise ValueError("source memory image is shorter than its declared dimensions")
    if len(rtl) != required_rtl_words:
        raise ValueError("RTL output memory image does not contain exactly width * height words")

    mismatches: list[tuple[int, int, str, str]] = []
    for y in range(height):
        for x in range(width):
            expected = source[y * stride + x] if x < width - 1 and y < height - 1 else "000000"
            actual = rtl[y * width + x]
            if actual != expected:
                mismatches.append((x, y, expected, actual))
    return mismatches


def _read_mem(path: Path) -> list[str]:
    return path.read_text(encoding="ascii").splitlines()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_mem", type=Path)
    parser.add_argument("rtl_mem", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frame-stride-pixels", type=int, default=None)
    arguments = parser.parse_args()

    mismatches = compare_identity_frame(
        _read_mem(arguments.source_mem),
        _read_mem(arguments.rtl_mem),
        width=arguments.width,
        height=arguments.height,
        frame_stride_pixels=arguments.frame_stride_pixels,
    )
    if mismatches:
        for x, y, expected, actual in mismatches[:20]:
            print(f"MISMATCH x={x} y={y}: expected={expected} actual={actual}")
        print(f"FAIL: {len(mismatches)} identity-image mismatches")
        return 1

    print("TEST_PASS: pixel_fetch_image_identity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
