`timescale 1ns / 1ps

module planner_strict_border_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg signed [31:0] s_sx = 0, s_sy = 0;
    reg s_geometry_valid = 1;
    reg [19:0] s_pixel_id = 0;
    wire m_valid;
    wire [10:0] m_x0, m_x1;
    wire [9:0] m_y0, m_y1;
    wire [15:0] m_fx, m_fy;
    wire [3:0] m_neighbor_valid;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;

    bilinear_sample_planner #(
        .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720), .STRICT_BLACK_BORDER(1)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_sx(s_sx), .s_sy(s_sy),
        .s_geometry_valid(s_geometry_valid), .s_border_replicate(1'b0),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'd2),
        .s_param_version(16'd3), .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(1'b1),
        .m_x0(m_x0), .m_x1(m_x1), .m_y0(m_y0), .m_y1(m_y1),
        .m_fx(m_fx), .m_fy(m_fy),
        .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(), .m_param_version(),
        .m_sof(), .m_eol(), .m_eof()
    );

    task automatic check_sample(
        input signed [31:0] x, input signed [31:0] y,
        input geometry, input [19:0] id, input expected_valid
    );
        begin
            @(negedge clk);
            if (!s_ready) $fatal(1, "Planner did not accept input");
            s_sx = x; s_sy = y; s_geometry_valid = geometry;
            s_pixel_id = id; s_valid = 1;
            @(posedge clk); #1;
            if (!m_valid || m_pixel_id !== id ||
                m_geometry_valid !== expected_valid ||
                m_neighbor_valid !== (expected_valid ? 4'b1111 : 4'b0000))
                $fatal(1, "Strict border mismatch at sample %0d", id);
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1;
        check_sample(1278 * 65536, 718 * 65536, 1, 0, 1);
        check_sample(1279 * 65536, 100 * 65536, 1, 1, 0);
        check_sample(640 * 65536, 719 * 65536, 1, 2, 0);
        check_sample(640 * 65536, 360 * 65536, 0, 3, 0);
        $display("PASS: Stage 8 strict four-neighbor black border");
        $finish;
    end
endmodule
