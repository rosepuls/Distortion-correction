`timescale 1ns / 1ps

module scale_3_2_mapper_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [11:0] s_u = 12'd0, s_v = 12'd0;
    reg [20:0] s_pixel_id = 21'd0;
    reg [31:0] s_frame_id = 32'd0;
    reg [15:0] s_param_version = 16'd0;
    reg s_sof = 1'b0, s_eol = 1'b0, s_eof = 1'b0;
    wire m_valid;
    reg m_ready = 1'b0;
    wire signed [31:0] m_sx, m_sy;
    wire m_geometry_valid;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    scale_3_2_mapper dut (
        .clk(clk), .rstn(rstn),
        .s_valid(s_valid), .s_ready(s_ready), .s_u(s_u), .s_v(s_v),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version), .s_sof(s_sof),
        .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_sx(m_sx), .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic offer(
        input [11:0] u,
        input [11:0] v,
        input [20:0] pixel_id,
        input sof,
        input eol,
        input eof
    );
        begin
            @(negedge clk);
            s_u = u;
            s_v = v;
            s_pixel_id = pixel_id;
            s_frame_id = 32'h12345678;
            s_param_version = 16'h0031;
            s_sof = sof;
            s_eol = eol;
            s_eof = eof;
            s_valid = 1'b1;
            if (!s_ready) $fatal(1, "FAIL: mapper refused an empty pipeline");
            @(posedge clk);
            @(negedge clk);
            s_valid = 1'b0;
        end
    endtask

    task automatic check_result(
        input signed [31:0] expected_x,
        input signed [31:0] expected_y,
        input [20:0] expected_id,
        input expected_sof,
        input expected_eol,
        input expected_eof
    );
        begin
            wait (m_valid);
            if (m_sx !== expected_x || m_sy !== expected_y ||
                m_geometry_valid !== 1'b1 || m_pixel_id !== expected_id ||
                m_frame_id !== 32'h12345678 || m_param_version !== 16'h0031 ||
                m_sof !== expected_sof || m_eol !== expected_eol ||
                m_eof !== expected_eof)
                $fatal(1, "FAIL: mapped output mismatch id=%0d sx=%0d sy=%0d",
                       m_pixel_id, m_sx, m_sy);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1'b1;

        offer(12'd0, 12'd0, 21'd0, 1'b1, 1'b0, 1'b0);
        check_result(-32'sd10923, -32'sd10923, 21'd0,
                     1'b1, 1'b0, 1'b0);

        // Hold one output under backpressure and ensure its coordinate and
        // frame metadata remain stable until the consumer accepts it.
        repeat (4) begin
            @(posedge clk);
            if (!m_valid || m_sx !== -32'sd10923 || m_sy !== -32'sd10923 ||
                m_pixel_id !== 21'd0 || m_frame_id !== 32'h12345678)
                $fatal(1, "FAIL: mapper changed a stalled output");
        end
        @(negedge clk);
        m_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        m_ready = 1'b0;

        offer(12'd960, 12'd540, 21'd1040640, 1'b0, 1'b0, 1'b0);
        check_result(32'sd41932117, 32'sd23582037, 21'd1040640,
                     1'b0, 1'b0, 1'b0);
        @(negedge clk); m_ready = 1'b1;
        @(posedge clk);
        @(negedge clk); m_ready = 1'b0;

        offer(12'd1919, 12'd1079, 21'd2073599, 1'b0, 1'b1, 1'b1);
        check_result(32'sd83831467, 32'sd47131307, 21'd2073599,
                     1'b0, 1'b1, 1'b1);
        @(negedge clk); m_ready = 1'b1;
        @(posedge clk);

        $display("PASS: Stage 12 center-aligned 3:2 mapping, rounding, metadata, and backpressure");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: scale_3_2_mapper test timed out");
    end
endmodule
