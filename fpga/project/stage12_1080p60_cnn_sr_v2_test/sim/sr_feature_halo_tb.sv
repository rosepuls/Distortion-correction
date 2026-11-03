`timescale 1ns/1ps
module sr_feature_halo_tb;
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
    reg [31:0] s_frame_id = 32'h89abcdef;
    wire m_valid;
    reg m_ready = 0;
    wire [63:0] m_features;
    wire [2:0] m_x, m_y;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    reg [7:0] image [0:2*8*W*H-1];
    integer accepted = 0, produced = 0, cycle = 0;
    integer x, y;
    reg [7:0] expected;

    sr_feature_halo #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .PADDED_WIDTH(PW), .PADDED_HEIGHT(PH),
        .X_WIDTH(3), .Y_WIDTH(3)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_features(s_features), .s_frame_id(s_frame_id),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features),
        .m_x(m_x), .m_y(m_y), .m_frame_id(m_frame_id),
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
            s_frame_id = 32'h89abcdef + f;
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
        m_ready = (cycle % 4 != 0) && (cycle % 9 != 0);
    end

    always @(posedge clk) begin
        if (rstn && m_valid && m_ready) begin
            integer frame_index;
            frame_index = produced / (PW*PH);
            x = produced % PW;
            y = (produced / PW) % PH;
            if (m_x != x || m_y != y)
                $fatal(1, "halo coordinate mismatch item=%0d expected=%0d,%0d got=%0d,%0d",
                       produced, x, y, m_x, m_y);
            if (m_sof != (produced == frame_index*PW*PH) || m_eol != (x == PW-1) ||
                m_eof != (produced == (frame_index+1)*PW*PH-1))
                $fatal(1, "halo marker mismatch item=%0d", produced);
            for (integer c = 0; c < 8; c = c + 1) begin
                if (x > 0 && x < PW-1 && y > 0 && y < PH-1)
                    expected = image[frame_index*8*W*H + c*W*H + (y-1)*W + (x-1)];
                else expected = 0;
                if (m_features[c*8 +: 8] !== expected)
                    $fatal(1, "halo data mismatch item=%0d channel=%0d got=%0d expected=%0d",
                           produced, c, m_features[c*8 +: 8], expected);
            end
            if (m_frame_id !== (32'h89abcdef + frame_index))
                $fatal(1, "halo frame id mismatch item=%0d got=%h", produced, m_frame_id);
            produced = produced + 1;
        end
        if (cycle > 2000) $fatal(1, "timeout accepted=%0d produced=%0d", accepted, produced);
        if (produced == 2*PW*PH) begin
            $display("PASS: multi-frame 8-channel halo insertion, metadata, and backpressure");
            $finish;
        end
    end
endmodule
