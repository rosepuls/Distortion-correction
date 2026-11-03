`timescale 1ns/1ps
module sr_stem_depthwise_chain_tb;
    localparam W = 16;
    localparam H = 16;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [71:0] s_window = 0;
    reg [10:0] s_x = 0;
    reg [9:0] s_y = 0;
    reg [20:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 32'hfedcba98;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [63:0] m_features;
    wire [10:0] m_x;
    wire [9:0] m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    reg [7:0] input_image [0:W*H-1];
    reg [7:0] expected_features [0:8*W*H-1];
    integer accepted = 0, produced = 0, cycle = 0;
    integer x, y, expected_index;
    reg [7:0] px;

    sr_stem_depthwise_chain #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_window(s_window), .s_x(s_x), .s_y(s_y), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    initial begin
        $readmemh("../../../source/rtl/sr/weights/golden_input_u8.hex", input_image);
        $readmemh("../../../source/rtl/sr/weights/block1_output_u8.hex", expected_features);
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
                        if (ix < 0 || ix >= W || iy < 0 || iy >= H) px = 0;
                        else px = input_image[iy*W+ix];
                        s_window[8*(8-(wy*3+wx)) +: 8] = px;
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
            if (m_x != x || m_y != y || m_pixel_id != produced ||
                m_frame_id != 32'hfedcba98)
                $fatal(1, "chain metadata mismatch pixel=%0d", produced);
            if (m_sof != (produced == 0) || m_eol != (x == W-1) ||
                m_eof != (produced == W*H-1))
                $fatal(1, "chain raster marker mismatch pixel=%0d", produced);
            for (integer c = 0; c < 8; c = c + 1) begin
                expected_index = c*W*H + produced;
                if (m_features[c*8 +: 8] !== expected_features[expected_index])
                    $fatal(1, "chain golden mismatch pixel=%0d ch=%0d got=%0d expected=%0d",
                           produced, c, m_features[c*8 +: 8], expected_features[expected_index]);
            end
            produced = produced + 1;
        end
        if (cycle > 30000) $fatal(1, "timeout accepted=%0d produced=%0d", accepted, produced);
        if (produced == W*H) begin
            $display("PASS: stem->feature FIFO->halo/window->depthwise->pointwise->residual join golden frame and backpressure");
            $finish;
        end
    end
endmodule
