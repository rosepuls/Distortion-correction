from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RTL_ROOT = PROJECT_ROOT / "rtl"
IVERILOG = shutil.which("iverilog")
VVP = shutil.which("vvp")

RTL_SOURCES = [
    RTL_ROOT / "preprocess" / "rgb2gray.sv",
    RTL_ROOT / "preprocess" / "brightness_gain.sv",
    RTL_ROOT / "preprocess" / "gamma_lut.sv",
    RTL_ROOT / "interpolation" / "bilinear_interp.sv",
    RTL_ROOT / "preprocess" / "line_buffer_3x3.sv",
    RTL_ROOT / "preprocess" / "window_3x3.sv",
    RTL_ROOT / "preprocess" / "gaussian_3x3.sv",
    RTL_ROOT / "detect" / "sobel_3x3.sv",
    RTL_ROOT / "detect" / "threshold.sv",
    RTL_ROOT / "detect" / "morphology.sv",
]


@unittest.skipUnless(IVERILOG and VVP, "requires Icarus Verilog (iverilog and vvp)")
class PreprocessRtlCompileTests(unittest.TestCase):
    def test_every_preprocess_source_compiles_with_systemverilog(self) -> None:
        # This catches missing modules, syntax errors, and incompatible ports.
        missing_sources = [str(source) for source in RTL_SOURCES if not source.is_file()]
        self.assertEqual(missing_sources, [], f"missing RTL files: {missing_sources}")

        smoke_top = """
module rtl_compile_smoke;
endmodule
"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            smoke_path = temporary_path / "rtl_compile_smoke.sv"
            output_path = temporary_path / "rtl_compile_smoke.vvp"
            smoke_path.write_text(smoke_top, encoding="utf-8")

            result = subprocess.run(
                [
                    IVERILOG,
                    "-g2012",
                    "-s",
                    "rtl_compile_smoke",
                    "-o",
                    str(output_path),
                    *(str(source) for source in RTL_SOURCES),
                    str(smoke_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
