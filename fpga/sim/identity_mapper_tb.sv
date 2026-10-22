`timescale 1ns / 1ps

module identity_mapper_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [10:0] s_u = 11'd0;
    reg [9:0] s_v = 10'd0;
    reg [19:0] s_pixel_id = 20'd0;
    reg [31:0] s_frame_id = 32'd0;
    reg [15:0] s_param_version = 16'd0;
    reg s_sof = 1'b0;
    reg s_eol = 1'b0;
    reg s_eof = 1'b0;

    wire m_valid;
    reg m_ready = 1'b0;
    wire signed [31:0] m_sx;
    wire signed [31:0] m_sy;
    wire m_geometry_valid;
    wire signed [31:0] m_j00;
    wire signed [31:0] m_j01;
    wire signed [31:0] m_j10;
    wire signed [31:0] m_j11;
    wire m_j_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof;
    wire m_eol;
    wire m_eof;

    identity_mapper dut (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_u(s_u),
        .s_v(s_v),
        .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_eof(s_eof),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_sx(m_sx),
        .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid),
        .m_j00(m_j00),
        .m_j01(m_j01),
        .m_j10(m_j10),
        .m_j11(m_j11),
        .m_j_valid(m_j_valid),
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
        input [10:0] u;
        input [9:0] v;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            s_valid = 1'b1;
            s_u = u;
            s_v = v;
            s_pixel_id = pixel_id;
            s_frame_id = frame_id;
            s_param_version = param_version;
            s_sof = sof;
            s_eol = eol;
            s_eof = eof;
        end
    endtask

    task automatic check_output;
        input [10:0] u;
        input [9:0] v;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            check(m_valid, "output is valid");
            check(m_sx === $signed({5'd0, u, 16'd0}), "sx is unsigned u encoded as signed Q16.16");
            check(m_sy === $signed({6'd0, v, 16'd0}), "sy is unsigned v encoded as signed Q16.16");
            check(m_geometry_valid, "identity coordinate is geometrically valid");
            check(m_j_valid, "identity Jacobian is valid");
            check(m_j00 === 32'sh00010000 && m_j01 === 32'sd0 &&
                  m_j10 === 32'sd0 && m_j11 === 32'sh00010000,
                  "identity Jacobian is Q16.16 [[1,0],[0,1]]");
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

        // One-entry elastic behavior: capture a corner and hold every field
        // stable while the downstream is stalled.
        drive_input(11'd1279, 10'd719, 20'd921599, 32'h12345678, 16'h0042,
                    1'b0, 1'b1, 1'b1);
        tick();
        @(negedge clk);
        s_valid = 1'b0;
        check_output(11'd1279, 10'd719, 20'd921599, 32'h12345678, 16'h0042,
                     1'b0, 1'b1, 1'b1);
        check(!s_ready, "full output register applies backpressure");
        tick();
        check_output(11'd1279, 10'd719, 20'd921599, 32'h12345678, 16'h0042,
                     1'b0, 1'b1, 1'b1);

        // Consume the stalled item while accepting the next item on the same
        // edge, proving one output pixel per cycle after pipeline fill.
        @(negedge clk);
        m_ready = 1'b1;
        drive_input(11'd0, 10'd0, 20'd0, 32'h89abcdef, 16'h0007,
                    1'b1, 1'b0, 1'b0);
        #1;
        check(s_ready, "ready during simultaneous consume and accept");
        tick();
        check_output(11'd0, 10'd0, 20'd0, 32'h89abcdef, 16'h0007,
                     1'b1, 1'b0, 1'b0);

        @(negedge clk);
        drive_input(11'd640, 10'd360, 20'd461440, 32'h89abcdef, 16'h0007,
                    1'b0, 1'b0, 1'b0);
        tick();
        check_output(11'd640, 10'd360, 20'd461440, 32'h89abcdef, 16'h0007,
                     1'b0, 1'b0, 1'b0);

        // Reset must flush an unconsumed coordinate so a previous frame can
        // never leak into a new processing task.
        @(negedge clk);
        m_ready = 1'b0;
        s_valid = 1'b0;
        rstn = 1'b0;
        tick();
        check(!m_valid, "reset flushes the coordinate register");
        check(!s_ready, "reset blocks new coordinate handshakes");
        @(negedge clk);
        rstn = 1'b1;
        #1;
        check(s_ready, "mapper accepts coordinates immediately after reset release");

        $display("PASS: identity_mapper Q16.16 handshake and metadata test");
        $finish;
    end
endmodule
