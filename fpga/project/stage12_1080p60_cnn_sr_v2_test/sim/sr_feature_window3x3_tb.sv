`timescale 1ns/1ps
module sr_feature_window3x3_tb;
    localparam W = 4;
    localparam H = 3;
    localparam PW = W + 2;
    localparam PH = H + 2;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [63:0] s_features = 0;
    reg [2:0] s_x = 0, s_y = 0;
    reg [31:0] s_frame_id = 32'h2468ace0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [575:0] m_window;
    wire [2:0] m_x, m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    reg [7:0] image [0:8*W*H-1];
    integer accepted = 0, produced = 0, cycle = 0;
    integer x, y, tap_x, tap_y, channel, src_x, src_y, pixel;
    reg [7:0] expected;

    sr_feature_window3x3 #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .PADDED_WIDTH(PW), .PADDED_HEIGHT(PH),
        .X_WIDTH(3), .Y_WIDTH(3), .X_ADDR_WIDTH(3)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_features(s_features), .s_x(s_x), .s_y(s_y), .s_frame_id(s_frame_id),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    initial begin
        for (integer c = 0; c < 8; c = c + 1)
            for (integer yy = 0; yy < H; yy = yy + 1)
                for (integer xx = 0; xx < W; xx = xx + 1)
                    image[c*W*H + yy*W + xx] = (c*29 + yy*17 + xx*11 + 3) & 8'hff;

        repeat (4) @(negedge clk);
        rstn = 1;
        for (integer yy = 0; yy < PH; yy = yy + 1) begin
            for (integer xx = 0; xx < PW; xx = xx + 1) begin
                @(negedge clk);
                s_valid = 1;
                s_x = xx;
                s_y = yy;
                s_sof = (xx == 0 && yy == 0);
                s_eol = (xx == PW-1);
                s_eof = (xx == PW-1 && yy == PH-1);
                s_features = 64'd0;
                if (xx > 0 && xx < PW-1 && yy > 0 && yy < PH-1)
                    for (integer c = 0; c < 8; c = c + 1)
                        s_features[c*8 +: 8] = image[c*W*H + (yy-1)*W + (xx-1)];
                do @(posedge clk); while (!s_ready);
                accepted = accepted + 1;
            end
        end
        @(negedge clk);
        s_valid = 0;
    end

    always @(negedge clk) begin
        cycle = cycle + 1;
        m_ready = (cycle % 5 != 0) && (cycle % 11 != 0);
    end

    always @(posedge clk) begin
        if (rstn && m_valid && m_ready) begin
            x = produced % W;
            y = produced / W;
            if (m_x != x || m_y != y || m_pixel_id != produced ||
                m_frame_id != 32'h2468ace0)
                $fatal(1, "feature window metadata mismatch pixel=%0d", produced);
            if (m_sof != (produced == 0) || m_eol != (x == W-1) ||
                m_eof != (produced == W*H-1))
                $fatal(1, "feature window marker mismatch pixel=%0d", produced);
            for (integer wy = 0; wy < 3; wy = wy + 1) begin
                for (integer wx = 0; wx < 3; wx = wx + 1) begin
                    src_x = x + wx - 1;
                    src_y = y + wy - 1;
                    for (integer c = 0; c < 8; c = c + 1) begin
                        if (src_x < 0 || src_x >= W || src_y < 0 || src_y >= H)
                            expected = 0;
                        else expected = image[c*W*H + src_y*W + src_x];
                        tap_x = wy*3 + wx;
                        pixel = ((8-tap_x)*8 + c)*8;
                        if (m_window[pixel +: 8] !== expected)
                            $fatal(1, "window mismatch output=%0d tap=%0d channel=%0d got=%0d expected=%0d",
                                   produced, tap_x, c, m_window[pixel +: 8], expected);
                    end
                end
            end
            produced = produced + 1;
        end
        if (cycle > 3000) $fatal(1, "timeout accepted=%0d produced=%0d", accepted, produced);
        if (produced == W*H) begin
            $display("PASS: 8-channel feature 3x3 windows, halo, metadata, and backpressure");
            $finish;
        end
    end
endmodule
