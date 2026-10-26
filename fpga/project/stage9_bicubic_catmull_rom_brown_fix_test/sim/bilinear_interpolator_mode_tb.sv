`timescale 1ns / 1ps

module bilinear_interpolator_mode_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [31:0] p00 = 0, p10 = 0, p01 = 0, p11 = 0;
    reg [15:0] fx = 0, fy = 0;
    reg [3:0] mask = 4'hf;
    reg geometry_valid = 1;
    reg m_ready = 0;
    wire m_valid, m_geometry_valid, m_sof, m_eol, m_eof;
    wire [31:0] m_pixel, m_frame_id;
    wire [19:0] m_pixel_id;
    wire [15:0] m_param_version;

    pipelined_bilinear_interpolator dut (
        .clk(clk), .rstn(rstn),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_p00(p00), .s_p10(p10), .s_p01(p01), .s_p11(p11),
        .s_fx(fx), .s_fy(fy), .s_neighbor_valid(mask),
        .s_geometry_valid(geometry_valid),
        .s_pixel_id(20'd17), .s_frame_id(32'h12345678),
        .s_param_version(16'h002a),
        .s_sof(1'b1), .s_eol(1'b0), .s_eof(1'b1),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        p00 = {8'd10, 8'd20, 8'd30, 8'd0};
        p10 = {8'd50, 8'd60, 8'd70, 8'd0};
        p01 = {8'd90, 8'd100, 8'd110, 8'd0};
        p11 = {8'd130, 8'd140, 8'd150, 8'd0};
        fx = 16'h8000;
        fy = 16'h8000;
        s_valid = 1;
        do @(posedge clk); while (!s_ready);
        @(negedge clk); s_valid = 0;
        wait (m_valid);
        repeat (5) begin
            @(negedge clk);
            if (!m_valid || m_pixel !== {8'd70, 8'd80, 8'd90, 8'd0} ||
                !m_geometry_valid || m_pixel_id !== 20'd17 ||
                m_frame_id !== 32'h12345678 ||
                m_param_version !== 16'h002a ||
                !m_sof || m_eol || !m_eof)
                $fatal(1, "Half-pixel bilinear result or stalled metadata mismatch");
        end
        m_ready = 1;
        @(negedge clk);
        if (m_valid)
            $fatal(1, "Bilinear result was not consumed");
        $display("PASS: Stage 9 bilinear fractional interpolation and backpressure");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Bilinear interpolation timed out");
    end
endmodule
