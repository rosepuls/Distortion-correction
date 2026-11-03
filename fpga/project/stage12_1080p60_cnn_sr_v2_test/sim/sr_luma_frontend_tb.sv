`timescale 1ns / 1ps

module sr_luma_frontend_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [31:0] s_rgbx = 32'd0;
    reg [20:0] s_pixel_id = 21'd0;
    reg [31:0] s_frame_id = 32'd0;
    reg [10:0] s_x = 11'd0;
    reg [9:0] s_y = 10'd0;
    reg s_sof = 1'b0, s_eol = 1'b0, s_eof = 1'b0;
    wire m_valid;
    reg m_ready = 1'b0;
    wire [7:0] m_luma;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [10:0] m_x;
    wire [9:0] m_y;
    wire m_sof, m_eol, m_eof;

    integer sent = 0;
    integer received = 0;
    integer cycle_count = 0;
    integer r, g, b, expected;

    sr_luma_frontend dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_rgbx(s_rgbx), .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_x(s_x), .s_y(s_y), .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_y(m_luma),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id), .m_x(m_x),
        .m_y_coord(m_y), .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    always @(posedge clk) begin
        if (rstn) begin
            cycle_count <= cycle_count + 1;
            m_ready <= (cycle_count % 7 != 2) && (cycle_count % 11 != 4);
            if (s_valid && s_ready) sent <= sent + 1;
            if (m_valid && m_ready) begin
                r = (m_pixel_id * 37 + 13) & 255;
                g = (m_pixel_id * 71 + 19) & 255;
                b = (m_pixel_id * 113 + 23) & 255;
                expected = (77*r + 150*g + 29*b + 128) >> 8;
                if (m_luma !== expected[7:0])
                    $fatal(1, "FAIL: pixel %0d luma %0d expected %0d",
                           m_pixel_id, m_luma, expected);
                if (m_frame_id !== 32'h12340000 + m_pixel_id ||
                    m_x !== m_pixel_id[10:0] || m_y !== (m_pixel_id >> 11) ||
                    m_sof !== (m_pixel_id == 0) ||
                    m_eol !== (m_pixel_id[3:0] == 4'd15) ||
                    m_eof !== (m_pixel_id == 31))
                    $fatal(1, "FAIL: metadata mismatch at pixel %0d", m_pixel_id);
                received <= received + 1;
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        for (integer i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_valid = 1'b1;
            s_pixel_id = i;
            s_frame_id = 32'h12340000 + i;
            s_x = i;
            s_y = i >> 11;
            s_rgbx[31:24] = (i*37+13) & 255;
            s_rgbx[23:16] = (i*71+19) & 255;
            s_rgbx[15:8] = (i*113+23) & 255;
            s_rgbx[7:0] = 8'h00;
            s_sof = (i == 0);
            s_eol = ((i & 15) == 15);
            s_eof = (i == 31);
            @(posedge clk);
            while (!s_ready) @(posedge clk);
        end
        @(negedge clk);
        s_valid = 1'b0;
        s_sof = 1'b0; s_eol = 1'b0; s_eof = 1'b0;
        wait (received == 32);
        if (sent != 32) $fatal(1, "FAIL: sent %0d pixels", sent);
        $display("PASS: SR luma frontend arithmetic, metadata, throughput and backpressure");
        $finish;
    end
endmodule
