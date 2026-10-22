`timescale 1ns / 1ps

module coordinate_fifo_tb;
    localparam integer DEPTH = 3;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg signed [31:0] s_sx = 32'sd0;
    reg signed [31:0] s_sy = 32'sd0;
    reg s_geometry_valid = 1'b0;
    reg signed [31:0] s_j00 = 32'sd0;
    reg signed [31:0] s_j01 = 32'sd0;
    reg signed [31:0] s_j10 = 32'sd0;
    reg signed [31:0] s_j11 = 32'sd0;
    reg s_j_valid = 1'b0;
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
    wire [1:0] level;

    coordinate_fifo #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_sx(s_sx),
        .s_sy(s_sy),
        .s_geometry_valid(s_geometry_valid),
        .s_j00(s_j00),
        .s_j01(s_j01),
        .s_j10(s_j10),
        .s_j11(s_j11),
        .s_j_valid(s_j_valid),
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
        .m_eof(m_eof),
        .level(level)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    task automatic drive_payload;
        input signed [31:0] sx;
        input signed [31:0] sy;
        input geometry_valid;
        input signed [31:0] j00;
        input signed [31:0] j01;
        input signed [31:0] j10;
        input signed [31:0] j11;
        input j_valid;
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
            s_j00 = j00;
            s_j01 = j01;
            s_j10 = j10;
            s_j11 = j11;
            s_j_valid = j_valid;
            s_pixel_id = pixel_id;
            s_frame_id = frame_id;
            s_param_version = param_version;
            s_sof = sof;
            s_eol = eol;
            s_eof = eof;
        end
    endtask

    task automatic check_payload;
        input signed [31:0] sx;
        input signed [31:0] sy;
        input geometry_valid;
        input signed [31:0] j00;
        input signed [31:0] j01;
        input signed [31:0] j10;
        input signed [31:0] j11;
        input j_valid;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            check(m_valid, "queued coordinate is valid");
            check(m_sx === sx && m_sy === sy, "source coordinates preserved");
            check(m_geometry_valid === geometry_valid, "geometry valid preserved");
            check(m_j00 === j00 && m_j01 === j01 &&
                  m_j10 === j10 && m_j11 === j11,
                  "all four Q16.16 Jacobian elements preserved");
            check(m_j_valid === j_valid, "Jacobian valid preserved");
            check(m_pixel_id === pixel_id && m_frame_id === frame_id &&
                  m_param_version === param_version,
                  "pixel, frame, and parameter identifiers preserved");
            check(m_sof === sof && m_eol === eol && m_eof === eof,
                  "frame boundary metadata preserved");
        end
    endtask

    initial begin
        tick();
        check(!s_ready && !m_valid && level == 0,
              "reset blocks input and empties queue");
        @(negedge clk);
        rstn = 1'b1;
        #1;
        check(s_ready, "empty queue accepts input after reset");

        // Fill a deliberately non-power-of-two queue. The head must remain A
        // while later entries are written and the downstream is stalled.
        drive_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);
        tick();
        check(level == 1, "first push increments level");
        check_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);

        @(negedge clk);
        drive_payload(32'sh00020000, 32'sh00030000, 1'b1,
                      32'sh0000f000, 32'sh00000010, 32'sh00000020, 32'sh0000e000, 1'b1,
                      20'd11, 32'h22222222, 16'h0022, 1'b0, 1'b1, 1'b0);
        tick();
        check(level == 2, "second push increments level");
        check_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);

        @(negedge clk);
        drive_payload(-32'sh00010000, 32'sh02cf0000, 1'b0,
                      -32'sh00010000, 32'sd0, 32'sd0, -32'sh00010000, 1'b0,
                      20'd12, 32'h33333333, 16'h0033, 1'b0, 1'b0, 1'b1);
        tick();
        check(level == 3 && !s_ready, "third push fills queue");
        check_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);

        // D is held while full. It must not overwrite A until A is consumed.
        @(negedge clk);
        drive_payload(32'sh04ff0000, 32'sh02cf0000, 1'b1,
                      32'sh00010000, 32'sd0, 32'sd0, 32'sh00010000, 1'b1,
                      20'd13, 32'h44444444, 16'h0044, 1'b0, 1'b1, 1'b1);
        tick();
        check(level == 3 && !s_ready, "full stalled queue rejects input");
        check_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);

        // A pop creates room for D on the same edge, with no input bubble.
        @(negedge clk);
        m_ready = 1'b1;
        #1;
        check(s_ready, "full queue accepts simultaneous pop and push");
        check_payload(32'sh00008000, -32'sh00004000, 1'b1,
                      32'sh00010000, 32'sh00000001, -32'sh00000002, 32'sh00010003, 1'b1,
                      20'd10, 32'h11111111, 16'h0011, 1'b1, 1'b0, 1'b0);
        tick();
        check(level == 3, "simultaneous pop and push preserves full level");
        check_payload(32'sh00020000, 32'sh00030000, 1'b1,
                      32'sh0000f000, 32'sh00000010, 32'sh00000020, 32'sh0000e000, 1'b1,
                      20'd11, 32'h22222222, 16'h0022, 1'b0, 1'b1, 1'b0);

        // Drain B, stall on C, then drain C and wrapped entry D in order.
        @(negedge clk);
        s_valid = 1'b0;
        tick();
        check(level == 2, "pop B decrements level");
        check_payload(-32'sh00010000, 32'sh02cf0000, 1'b0,
                      -32'sh00010000, 32'sd0, 32'sd0, -32'sh00010000, 1'b0,
                      20'd12, 32'h33333333, 16'h0033, 1'b0, 1'b0, 1'b1);
        @(negedge clk);
        m_ready = 1'b0;
        tick();
        check(level == 2, "downstream stall preserves level");
        check_payload(-32'sh00010000, 32'sh02cf0000, 1'b0,
                      -32'sh00010000, 32'sd0, 32'sd0, -32'sh00010000, 1'b0,
                      20'd12, 32'h33333333, 16'h0033, 1'b0, 1'b0, 1'b1);
        @(negedge clk);
        m_ready = 1'b1;
        tick();
        check(level == 1, "pop C decrements level");
        check_payload(32'sh04ff0000, 32'sh02cf0000, 1'b1,
                      32'sh00010000, 32'sd0, 32'sd0, 32'sh00010000, 1'b1,
                      20'd13, 32'h44444444, 16'h0044, 1'b0, 1'b1, 1'b1);
        tick();
        check(level == 0 && !m_valid, "pop D empties wrapped queue");

        // A queued item is discarded by reset, and reset cannot report a
        // false input handshake.
        @(negedge clk);
        m_ready = 1'b0;
        drive_payload(32'sh00050000, 32'sh00060000, 1'b1,
                      32'sh00010000, 32'sd0, 32'sd0, 32'sh00010000, 1'b1,
                      20'd14, 32'h55555555, 16'h0055, 1'b0, 1'b0, 1'b0);
        tick();
        check(level == 1 && m_valid, "post-wrap push is visible");
        @(negedge clk);
        rstn = 1'b0;
        tick();
        check(level == 0 && !m_valid && !s_ready, "reset flushes queue and blocks input");

        $display("PASS: coordinate_fifo ordering, wrap, backpressure, and metadata test");
        $finish;
    end
endmodule
