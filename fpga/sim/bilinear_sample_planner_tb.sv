`timescale 1ns / 1ps

module bilinear_sample_planner_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg signed [31:0] s_sx = 32'sd0;
    reg signed [31:0] s_sy = 32'sd0;
    reg s_geometry_valid = 1'b0;
    reg s_border_replicate = 1'b0;
    reg [19:0] s_pixel_id = 20'd0;
    reg [31:0] s_frame_id = 32'd0;
    reg [15:0] s_param_version = 16'd0;
    reg s_sof = 1'b0;
    reg s_eol = 1'b0;
    reg s_eof = 1'b0;

    wire m_valid;
    reg m_ready = 1'b0;
    wire [10:0] m_x0;
    wire [10:0] m_x1;
    wire [9:0] m_y0;
    wire [9:0] m_y1;
    wire [15:0] m_fx;
    wire [15:0] m_fy;
    wire [3:0] m_neighbor_valid;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof;
    wire m_eol;
    wire m_eof;

    bilinear_sample_planner dut (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_sx(s_sx),
        .s_sy(s_sy),
        .s_geometry_valid(s_geometry_valid),
        .s_border_replicate(s_border_replicate),
        .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_eof(s_eof),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_x0(m_x0),
        .m_x1(m_x1),
        .m_y0(m_y0),
        .m_y1(m_y1),
        .m_fx(m_fx),
        .m_fy(m_fy),
        .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof),
        .m_eol(m_eol),
        .m_eof(m_eof)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    task automatic drive_input;
        input signed [31:0] sx;
        input signed [31:0] sy;
        input geometry_valid;
        input border_replicate;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            s_valid = 1'b1;
            s_sx = sx;
            s_sy = sy;
            s_geometry_valid = geometry_valid;
            s_border_replicate = border_replicate;
            s_pixel_id = pixel_id;
            s_frame_id = frame_id;
            s_param_version = param_version;
            s_sof = sof;
            s_eol = eol;
            s_eof = eof;
        end
    endtask

    task automatic check_output;
        input [10:0] x0;
        input [10:0] x1;
        input [9:0] y0;
        input [9:0] y1;
        input [15:0] fx;
        input [15:0] fy;
        input [3:0] neighbor_valid;
        input geometry_valid;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            check(m_valid, "output is valid");
            check(m_x0 === x0 && m_x1 === x1, "horizontal neighbors match");
            check(m_y0 === y0 && m_y1 === y1, "vertical neighbors match");
            check(m_fx === fx && m_fy === fy, "Q16 fractions match");
            check(m_neighbor_valid === neighbor_valid, "neighbor mask matches P00/P10/P01/P11 order");
            check(m_geometry_valid === geometry_valid, "geometry validity preserved");
            check(m_pixel_id === pixel_id, "pixel id preserved");
            check(m_frame_id === frame_id, "frame id preserved");
            check(m_param_version === param_version, "parameter version preserved");
            check(m_sof === sof && m_eol === eol && m_eof === eof,
                  "frame boundary metadata preserved");
        end
    endtask

    initial begin
        tick();
        tick();
        @(negedge clk);
        rstn = 1'b1;

        // Interior point: hold it under backpressure and verify every field.
        drive_input(32'sh00054000, 32'sh00078000, 1'b1, 1'b0,
                    20'd77, 32'h10203040, 16'h0012, 1'b1, 1'b0, 1'b0);
        tick();
        @(negedge clk);
        s_valid = 1'b0;
        check_output(11'd5, 11'd6, 10'd7, 10'd8, 16'h4000, 16'h8000,
                     4'b1111, 1'b1, 20'd77, 32'h10203040, 16'h0012,
                     1'b1, 1'b0, 1'b0);
        check(!s_ready, "full output register applies backpressure");
        tick();
        check_output(11'd5, 11'd6, 10'd7, 10'd8, 16'h4000, 16'h8000,
                     4'b1111, 1'b1, 20'd77, 32'h10203040, 16'h0012,
                     1'b1, 1'b0, 1'b0);

        // -0.25 floors to -1; only the right-hand neighbors are in bounds.
        @(negedge clk);
        m_ready = 1'b1;
        drive_input(-32'sh00004000, 32'sh00008000, 1'b1, 1'b0,
                    20'd78, 32'h10203040, 16'h0012, 1'b0, 1'b0, 1'b0);
        #1;
        check(s_ready, "simultaneous consume and accept is supported");
        tick();
        check_output(11'd0, 11'd0, 10'd0, 10'd1, 16'hc000, 16'h8000,
                     4'b1010, 1'b1, 20'd78, 32'h10203040, 16'h0012,
                     1'b0, 1'b0, 1'b0);

        // At (1279.75,719.25), black border leaves only P00 valid.
        @(negedge clk);
        drive_input(32'sh04ffc000, 32'sh02cf4000, 1'b1, 1'b0,
                    20'd921599, 32'h10203040, 16'h0012, 1'b0, 1'b1, 1'b1);
        tick();
        check_output(11'd1279, 11'd1279, 10'd719, 10'd719, 16'hc000, 16'h4000,
                     4'b0001, 1'b1, 20'd921599, 32'h10203040, 16'h0012,
                     1'b0, 1'b1, 1'b1);

        // Replicate mode clamps all addresses and marks every tap readable.
        @(negedge clk);
        drive_input(-32'sh00004000, 32'sh02cf4000, 1'b1, 1'b1,
                    20'd79, 32'h55667788, 16'h0034, 1'b0, 1'b0, 1'b0);
        tick();
        check_output(11'd0, 11'd0, 10'd719, 10'd719, 16'hc000, 16'h4000,
                     4'b1111, 1'b1, 20'd79, 32'h55667788, 16'h0034,
                     1'b0, 1'b0, 1'b0);

        // Geometric invalidity wins over the selected border policy.
        @(negedge clk);
        drive_input(32'sh00010000, 32'sh00020000, 1'b0, 1'b1,
                    20'd80, 32'h55667788, 16'h0034, 1'b0, 1'b0, 1'b0);
        tick();
        check_output(11'd1, 11'd2, 10'd2, 10'd3, 16'h0000, 16'h0000,
                     4'b0000, 1'b0, 20'd80, 32'h55667788, 16'h0034,
                     1'b0, 1'b0, 1'b0);

        @(negedge clk);
        m_ready = 1'b0;
        s_valid = 1'b0;
        rstn = 1'b0;
        tick();
        check(!m_valid, "reset flushes pending sample request");
        check(!s_ready, "reset blocks input handshakes");
        @(negedge clk);
        rstn = 1'b1;
        #1;
        check(s_ready, "planner is ready after reset release");

        $display("PASS: bilinear_sample_planner floor, border, handshake and metadata test");
        $finish;
    end
endmodule
