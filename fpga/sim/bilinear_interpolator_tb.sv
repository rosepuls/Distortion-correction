`timescale 1ns / 1ps

module bilinear_interpolator_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [31:0] s_p00 = 32'd0;
    reg [31:0] s_p10 = 32'd0;
    reg [31:0] s_p01 = 32'd0;
    reg [31:0] s_p11 = 32'd0;
    reg [15:0] s_fx = 16'd0;
    reg [15:0] s_fy = 16'd0;
    reg [3:0] s_neighbor_valid = 4'd0;
    reg s_geometry_valid = 1'b0;
    reg [19:0] s_pixel_id = 20'd0;
    reg [31:0] s_frame_id = 32'd0;
    reg [15:0] s_param_version = 16'd0;
    reg s_sof = 1'b0;
    reg s_eol = 1'b0;
    reg s_eof = 1'b0;

    wire m_valid;
    reg m_ready = 1'b0;
    wire [31:0] m_pixel;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof;
    wire m_eol;
    wire m_eof;

    bilinear_interpolator dut (
        .clk(clk), .rstn(rstn),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_p00(s_p00), .s_p10(s_p10), .s_p01(s_p01), .s_p11(s_p11),
        .s_fx(s_fx), .s_fy(s_fy), .s_neighbor_valid(s_neighbor_valid),
        .s_geometry_valid(s_geometry_valid),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    function automatic [31:0] rgbx;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        input [7:0] x;
        begin
            rgbx = {r, g, b, x};
        end
    endfunction

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
        input [31:0] p00;
        input [31:0] p10;
        input [31:0] p01;
        input [31:0] p11;
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
            s_valid = 1'b1;
            s_p00 = p00;
            s_p10 = p10;
            s_p01 = p01;
            s_p11 = p11;
            s_fx = fx;
            s_fy = fy;
            s_neighbor_valid = neighbor_valid;
            s_geometry_valid = geometry_valid;
            s_pixel_id = pixel_id;
            s_frame_id = frame_id;
            s_param_version = param_version;
            s_sof = sof;
            s_eol = eol;
            s_eof = eof;
        end
    endtask

    task automatic check_output;
        input [31:0] pixel;
        input geometry_valid;
        input [19:0] pixel_id;
        input [31:0] frame_id;
        input [15:0] param_version;
        input sof;
        input eol;
        input eof;
        begin
            check(m_valid, "output is valid");
            check(m_pixel === pixel, "interpolated RGBX8888 pixel matches");
            check(m_pixel[7:0] === 8'h00, "public X byte is zero");
            check(m_geometry_valid === geometry_valid, "geometry validity preserved");
            check(m_pixel_id === pixel_id && m_frame_id === frame_id,
                  "pixel and frame identifiers preserved");
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

        // Exact P00 selection also proves the input X byte is ignored.
        drive_input(rgbx(8'd12, 8'd34, 8'd56, 8'haa),
                    rgbx(8'd200, 8'd201, 8'd202, 8'hff),
                    rgbx(8'd210, 8'd211, 8'd212, 8'hff),
                    rgbx(8'd220, 8'd221, 8'd222, 8'hff),
                    16'h0000, 16'h0000, 4'b1111, 1'b1,
                    20'd1, 32'h01020304, 16'h0005, 1'b1, 1'b0, 1'b0);
        tick();
        @(negedge clk);
        s_valid = 1'b0;
        check_output(rgbx(8'd12, 8'd34, 8'd56, 8'h00), 1'b1,
                     20'd1, 32'h01020304, 16'h0005, 1'b1, 1'b0, 1'b0);
        check(!s_ready, "full output register applies backpressure");
        tick();
        check_output(rgbx(8'd12, 8'd34, 8'd56, 8'h00), 1'b1,
                     20'd1, 32'h01020304, 16'h0005, 1'b1, 1'b0, 1'b0);

        // Center of four pixels: every channel is their exact average.
        @(negedge clk);
        m_ready = 1'b1;
        drive_input(rgbx(8'd10, 8'd20, 8'd30, 8'd0),
                    rgbx(8'd20, 8'd30, 8'd40, 8'd0),
                    rgbx(8'd30, 8'd40, 8'd50, 8'd0),
                    rgbx(8'd40, 8'd50, 8'd60, 8'd0),
                    16'h8000, 16'h8000, 4'b1111, 1'b1,
                    20'd2, 32'h01020304, 16'h0005, 1'b0, 1'b0, 1'b0);
        #1;
        check(s_ready, "simultaneous consume and accept is supported");
        tick();
        check_output(rgbx(8'd25, 8'd35, 8'd45, 8'd0), 1'b1,
                     20'd2, 32'h01020304, 16'h0005, 1'b0, 1'b0, 1'b0);

        // Invalid left taps contribute black; weights are not renormalized.
        @(negedge clk);
        drive_input(rgbx(8'd255, 8'd255, 8'd255, 8'd0),
                    rgbx(8'd100, 8'd20, 8'd40, 8'd0),
                    rgbx(8'd255, 8'd255, 8'd255, 8'd0),
                    rgbx(8'd200, 8'd60, 8'd80, 8'd0),
                    16'hc000, 16'h8000, 4'b1010, 1'b1,
                    20'd3, 32'h01020304, 16'h0005, 1'b0, 1'b1, 1'b0);
        tick();
        check_output(rgbx(8'd113, 8'd30, 8'd45, 8'd0), 1'b1,
                     20'd3, 32'h01020304, 16'h0005, 1'b0, 1'b1, 1'b0);

        // A half-LSB result rounds upward after the full 2D accumulation.
        @(negedge clk);
        drive_input(rgbx(8'd0, 8'd0, 8'd0, 8'd0),
                    rgbx(8'd1, 8'd1, 8'd1, 8'd0),
                    rgbx(8'd0, 8'd0, 8'd0, 8'd0),
                    rgbx(8'd1, 8'd1, 8'd1, 8'd0),
                    16'h8000, 16'h0000, 4'b1111, 1'b1,
                    20'd4, 32'h01020304, 16'h0005, 1'b0, 1'b0, 1'b1);
        tick();
        check_output(rgbx(8'd1, 8'd1, 8'd1, 8'd0), 1'b1,
                     20'd4, 32'h01020304, 16'h0005, 1'b0, 1'b0, 1'b1);

        // Non-symmetric full-scale weights exercise the widest accumulator value.
        @(negedge clk);
        drive_input(32'hffffff00, 32'hffffff00, 32'hffffff00, 32'hffffff00,
                    16'he731, 16'h294a, 4'b1111, 1'b1,
                    20'd5, 32'h05060708, 16'h0006, 1'b0, 1'b0, 1'b0);
        tick();
        check_output(32'hffffff00, 1'b1,
                     20'd5, 32'h05060708, 16'h0006, 1'b0, 1'b0, 1'b0);

        // No readable taps yields black while keeping the output transaction.
        @(negedge clk);
        drive_input(32'hff010200, 32'h03ff0400, 32'h0506ff00, 32'hffffff00,
                    16'h1234, 16'h5678, 4'b0000, 1'b0,
                    20'd6, 32'h05060708, 16'h0006, 1'b0, 1'b0, 1'b0);
        tick();
        check_output(32'h00000000, 1'b0,
                     20'd6, 32'h05060708, 16'h0006, 1'b0, 1'b0, 1'b0);

        @(negedge clk);
        m_ready = 1'b0;
        s_valid = 1'b0;
        rstn = 1'b0;
        tick();
        check(!m_valid, "reset flushes pending output pixel");
        check(!s_ready, "reset blocks input handshakes");

        $display("PASS: bilinear_interpolator RGBX8888 arithmetic, handshake and metadata test");
        $finish;
    end
endmodule
