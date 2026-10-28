"""Create bit-exact Stage 8 RTL vectors from exported synthetic poses."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


POINTS = ((0, 0), (1279, 0), (0, 719), (1279, 719), (640, 360), (325, 168))
Q30 = 1 << 30


def reciprocal_seed(address: int) -> int:
    numerator, denominator = 1 << 40, 513 + 2 * address
    quotient, remainder = divmod(numerator, denominator)
    return quotient + (2 * remainder > denominator or
                       (2 * remainder == denominator and quotient & 1))


def signed_round_shift(value: int, bits: int) -> int:
    rounded = (abs(value) + (1 << (bits - 1))) >> bits
    return -rounded if value < 0 else rounded


def expected_coordinate(rows: list[list[int]], u: int, v: int) -> tuple[int, int, int]:
    nx = rows[0][0] * u + rows[0][1] * v + rows[0][2]
    ny = rows[1][0] * u + rows[1][1] * v + rows[1][2]
    d = rows[2][0] * u + rows[2][1] * v + rows[2][2]
    if not ((1 << 29) <= d < (2 << 30) and
            abs(nx) <= (1 << 30) and abs(ny) <= (1 << 30)):
        return 0, 0, 0
    seed = reciprocal_seed((d - (1 << 29)) >> 21)
    dr = (d * seed + (1 << 29)) >> 30
    reciprocal = (seed * ((2 << 30) - dr) + (1 << 29)) >> 30
    if d == Q30:
        reciprocal = Q30
    x = signed_round_shift(nx * reciprocal, 30)
    y = signed_round_shift(ny * reciprocal, 30)
    valid = int(-(1 << 31) <= x < (1 << 31) and
                -(1 << 31) <= y < (1 << 31))
    return (x, y, valid) if valid else (0, 0, 0)


def expected_brown(x: int, y: int, valid: int) -> tuple[int, int, int]:
    dx, dy = x - (640 << 16), y - (360 << 16)
    if abs(dx) > (2048 << 16) or abs(dy) > (2048 << 16):
        return 0, 0, 0
    xx, yy, xy = dx * dx, dy * dy, dx * dy
    radius2_q12 = (xx + yy) >> 38
    gain_q16 = (radius2_q12 * radius2_q12 >> 12) - (radius2_q12 << 2)
    tang_x_q16 = ((xy << 1) - (xx + yy) - (xx << 1)) >> 30
    tang_y_q16 = ((xx + yy) + (yy << 1) - (xy << 1)) >> 30
    mapped_x = x + ((dx * gain_q16) >> 16) + tang_x_q16
    mapped_y = y + ((dy * gain_q16) >> 16) + tang_y_q16
    in_range = (-(1 << 31) <= mapped_x < (1 << 31) and
                -(1 << 31) <= mapped_y < (1 << 31))
    if not in_range:
        return 0, 0, 0
    return mapped_x, mapped_y, valid


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pose_log", type=Path)
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).with_name("homography_reference_vectors.mem"))
    args = parser.parse_args()

    vectors = []
    for line in args.pose_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if not record.get("valid"):
            continue
        rows = record["candidate_fixed_point"]["integer_rows"]
        coefficients = int(record["candidate_fixed_point"]["cfg_words_288bit_hex"], 16)
        for u, v in POINTS:
            x, y, valid = expected_coordinate(rows, u, v)
            brown_x, brown_y, brown_valid = expected_brown(x, y, valid)
            packed = (coefficients | (u << 288) | (v << 299) |
                      ((x & 0xFFFFFFFF) << 309) |
                      ((y & 0xFFFFFFFF) << 341) | (valid << 373) |
                      ((brown_x & 0xFFFFFFFF) << 374) |
                      ((brown_y & 0xFFFFFFFF) << 406) |
                      (brown_valid << 438))
            vectors.append(f"{packed:110x}")
    if len(vectors) != 60:
        raise ValueError(f"Expected 10 valid poses × 6 points, got {len(vectors)}")
    args.out.write_text("\n".join(vectors) + "\n", encoding="ascii")
    print(f"Wrote {len(vectors)} Stage 8 homography vectors to {args.out}")


if __name__ == "__main__":
    main()
