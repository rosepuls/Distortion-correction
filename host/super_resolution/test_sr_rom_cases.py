"""Check generated synthesizable CNN case ROMs against their source hex tables."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WEIGHTS = ROOT / "fpga/project/stage12_1080p60_cnn_sr_v2_test/source/rtl/sr/weights"

TABLES = {
    "sr_stem_rom_cases.vh": {
        "SR_STEM_WEIGHT_CASES": "stem_weights_s8.hex",
        "SR_STEM_BIAS_CASES": "stem_bias_s32.hex",
        "SR_STEM_REQUANT_MULT_CASES": "stem_requant_q31.hex",
        "SR_STEM_REQUANT_SHIFT_CASES": "stem_requant_shift.hex",
    },
    "sr_block1_depthwise_rom_cases.vh": {
        "SR_BLOCK1_DW_WEIGHT_CASES": "block1_depthwise_weights_s8.hex",
        "SR_BLOCK1_DW_BIAS_CASES": "block1_depthwise_bias_s32.hex",
        "SR_BLOCK1_DW_REQUANT_MULT_CASES": "block1_depthwise_requant_q31.hex",
        "SR_BLOCK1_DW_REQUANT_SHIFT_CASES": "block1_depthwise_requant_shift.hex",
    },
    "sr_block1_pointwise_rom_cases.vh": {
        "SR_BLOCK1_PW_WEIGHT_CASES": "block1_pointwise_weights_s8.hex",
        "SR_BLOCK1_PW_BIAS_CASES": "block1_pointwise_bias_s32.hex",
        "SR_BLOCK1_PW_REQUANT_MULT_CASES": "block1_pointwise_requant_q31.hex",
        "SR_BLOCK1_PW_REQUANT_SHIFT_CASES": "block1_pointwise_requant_shift.hex",
    },
    "sr_block2_depthwise_rom_cases.vh": {
        "SR_BLOCK2_DW_WEIGHT_CASES": "block2_depthwise_weights_s8.hex",
        "SR_BLOCK2_DW_BIAS_CASES": "block2_depthwise_bias_s32.hex",
        "SR_BLOCK2_DW_REQUANT_MULT_CASES": "block2_depthwise_requant_q31.hex",
        "SR_BLOCK2_DW_REQUANT_SHIFT_CASES": "block2_depthwise_requant_shift.hex",
    },
    "sr_block2_pointwise_rom_cases.vh": {
        "SR_BLOCK2_PW_WEIGHT_CASES": "block2_pointwise_weights_s8.hex",
        "SR_BLOCK2_PW_BIAS_CASES": "block2_pointwise_bias_s32.hex",
        "SR_BLOCK2_PW_REQUANT_MULT_CASES": "block2_pointwise_requant_q31.hex",
        "SR_BLOCK2_PW_REQUANT_SHIFT_CASES": "block2_pointwise_requant_shift.hex",
    },
    "sr_phase_head_rom_cases.vh": {
        "SR_PHASE_WEIGHT_CASES": "phase_head_weights_s8.hex",
        "SR_PHASE_BIAS_CASES": "phase_head_bias_s32.hex",
        "SR_PHASE_REQUANT_MULT_CASES": "phase_head_requant_q31.hex",
        "SR_PHASE_REQUANT_SHIFT_CASES": "phase_head_requant_shift.hex",
    },
    "sr_join_rom_cases.vh": {
        "SR_BLOCK1_JOIN_CASES": "block1_join_constants.hex",
        "SR_BLOCK2_JOIN_CASES": "block2_join_constants.hex",
    },
}


class GeneratedRomCaseTest(unittest.TestCase):
    def test_every_generated_case_entry_matches_its_hex_source(self):
        for header_name, macros in TABLES.items():
            header_path = WEIGHTS / header_name
            self.assertTrue(header_path.is_file(), f"missing generated ROM case file: {header_path}")
            header_text = header_path.read_text(encoding="ascii")
            for macro, hex_name in macros.items():
                with self.subTest(header=header_name, macro=macro):
                    match = re.search(
                        rf"`define\s+{re.escape(macro)}\b(.*?)(?=\n`define\s|\Z)",
                        header_text,
                        flags=re.S,
                    )
                    self.assertIsNotNone(match, f"missing macro {macro}")
                    entries = re.findall(r"(\d+)\s*:\s*rom_value\s*=\s*\d+'h([0-9a-fA-F]+)\s*;", match.group(1))
                    actual = [(int(address), int(value, 16)) for address, value in entries]
                    expected = [int(line, 16) for line in (WEIGHTS / hex_name).read_text(encoding="ascii").splitlines()]
                    first_address = 4 if macro == "SR_BLOCK2_JOIN_CASES" else 0
                    self.assertEqual(actual, list(enumerate(expected, first_address)), f"ROM table mismatch for {hex_name}")


if __name__ == "__main__":
    unittest.main()
