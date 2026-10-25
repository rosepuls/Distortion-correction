`timescale 1ns / 1ps

module bicubic_sample_planner_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg signed [31:0] s_sx = 0, s_sy = 0;
    reg s_geometry_valid = 1;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 0;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 1;
    wire [10:0] m_x0, m_x1, m_x2, m_x3;
    wire [9:0] m_y0, m_y1, m_y2, m_y3;
    wire [15:0] m_fx, m_fy;
    wire [15:0] m_neighbor_valid;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    bicubic_sample_planner #(
        .IMAGE_WIDTH(8), .IMAGE_HEIGHT(8)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_sx(s_sx), .s_sy(s_sy), .s_geometry_valid(s_geometry_valid),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version), .s_sof(s_sof), .s_eol(s_eol),
        .s_eof(s_eof), .m_valid(m_valid), .m_ready(m_ready),
        .m_x0(m_x0), .m_x1(m_x1), .m_x2(m_x2), .m_x3(m_x3),
        .m_y0(m_y0), .m_y1(m_y1), .m_y2(m_y2), .m_y3(m_y3),
        .m_fx(m_fx), .m_fy(m_fy), .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send_and_check(
        input signed [31:0] x, input signed [31:0] y,
        input geometry, input [19:0] id, input expected_valid,
        input [10:0] ex0, ex1, ex2, ex3,
        input [9:0] ey0, ey1, ey2, ey3,
        input [15:0] efx, efy
    );
        begin
            @(negedge clk);
            if (!s_ready) $fatal(1, "Planner did not accept input");
            s_sx = x; s_sy = y; s_geometry_valid = geometry;
            s_pixel_id = id; s_frame_id = 32'h12340000 + id;
            s_param_version = 16'h0042; s_sof = (id == 1);
            s_eol = (id == 2); s_eof = (id == 3); s_valid = 1;
            @(posedge clk); #1;
            if (!m_valid || m_pixel_id !== id ||
                m_frame_id !== 32'h12340000 + id ||
                m_param_version !== 16'h0042 ||
                m_sof !== (id == 1) || m_eol !== (id == 2) ||
                m_eof !== (id == 3) ||
                m_geometry_valid !== expected_valid ||
                m_neighbor_valid !== (expected_valid ? 16'hffff : 16'h0000) ||
                {m_x0,m_x1,m_x2,m_x3} !== {ex0,ex1,ex2,ex3} ||
                {m_y0,m_y1,m_y2,m_y3} !== {ey0,ey1,ey2,ey3} ||
                m_fx !== efx || m_fy !== efy) begin
                $display("id=%0d valid=%b/%b mask=%h xy=%0d,%0d,%0d,%0d / %0d,%0d,%0d,%0d frac=%h,%h flags=%b%b%b",
                         id, m_geometry_valid, expected_valid, m_neighbor_valid,
                         m_x0,m_x1,m_x2,m_x3,m_y0,m_y1,m_y2,m_y3,
                         m_fx,m_fy,m_sof,m_eol,m_eof);
                $fatal(1, "Planner mismatch for sample %0d", id);
            end
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1;

        // Stencil coordinates are floor-1 through floor+2.
        send_and_check(1 * 65536, 2 * 65536, 1, 1, 1,
                       0,1,2,3, 1,2,3,4, 0,0);
        send_and_check(3 * 65536 + 32768, 4 * 65536 + 16384, 1, 2, 1,
                       2,3,4,5, 3,4,5,6, 32768,16384);

        // Any incomplete 4x4 support uses black border and clears the mask.
        send_and_check(0, 2 * 65536, 1, 3, 0,
                       0,0,1,2, 1,2,3,4, 0,0);
        send_and_check(7 * 65536, 7 * 65536, 1, 4, 0,
                       6,7,7,7, 6,7,7,7, 0,0);
        send_and_check(-32768, 2 * 65536, 1, 5, 0,
                       0,0,0,1, 1,2,3,4, 32768,0);
        send_and_check(3 * 65536, 3 * 65536, 0, 6, 0,
                       2,3,4,5, 2,3,4,5, 0,0);

        // Hold a valid response under backpressure and check stable metadata.
        @(negedge clk);
        s_sx = 2 * 65536; s_sy = 2 * 65536; s_geometry_valid = 1;
        s_pixel_id = 20'habcde; s_frame_id = 32'hfeed1234;
        s_param_version = 16'h1357; s_sof = 1; s_eol = 0; s_eof = 1;
        s_valid = 1; m_ready = 0;
        @(posedge clk); #1;
        s_valid = 0;
        repeat (3) begin
            if (!m_valid || s_ready || m_pixel_id !== 20'habcde ||
                m_frame_id !== 32'hfeed1234 || m_param_version !== 16'h1357 ||
                !m_sof || m_eol || !m_eof || !m_geometry_valid ||
                m_neighbor_valid !== 16'hffff)
                $fatal(1, "Planner did not hold response under backpressure");
            @(posedge clk); #1;
        end
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        if (m_valid) $fatal(1, "Planner did not retire stalled response");

        $display("PASS: Stage 9 bicubic stencil, strict border and handshake test");
        $finish;
    end
endmodule
