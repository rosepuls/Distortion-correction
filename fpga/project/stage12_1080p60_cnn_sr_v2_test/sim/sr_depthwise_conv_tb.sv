`timescale 1ns/1ps
module sr_depthwise_conv_tb;
    localparam W = 16;
    localparam H = 16;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [575:0] s_window = 0;
    reg [10:0] s_x = 0;
    reg [9:0] s_y = 0;
    reg [20:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 32'h456789ab;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [63:0] m_features;
    wire [10:0] m_x;
    wire [9:0] m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;

    reg [7:0] input_features [0:8*W*H-1];
    reg [7:0] expected_features [0:8*W*H-1];
    integer accepted = 0, produced = 0, cycle = 0;
    integer x, y, dx, dy, tap, ch, expected_index;
    reg [7:0] px;
    sr_depthwise_conv dut (
        .clk(clk), .rstn(rstn),
        .s_valid(s_valid), .s_ready(s_ready), .s_window(s_window),
        .s_x(s_x), .s_y(s_y), .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features), .m_skip(),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    initial begin
        $readmemh("../../../source/rtl/sr/weights/stem_u8.hex", input_features);
        $readmemh("../../../source/rtl/sr/weights/block1_depthwise_u8.hex", expected_features);
        repeat (4) @(negedge clk);
        rstn = 1;
        for (integer yy = 0; yy < H; yy = yy + 1) begin
            for (integer xx = 0; xx < W; xx = xx + 1) begin
                @(negedge clk);
                s_valid = 1;
                s_x = xx;
                s_y = yy;
                s_pixel_id = yy*W+xx;
                s_sof = (xx == 0 && yy == 0);
                s_eol = (xx == W-1);
                s_eof = (xx == W-1 && yy == H-1);
                for (integer wy = 0; wy < 3; wy = wy + 1) begin
                    for (integer wx = 0; wx < 3; wx = wx + 1) begin
                        integer ix, iy;
                        ix = xx + wx - 1;
                        iy = yy + wy - 1;
                        for (integer cc = 0; cc < 8; cc = cc + 1) begin
                            if (ix < 0 || ix >= W || iy < 0 || iy >= H) px = 0;
                            else px = input_features[cc*W*H + iy*W+ix];
                            s_window[((8-(wy*3+wx))*8+cc)*8 +: 8] = px;
                        end
                    end
                end
                do @(posedge clk); while (!s_ready);
                accepted = accepted + 1;
            end
        end
        @(negedge clk);
        s_valid = 0;
    end

    always @(negedge clk) begin
        cycle = cycle + 1;
        m_ready = (cycle % 7 != 0) && (cycle % 13 != 0);
    end

    always @(posedge clk) begin
        if (rstn && m_valid && m_ready) begin
            x = produced % W;
            y = produced / W;
            if (m_x != x || m_y != y || m_pixel_id != produced || m_frame_id != 32'h456789ab)
                $fatal(1, "stem metadata mismatch pixel=%0d xy=%0d,%0d got=%0d,%0d", produced, x,y,m_x,m_y);
            if (m_sof != (produced == 0) || m_eol != (x == W-1) || m_eof != (produced == W*H-1))
                $fatal(1, "stem raster marker mismatch pixel=%0d", produced);
            for (integer cc = 0; cc < 8; cc = cc + 1) begin
                expected_index = cc*W*H + produced;
                if (m_features[cc*8 +: 8] !== expected_features[expected_index])
                    $fatal(1, "stem golden mismatch pixel=%0d channel=%0d got=%0d expected=%0d", produced, cc, m_features[cc*8 +: 8], expected_features[expected_index]);
            end
            produced = produced + 1;
        end
        if (cycle > 10000) $fatal(1, "timeout: accepted=%0d produced=%0d", accepted, produced);
        if (produced == W*H) begin
            $display("PASS: trained block1 depthwise 8x3x3 golden vectors, metadata, and output backpressure");
            $finish;
        end
    end
endmodule



