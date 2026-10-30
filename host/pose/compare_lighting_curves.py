"""Render provisional lighting LUT comparisons for captured sample folders."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import sys

import cv2
import numpy as np

from lighting_curves import generate_luts, load_parameters
from lighting_profile import PROFILE_NAMES


SCRIPT_DIR = Path(__file__).resolve().parent


def _luma(frame: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)


def _metrics(source: np.ndarray, enhanced: np.ndarray) -> dict[str, float]:
    source_y = _luma(source)
    output_y = _luma(enhanced)
    dark_mask = source_y <= 64
    highlight_mask = source_y >= 245
    dark_before = float(source_y[dark_mask].mean()) if dark_mask.any() else 0.0
    dark_after = float(output_y[dark_mask].mean()) if dark_mask.any() else 0.0
    highlight_after = float(output_y[highlight_mask].mean()) if highlight_mask.any() else 0.0
    return {
        "source_mean_luma": float(source_y.mean()),
        "output_mean_luma": float(output_y.mean()),
        "source_dark_ratio": float(dark_mask.mean()),
        "dark_mean_before": dark_before,
        "dark_mean_after": dark_after,
        "dark_mean_gain": dark_after - dark_before,
        "source_highlight_ratio": float(highlight_mask.mean()),
        "highlight_mean_after": highlight_after,
        "highlight_clipped_after_ratio": (
            float((output_y[highlight_mask] >= 245).mean()) if highlight_mask.any() else 0.0
        ),
        "output_clipped_ratio": float((output_y >= 250).mean()),
        "mean_absolute_rgb_change": float(
            np.abs(enhanced.astype(np.int16) - source.astype(np.int16)).mean()
        ),
    }


def _thumbnail(frame: np.ndarray, label: str, width: int, height: int) -> np.ndarray:
    thumb = cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)
    header = np.zeros((24, width, 3), dtype=np.uint8)
    cv2.putText(header, label, (5, 17), cv2.FONT_HERSHEY_SIMPLEX,
                0.48, (255, 255, 255), 1, cv2.LINE_AA)
    return np.vstack((header, thumb))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path,
                        default=SCRIPT_DIR / "output" / "lighting_samples",
                        help="sample root with one profile subfolder per category")
    parser.add_argument("--parameters", type=Path,
                        default=SCRIPT_DIR / "lighting_curve_parameters.json",
                        help="editable provisional curve parameter JSON")
    parser.add_argument("--output", type=Path,
                        default=SCRIPT_DIR / "output" / "lighting_curve_comparison",
                        help="comparison output directory")
    parser.add_argument("--tile-width", type=int, default=224,
                        help="contact-sheet thumbnail width (default 224)")
    parser.add_argument("--tile-height", type=int, default=126,
                        help="contact-sheet thumbnail height (default 126)")
    args = parser.parse_args(argv)
    if args.tile_width < 32 or args.tile_height < 32:
        parser.error("thumbnail dimensions must be at least 32 pixels")

    input_root = args.input.expanduser().resolve()
    output_root = args.output.expanduser().resolve()
    config = load_parameters(args.parameters.expanduser().resolve())
    luts = generate_luts(config)
    if not input_root.is_dir():
        raise SystemExit(f"sample directory not found: {input_root}")
    output_root.mkdir(parents=True, exist_ok=True)

    metric_rows: list[dict[str, object]] = []
    total_images = 0
    for source_id, source_name in PROFILE_NAMES.items():
        source_dir = input_root / f"{source_id}_{source_name}"
        image_paths = sorted(source_dir.glob("sample_*.png")) if source_dir.is_dir() else []
        if not image_paths:
            print(f"skip {source_id}:{source_name}: no sample_*.png files")
            continue

        sheet_rows: list[np.ndarray] = []
        for image_path in image_paths:
            source = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
            if source is None:
                raise SystemExit(f"could not read image: {image_path}")
            tiles = [_thumbnail(source, "original", args.tile_width, args.tile_height)]
            for profile_id in PROFILE_NAMES:
                enhanced = cv2.LUT(source, luts[profile_id].reshape(256, 1))
                tiles.append(_thumbnail(enhanced, f"{profile_id}:{PROFILE_NAMES[profile_id]}",
                                        args.tile_width, args.tile_height))
                row: dict[str, object] = {
                    "source_category": source_name,
                    "source_file": image_path.name,
                    "profile_id": profile_id,
                    "profile_name": PROFILE_NAMES[profile_id],
                }
                row.update(_metrics(source, enhanced))
                metric_rows.append(row)
            sheet_rows.append(np.hstack(tiles))
            total_images += 1

        sheet = np.vstack(sheet_rows)
        sheet_path = output_root / f"{source_id}_{source_name}_comparison.png"
        if not cv2.imwrite(str(sheet_path), sheet):
            raise OSError(f"failed to write contact sheet: {sheet_path}")
        print(f"wrote {sheet_path} ({len(image_paths)} source images)")

    if total_images == 0:
        raise SystemExit(f"no sample_*.png images found under {input_root}")

    with (output_root / "metrics.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(metric_rows[0]))
        writer.writeheader()
        writer.writerows(metric_rows)

    lut_export = {
        "schema_version": 1,
        "status": config.get("status", "provisional"),
        "parameters": config["profiles"],
        "tables": {str(profile_id): table.astype(int).tolist()
                   for profile_id, table in luts.items()},
    }
    (output_root / "lighting_luts.json").write_text(
        json.dumps(lut_export, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"processed {total_images} source images; generated {len(metric_rows)} comparisons")
    print(f"results: {output_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
