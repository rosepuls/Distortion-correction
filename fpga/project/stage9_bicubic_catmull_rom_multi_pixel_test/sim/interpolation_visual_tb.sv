`timescale 1ns / 1ps

module interpolation_visual_tb;
    localparam integer OUT_W = 128;
    localparam integer OUT_H = 128;
    localparam integer TOTAL = OUT_W * OUT_H;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [15:0] s_fx = 16'd0, s_fy = 16'd0;
    reg [19:0] s_pixel_id = 20'd0;
    wire m_valid;
    wire [31:0] m_pixel;
    wire [19:0] m_pixel_id;
    integer out_file;
    integer sent, received;
    integer x, y, bx, by, qx, qy, row_i, col_i;

`ifdef BICUBIC
    reg [511:0] s_samples = 512'd0;
    wire [15:0] m_param_version;
    wire [31:0] m_frame_id;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    pipelined_catmull_rom_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_samples(s_samples), .s_fx(s_fx), .s_fy(s_fy),
        .s_neighbor_valid(16'hffff), .s_geometry_valid(1'b1),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'h12345678),
        .s_param_version(16'h002a), .s_sof(1'b0), .s_eol(1'b0),
        .s_eof(1'b0), .m_valid(m_valid), .m_ready(1'b1),
        .m_pixel(m_pixel), .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version), .m_sof(m_sof),
        .m_eol(m_eol), .m_eof(m_eof)
    );
`else
    reg [31:0] s_p00 = 32'd0, s_p10 = 32'd0;
    reg [31:0] s_p01 = 32'd0, s_p11 = 32'd0;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    pipelined_bilinear_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_p00(s_p00), .s_p10(s_p10), .s_p01(s_p01), .s_p11(s_p11),
        .s_fx(s_fx), .s_fy(s_fy), .s_neighbor_valid(4'hf),
        .s_geometry_valid(1'b1), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'h12345678), .s_param_version(16'h002a),
        .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(1'b1), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
`endif

    function automatic [7:0] chart_value;
        input integer px;
        input integer py;
        begin
            // Four deliberately difficult regions: one-pixel checkerboard,
            // one-pixel vertical bars, a diagonal edge, and a hard step edge.
            if (py < 10 && px < 10)
                chart_value = (((px + py) % 2) == 0) ? 8'd24 : 8'd232;
            else if (py < 10)
                chart_value = ((px % 2) == 0) ? 8'd32 : 8'd224;
            else if (px < 10)
                chart_value = (px < ((py - 10) / 2 + 2)) ? 8'd28 : 8'd228;
            else if (px < 14)
                chart_value = 8'd32;
            else
                chart_value = 8'd224;
        end
    endfunction

    function automatic [31:0] chart_pixel;
        input integer px;
        input integer py;
        reg [7:0] value;
        begin
            value = chart_value(px, py);
            chart_pixel = {value, value, value, 8'h00};
        end
    endfunction

    always @(posedge clk) begin
        if (rstn && m_valid) begin
            if (m_pixel_id !== received[19:0])
                $fatal(1, "Output order mismatch: got %0d expected %0d",
                       m_pixel_id, received);
            $fdisplay(out_file, "%0d,%0d,%0d,%0d,%0d,%0d",
                      m_pixel_id, m_pixel_id % OUT_W, m_pixel_id / OUT_W,
                      m_pixel[31:24], m_pixel[23:16], m_pixel[15:8]);
            received = received + 1;
            if (received == TOTAL) begin
                $fclose(out_file);
`ifdef BICUBIC
                $display("PASS: RTL bicubic generated %0d pixels", received);
`else
                $display("PASS: RTL bilinear generated %0d pixels", received);
`endif
                $finish;
            end
        end
    end

    initial begin
        out_file = $fopen("pixels.csv", "w");
        if (out_file == 0) $fatal(1, "Could not open pixels.csv");
        $fdisplay(out_file, "idx,x,y,r,g,b");
        sent = 0;
        received = 0;
        repeat (5) @(negedge clk);
        rstn = 1'b1;

        for (sent = 0; sent < TOTAL; sent = sent + 1) begin
            x = sent % OUT_W;
            y = sent / OUT_W;
            // Q0.16 source position: x/y = 1.5 + output_index / 8.
            qx = 98304 + x * 8192;
            qy = 98304 + y * 8192;
            bx = qx >> 16;
            by = qy >> 16;
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_pixel_id = sent[19:0];
            s_fx = qx[15:0];
            s_fy = qy[15:0];
`ifdef BICUBIC
            for (row_i = 0; row_i < 4; row_i = row_i + 1)
                for (col_i = 0; col_i < 4; col_i = col_i + 1)
                    s_samples[(row_i*4+col_i)*32 +: 32] =
                        chart_pixel(bx + col_i - 1, by + row_i - 1);
`else
            s_p00 = chart_pixel(bx,     by);
            s_p10 = chart_pixel(bx + 1, by);
            s_p01 = chart_pixel(bx,     by + 1);
            s_p11 = chart_pixel(bx + 1, by + 1);
`endif
            s_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_valid = 1'b0;
        end
    end

    initial begin
        #20000000;
        $fatal(1, "Interpolation visualization simulation timed out");
    end
endmodule
