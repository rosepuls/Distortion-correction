from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RTL_PATH = PROJECT_ROOT / "rtl" / "preprocess" / "rgb2gray.sv"
IVERILOG = shutil.which("iverilog")
VVP = shutil.which("vvp")


@unittest.skipUnless(IVERILOG and VVP, "requires Icarus Verilog (iverilog and vvp)")
class Rgb2GrayRtlTests(unittest.TestCase):
    def _run_bench(self, test_body: str) -> None:
        self.assertTrue(RTL_PATH.is_file(), f"missing RTL module: {RTL_PATH}")

        testbench = f"""
module tb_rgb2gray;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [23:0] in_pixel = '0;
    logic in_valid = 1'b0;
    logic in_sof = 1'b0;
    logic in_eol = 1'b0;
    logic [7:0] out_pixel;
    logic out_valid;
    logic out_sof;
    logic out_eol;

    rgb2gray dut (
        .clk,
        .rst_n,
        .in_pixel,
        .in_valid,
        .in_sof,
        .in_eol,
        .out_pixel,
        .out_valid,
        .out_sof,
        .out_eol
    );

    always #5 clk = ~clk;

    task automatic drive_and_expect(
        input logic [23:0] pixel,
        input logic valid,
        input logic sof,
        input logic eol,
        input logic [7:0] expected_pixel,
        input logic expected_valid,
        input logic expected_sof,
        input logic expected_eol
    );
        begin
            @(negedge clk);
            in_pixel = pixel;
            in_valid = valid;
            in_sof = sof;
            in_eol = eol;
            @(posedge clk);
            #1;
            if (out_pixel !== expected_pixel ||
                out_valid !== expected_valid ||
                out_sof !== expected_sof ||
                out_eol !== expected_eol) begin
                $fatal(1,
                    "expected pixel=%0d valid=%0b sof=%0b eol=%0b; got pixel=%0d valid=%0b sof=%0b eol=%0b",
                    expected_pixel, expected_valid, expected_sof, expected_eol,
                    out_pixel, out_valid, out_sof, out_eol
                );
            end
        end
    endtask

    initial begin
        {test_body}
    end
endmodule
"""

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            testbench_path = temporary_path / "tb_rgb2gray.sv"
            simulation_path = temporary_path / "rgb2gray_sim.vvp"
            testbench_path.write_text(testbench, encoding="utf-8")

            compile_result = subprocess.run(
                [
                    IVERILOG,
                    "-g2012",
                    "-o",
                    str(simulation_path),
                    str(RTL_PATH),
                    str(testbench_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)

            simulation_result = subprocess.run(
                [VVP, str(simulation_path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                simulation_result.returncode,
                0,
                simulation_result.stdout + simulation_result.stderr,
            )

    def test_rtl_uses_the_specified_integer_rgb_weights(self) -> None:
        # These literals catch changes to any of the 77/150/29 weights,
        # the final right shift, or RGB packing order.
        self._run_bench(
            """
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            drive_and_expect(24'h000000, 1'b1, 1'b1, 1'b0, 8'd0,   1'b1, 1'b1, 1'b0);
            drive_and_expect(24'hFFFFFF, 1'b1, 1'b0, 1'b0, 8'd255, 1'b1, 1'b0, 1'b0);
            drive_and_expect(24'hFF0000, 1'b1, 1'b0, 1'b0, 8'd76,  1'b1, 1'b0, 1'b0);
            drive_and_expect(24'h00FF00, 1'b1, 1'b0, 1'b0, 8'd149, 1'b1, 1'b0, 1'b0);
            drive_and_expect(24'h0000FF, 1'b1, 1'b0, 1'b1, 8'd28,  1'b1, 1'b0, 1'b1);
            $finish;
            """
        )

    def test_rtl_clears_control_outputs_for_reset_and_input_bubbles(self) -> None:
        # This catches a stale valid/sof/eol register after reset or a bubble.
        self._run_bench(
            """
            repeat (2) @(posedge clk);
            if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0)
                $fatal(1, "reset must clear output control signals");
            rst_n = 1'b1;
            drive_and_expect(24'h0A141E, 1'b1, 1'b1, 1'b0, 8'd18, 1'b1, 1'b1, 1'b0);
            drive_and_expect(24'hFFFFFF, 1'b0, 1'b1, 1'b1, 8'd0,  1'b0, 1'b0, 1'b0);
            $finish;
            """
        )


if __name__ == "__main__":
    unittest.main()
