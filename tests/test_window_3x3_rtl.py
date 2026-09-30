from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
IVERILOG = shutil.which("iverilog")
VVP = shutil.which("vvp")


@unittest.skipUnless(IVERILOG and VVP, "requires Icarus Verilog (iverilog and vvp)")
class Window3x3RtlTests(unittest.TestCase):
    def test_full_frame_zero_padded_windows_are_raster_ordered(self) -> None:
        """Check all corners and both output EOL markers on a 3x2 frame."""
        testbench = r"""
module tb_window_3x3;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] in_pixel = 8'd0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire [7:0] tap_top, tap_middle, tap_bottom;
    wire line_valid, line_sof, line_eol, line_synthetic;
    wire [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    wire out_valid, out_sof, out_eol;

    always #5 clk = ~clk;

    line_buffer_3x3 #(.IMAGE_WIDTH(3), .IMAGE_HEIGHT(2), .PIXEL_WIDTH(8)) line_buffer (
        .clk(clk), .rst_n(rst_n), .in_pixel(in_pixel), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .tap_top(tap_top),
        .tap_middle(tap_middle), .tap_bottom(tap_bottom), .out_valid(line_valid),
        .out_sof(line_sof), .out_eol(line_eol), .out_synthetic(line_synthetic)
    );

    window_3x3 #(.IMAGE_WIDTH(3), .IMAGE_HEIGHT(2), .PIXEL_WIDTH(8)) window (
        .clk(clk), .rst_n(rst_n), .tap_top(tap_top), .tap_middle(tap_middle),
        .tap_bottom(tap_bottom), .in_valid(line_valid), .in_sof(line_sof),
        .in_eol(line_eol), .in_synthetic(line_synthetic), .p00(p00), .p01(p01),
        .p02(p02), .p10(p10), .p11(p11), .p12(p12), .p20(p20), .p21(p21),
        .p22(p22), .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task send_pixel;
        input [7:0] value;
        input sof;
        input eol;
        begin
            @(negedge clk);
            in_pixel = value;
            in_valid = 1'b1;
            in_sof = sof;
            in_eol = eol;
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
        end
    endtask

    always @(negedge clk) begin
        if (out_valid)
            $display("WINDOW %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                out_sof, out_eol, p00, p01, p02, p10, p11, p12, p20, p21, p22);
    end

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        send_pixel(8'd1, 1'b1, 1'b0);
        send_pixel(8'd2, 1'b0, 1'b0);
        send_pixel(8'd3, 1'b0, 1'b1);
        send_pixel(8'd4, 1'b0, 1'b0);
        send_pixel(8'd5, 1'b0, 1'b0);
        send_pixel(8'd6, 1'b0, 1'b1);
        repeat (20) @(negedge clk);
        $finish;
    end
endmodule
"""
        expected = [
            (1, 0, 0, 0, 0, 0, 1, 2, 0, 4, 5),
            (0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6),
            (0, 1, 0, 0, 0, 2, 3, 0, 5, 6, 0),
            (0, 0, 0, 1, 2, 0, 4, 5, 0, 0, 0),
            (0, 0, 1, 2, 3, 4, 5, 6, 0, 0, 0),
            (0, 1, 2, 3, 0, 5, 6, 0, 0, 0, 0),
        ]
        line_buffer = PROJECT_ROOT / "rtl" / "preprocess" / "line_buffer_3x3.sv"
        window = PROJECT_ROOT / "rtl" / "preprocess" / "window_3x3.sv"

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            testbench_path = temporary_path / "tb_window_3x3.sv"
            executable_path = temporary_path / "tb_window_3x3.vvp"
            testbench_path.write_text(testbench, encoding="utf-8")

            compile_result = subprocess.run(
                [
                    IVERILOG,
                    "-g2012",
                    "-s",
                    "tb_window_3x3",
                    "-o",
                    str(executable_path),
                    str(line_buffer),
                    str(window),
                    str(testbench_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)

            run_result = subprocess.run(
                [VVP, str(executable_path)], check=False, capture_output=True, text=True
            )
            self.assertEqual(run_result.returncode, 0, run_result.stdout + run_result.stderr)

        observed = [
            tuple(int(value) for value in line.split()[1:])
            for line in run_result.stdout.splitlines()
            if line.startswith("WINDOW ")
        ]
        self.assertEqual(observed, expected)


if __name__ == "__main__":
    unittest.main()
