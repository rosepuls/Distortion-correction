`timescale 1ns/1ps
module sr_feature_window_pipeline_tb;
    localparam W = 4;
    localparam H = 3;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [63:0] s_features = 0;
    reg [31:0] s_frame_id = 32'h13579bdf;
    wire m_valid;
    reg m_ready = 0;
    wire [575:0] m_window;
    wire [2:0] m_x, m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    reg [7:0] image [0:2*8*W*H-1];
    integer accepted = 0, produced = 0, cycle = 0;
    integer x, y, tap, channel, src_x, src_y, bit_index;
    reg [7:0] expected;

    sr_feature_window_pipeline #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .X_WIDTH(3), .Y_WIDTH(3)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_features(s_features), .s_frame_id(s_frame_id),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    initial begin
        for (integer f = 0; f < 2; f = f + 1)
            for (integer c = 0; c < 8; c = c + 1)
                for (integer yy = 0; yy < H; yy = yy + 1)
                    for (integer xx = 0; xx < W; xx = xx + 1)
                        image[f*8*W*H + c*W*H + yy*W + xx] = (f*47 + c*29 + yy*17 + xx*11 + 3) & 8'hff;

        repeat (4) @(negedge clk);
        rstn = 1;
        for (integer f = 0; f < 2; f = f + 1) begin
            s_frame_id = 32'h13579bdf + f;
            for (integer yy = 0; yy < H; yy = yy + 1) begin
                for (integer xx = 0; xx < W; xx = xx + 1) begin
                    @(negedge clk);
                    s_valid = 1;
                    for (integer c = 0; c < 8; c = c + 1)
                        s_features[c*8 +: 8] = image[f*8*W*H + c*W*H + yy*W + xx];
                    do @(posedge clk); while (!s_ready);
                    accepted = accepted + 1;
                end
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
            integer frame_index, pixel_index;
            frame_index = produced / (W*H);
            pixel_index = produced % (W*H);
            x = pixel_index % W;
            y = pixel_index / W;
            if (m_x != x || m_y != y || m_pixel_id != pixel_index ||
                m_frame_id != 32'h13579bdf + frame_index)
                $fatal(1, "window pipeline metadata mismatch pixel=%0d", produced);
            if (m_sof != (pixel_index == 0) || m_eol != (x == W-1) ||
                m_eof != (pixel_index == W*H-1))
                $fatal(1, "window pipeline marker mismatch pixel=%0d", produced);
            for (integer wy = 0; wy < 3; wy = wy + 1) begin
                for (integer wx = 0; wx < 3; wx = wx + 1) begin
                    src_x = x + wx - 1;
                    src_y = y + wy - 1;
                    tap = wy*3 + wx;
                    for (integer c = 0; c < 8; c = c + 1) begin
                        if (src_x < 0 || src_x >= W || src_y < 0 || src_y >= H)
                            expected = 0;
                        else expected = image[frame_index*8*W*H + c*W*H + src_y*W + src_x];
                        bit_index = ((8-tap)*8 + c)*8;
                        if (m_window[bit_index +: 8] !== expected)
                            $fatal(1, "window pipeline mismatch pixel=%0d tap=%0d ch=%0d got=%0d expected=%0d",
                                   produced, tap, c, m_window[bit_index +: 8], expected);
                    end
                end
            end
            produced = produced + 1;
        end
        if (cycle > 3000) $fatal(1, "timeout accepted=%0d produced=%0d", accepted, produced);
        if (produced == 2*W*H) begin
            $display("PASS: multi-frame halo-to-window stream, all taps, metadata, and backpressure");
            $finish;
        end
    end
endmodule
