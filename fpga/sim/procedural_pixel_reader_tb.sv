`timescale 1ns / 1ps

module procedural_pixel_reader_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [10:0] s_x0 = 0;
    reg [10:0] s_x1 = 0;
    reg [9:0] s_y0 = 0;
    reg [9:0] s_y1 = 0;
    reg [15:0] s_fx = 0;
    reg [15:0] s_fy = 0;
    reg [3:0] s_neighbor_valid = 0;
    reg s_geometry_valid = 0;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 0;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0;
    reg s_eol = 0;
    reg s_eof = 0;

    wire m_valid;
    reg m_ready = 0;
    wire [31:0] m_p00, m_p10, m_p01, m_p11;
    wire [15:0] m_fx, m_fy;
    wire [3:0] m_neighbor_valid;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    procedural_pixel_reader dut (
        .clk(clk), .rstn(rstn),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_x0(s_x0), .s_x1(s_x1), .s_y0(s_y0), .s_y1(s_y1),
        .s_fx(s_fx), .s_fy(s_fy), .s_neighbor_valid(s_neighbor_valid),
        .s_geometry_valid(s_geometry_valid),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_p00(m_p00), .m_p10(m_p10), .m_p01(m_p01), .m_p11(m_p11),
        .m_fx(m_fx), .m_fy(m_fy), .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic tick;
        begin @(posedge clk); #1; end
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

    task automatic drive;
        input [10:0] x0;
        input [10:0] x1;
        input [9:0] y0;
        input [9:0] y1;
        input [3:0] mask;
        input [19:0] pixel_id;
        begin
            s_valid = 1'b1;
            s_x0 = x0; s_x1 = x1; s_y0 = y0; s_y1 = y1;
            s_fx = 16'h4000; s_fy = 16'h8000;
            s_neighbor_valid = mask;
            s_geometry_valid = 1'b1;
            s_pixel_id = pixel_id;
            s_frame_id = 32'h12345678;
            s_param_version = 16'h0042;
            s_sof = (pixel_id == 0);
            s_eol = 1'b0;
            s_eof = 1'b0;
        end
    endtask

    initial begin
        tick(); tick();
        @(negedge clk); rstn = 1'b1;

        // A normal 2x2 neighborhood uses literal coordinate-derived colors.
        drive(11'd5, 11'd6, 10'd7, 10'd8, 4'b1111, 20'd0);
        tick();
        @(negedge clk); s_valid = 1'b0;
        check(m_valid, "reader produced a neighborhood");
        check(m_p00 === 32'h05070200, "P00 procedural color");
        check(m_p10 === 32'h06070100, "P10 procedural color");
        check(m_p01 === 32'h05080d00, "P01 procedural color");
        check(m_p11 === 32'h06080e00, "P11 procedural color");
        check(m_fx === 16'h4000 && m_fy === 16'h8000, "fractions preserved");
        check(m_pixel_id === 0 && m_sof, "metadata preserved");
        check(!s_ready, "backpressure reaches input");
        tick();
        check(m_p00 === 32'h05070200 && m_p11 === 32'h06080e00,
              "payload remains stable while stalled");

        // Invalid left neighbors must become black before reconstruction.
        @(negedge clk); m_ready = 1'b1;
        drive(11'd0, 11'd5, 10'd7, 10'd8, 4'b1010, 20'd1);
        #1; check(s_ready, "consume and accept in one cycle");
        tick();
        check(m_p00 === 32'h00000000 && m_p01 === 32'h00000000,
              "invalid taps are black");
        check(m_p10 === 32'h05070200 && m_p11 === 32'h05080d00,
              "valid taps retain procedural pixels");
        check(m_neighbor_valid === 4'b1010, "neighbor mask preserved");

        // Grid lines and image edges are deliberately white for visual checks.
        @(negedge clk);
        drive(11'd64, 11'd1279, 10'd65, 10'd719, 4'b1111, 20'd2);
        tick();
        check(m_p00 === 32'hffffff00 && m_p10 === 32'hffffff00 &&
              m_p01 === 32'hffffff00 && m_p11 === 32'hffffff00,
              "grid and outer border are white");

        @(negedge clk); s_valid = 1'b0; m_ready = 1'b0; rstn = 1'b0;
        tick();
        check(!m_valid && !s_ready, "reset flushes and blocks reader");
        $display("PASS: procedural_pixel_reader neighborhood, border and handshake test");
        $finish;
    end
endmodule
