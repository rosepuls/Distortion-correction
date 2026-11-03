"""Generate constant case tables for PDS synthesis from deployed SR hex data."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
WEIGHTS = ROOT / "fpga/project/stage12_1080p60_cnn_sr_v2_test/source/rtl/sr/weights"

TABLES: dict[str, list[tuple[str, str, int]]] = {
    "sr_stem_rom_cases.vh": [
        ("SR_STEM_WEIGHT_CASES", "stem_weights_s8.hex", 8),
        ("SR_STEM_BIAS_CASES", "stem_bias_s32.hex", 32),
        ("SR_STEM_REQUANT_MULT_CASES", "stem_requant_q31.hex", 32),
        ("SR_STEM_REQUANT_SHIFT_CASES", "stem_requant_shift.hex", 8),
    ],
    "sr_block1_depthwise_rom_cases.vh": [
        ("SR_BLOCK1_DW_WEIGHT_CASES", "block1_depthwise_weights_s8.hex", 8),
        ("SR_BLOCK1_DW_BIAS_CASES", "block1_depthwise_bias_s32.hex", 32),
        ("SR_BLOCK1_DW_REQUANT_MULT_CASES", "block1_depthwise_requant_q31.hex", 32),
        ("SR_BLOCK1_DW_REQUANT_SHIFT_CASES", "block1_depthwise_requant_shift.hex", 8),
    ],
    "sr_block1_pointwise_rom_cases.vh": [
        ("SR_BLOCK1_PW_WEIGHT_CASES", "block1_pointwise_weights_s8.hex", 8),
        ("SR_BLOCK1_PW_BIAS_CASES", "block1_pointwise_bias_s32.hex", 32),
        ("SR_BLOCK1_PW_REQUANT_MULT_CASES", "block1_pointwise_requant_q31.hex", 32),
        ("SR_BLOCK1_PW_REQUANT_SHIFT_CASES", "block1_pointwise_requant_shift.hex", 8),
    ],
    "sr_block2_depthwise_rom_cases.vh": [
        ("SR_BLOCK2_DW_WEIGHT_CASES", "block2_depthwise_weights_s8.hex", 8),
        ("SR_BLOCK2_DW_BIAS_CASES", "block2_depthwise_bias_s32.hex", 32),
        ("SR_BLOCK2_DW_REQUANT_MULT_CASES", "block2_depthwise_requant_q31.hex", 32),
        ("SR_BLOCK2_DW_REQUANT_SHIFT_CASES", "block2_depthwise_requant_shift.hex", 8),
    ],
    "sr_block2_pointwise_rom_cases.vh": [
        ("SR_BLOCK2_PW_WEIGHT_CASES", "block2_pointwise_weights_s8.hex", 8),
        ("SR_BLOCK2_PW_BIAS_CASES", "block2_pointwise_bias_s32.hex", 32),
        ("SR_BLOCK2_PW_REQUANT_MULT_CASES", "block2_pointwise_requant_q31.hex", 32),
        ("SR_BLOCK2_PW_REQUANT_SHIFT_CASES", "block2_pointwise_requant_shift.hex", 8),
    ],
    "sr_phase_head_rom_cases.vh": [
        ("SR_PHASE_WEIGHT_CASES", "phase_head_weights_s8.hex", 8),
        ("SR_PHASE_BIAS_CASES", "phase_head_bias_s32.hex", 32),
        ("SR_PHASE_REQUANT_MULT_CASES", "phase_head_requant_q31.hex", 32),
        ("SR_PHASE_REQUANT_SHIFT_CASES", "phase_head_requant_shift.hex", 8),
    ],
    "sr_join_rom_cases.vh": [
        ("SR_BLOCK1_JOIN_CASES", "block1_join_constants.hex", 32),
        ("SR_BLOCK2_JOIN_CASES", "block2_join_constants.hex", 32),
    ],
}


def render_table(macro: str, filename: str, width: int) -> list[str]:
    values = [int(line, 16) for line in (WEIGHTS / filename).read_text(encoding="ascii").splitlines()]
    if not values:
        raise ValueError(f"empty source ROM: {filename}")
    if any(value < 0 or value >= (1 << width) for value in values):
        raise ValueError(f"value exceeds {width}-bit ROM width: {filename}")
    lines = [f"`define {macro} \\"]
    for address, value in enumerate(values):
        suffix = " \\" if address != len(values) - 1 else ""
        lines.append(f"    {address}: rom_value = {width}'h{value:0{width // 4}x};{suffix}")
    return lines


def render_header(tables: list[tuple[str, str, int]]) -> str:
    output: list[str] = []
    for index, (macro, filename, width) in enumerate(tables):
        if index:
            output.append("")
        output.extend(render_table(macro, filename, width))
    return "\n".join(output) + "\n"


def render_join_header() -> str:
    output: list[str] = []
    for block_index, block in enumerate(("block1", "block2")):
        if block_index:
            output.append("")
        macro = f"SR_{block.upper()}_JOIN_CASES"
        values = [int(line, 16) for line in (WEIGHTS / f"{block}_join_constants.hex").read_text(encoding="ascii").splitlines()]
        if len(values) != 4:
            raise ValueError(f"{block} join constants must contain four words")
        output.append(f"`define {macro} \\")
        widths = (32, 8, 32, 8)
        for address, (value, width) in enumerate(zip(values, widths)):
            suffix = " \\" if address != len(values) - 1 else ""
            output.append(f"    {block_index * 4 + address}: rom_value = {width}'h{value:0{width // 4}x};{suffix}")
    return "\n".join(output) + "\n"


def expected_headers() -> dict[str, str]:
    result = {name: render_header(tables) for name, tables in TABLES.items() if name != "sr_join_rom_cases.vh"}
    result["sr_join_rom_cases.vh"] = render_join_header()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated headers differ from source hex")
    args = parser.parse_args()
    failed = False
    for name, content in expected_headers().items():
        path = WEIGHTS / name
        if args.check:
            if not path.is_file() or path.read_text(encoding="ascii") != content:
                print(f"ROM case header is stale or missing: {path}", file=sys.stderr)
                failed = True
        else:
            path.write_text(content, encoding="ascii", newline="\n")
            print(f"wrote {path.name}")
    if args.check and not failed:
        print("PASS: generated SR ROM case tables match all deployed hex files")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
