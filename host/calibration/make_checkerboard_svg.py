"""Create a millimeter-sized printable chessboard SVG (no extra packages)."""

from __future__ import annotations

import argparse
import math
from pathlib import Path


def positive(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return number


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cols", type=int, default=9, help="inner corners across")
    parser.add_argument("--rows", type=int, default=6, help="inner corners down")
    parser.add_argument("--square-mm", type=positive, default=25.0)
    parser.add_argument("--page-width-mm", type=positive, default=297.0)
    parser.add_argument("--page-height-mm", type=positive, default=210.0)
    parser.add_argument("--margin-mm", type=positive, default=8.0)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.cols < 3 or args.rows < 3:
        parser.error("at least 3 inner corners per direction are required")
    board_width = (args.cols + 1) * args.square_mm
    board_height = (args.rows + 1) * args.square_mm
    if (board_width + 2 * args.margin_mm > args.page_width_mm
            or board_height + 2 * args.margin_mm > args.page_height_mm):
        parser.error("board and margins do not fit the specified page")
    left = (args.page_width_mm - board_width) / 2
    top = (args.page_height_mm - board_height) / 2
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{args.page_width_mm:g}mm" '
        f'height="{args.page_height_mm:g}mm" '
        f'viewBox="0 0 {args.page_width_mm:g} {args.page_height_mm:g}">',
        f'<rect width="{args.page_width_mm:g}" height="{args.page_height_mm:g}" fill="white"/>',
    ]
    for row in range(args.rows + 1):
        for col in range(args.cols + 1):
            if (row + col) % 2 == 0:
                x = left + col * args.square_mm
                y = top + row * args.square_mm
                lines.append(
                    f'<rect x="{x:g}" y="{y:g}" width="{args.square_mm:g}" '
                    f'height="{args.square_mm:g}" fill="black"/>'
                )
    lines.append("</svg>")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        f"Saved {args.out}: {args.cols}x{args.rows} inner corners, "
        f"{args.square_mm:g} mm squares, board {board_width:g}x{board_height:g} mm"
    )


if __name__ == "__main__":
    main()
