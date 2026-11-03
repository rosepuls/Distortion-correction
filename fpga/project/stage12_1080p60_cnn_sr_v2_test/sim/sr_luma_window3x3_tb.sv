`timescale 1ns / 1ps

module sr_luma_window3x3_tb;
    localparam integer W = 4;
    localparam integer H = 3;
    localparam integer PW = W + 2;
    localparam integer PH = H + 2;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [7:0] s_luma = 0;
    reg [2:0] s_x = 0, s_y = 0;
    reg [31:0] s_frame_id = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [71:0] m_window;
    wire [2:0] m_x, m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    integer cycle_count = 0;
    integer received = 0;
    integer row, col, ky, kx, expected, actual;

    sr_luma_window3x3 #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .PADDED_WIDTH(PW),
        .PADDED_HEIGHT(PH), .X_WIDTH(3), .Y_WIDTH(3),
        .X_ADDR_WIDTH(3)
    ) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_luma(s_luma), .s_x(s_x), .s_y(s_y), .s_frame_id(s_frame_id),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    function automatic [7:0] sample(input integer px, input integer py);
        begin
            if (px < 0 || px >= W || py < 0 || py >= H)
                sample = 8'd0;
            else
                sample = 10 + py * 20 + px;
        end
    endfunction

    always @(posedge clk) begin
        if (rstn) begin
            cycle_count <= cycle_count + 1;
            m_ready <= (cycle_count % 5 != 1) && (cycle_count % 7 != 3);
            if (m_valid && m_ready) begin
                row = received / W;
                col = received % W;
                if (m_x !== col || m_y !== row || m_pixel_id !== received ||
                    m_frame_id !== 32'h89abcdef ||
                    m_sof !== (received == 0) || m_eol !== (col == W-1) ||
                    m_eof !== (received == W*H-1))
                    $fatal(1, "FAIL: window metadata at output %0d", received);
                for (ky = 0; ky < 3; ky = ky + 1) begin
                    for (kx = 0; kx < 3; kx = kx + 1) begin
                        expected = sample(col + kx - 1, row + ky - 1);
                        actual = m_window[71 - ((ky*3+kx)*8) -: 8];
                        if (actual !== expected)
                            $fatal(1, "FAIL: window %0d,%0d tap %0d,%0d got %0d expected %0d",
                                   col, row, kx, ky, actual, expected);
                    end
                end
                received <= received + 1;
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        for (integer py = 0; py < PH; py = py + 1) begin
            for (integer px = 0; px < PW; px = px + 1) begin
                @(negedge clk);
                while (!s_ready) @(negedge clk);
                s_valid = 1;
                s_x = px; s_y = py;
                s_frame_id = 32'h89abcdef;
                s_sof = (px == 0 && py == 0);
                s_eol = (px == PW-1);
                s_eof = (px == PW-1 && py == PH-1);
                if (px == 0 || px == PW-1 || py == 0 || py == PH-1)
                    s_luma = 0;
                else
                    s_luma = sample(px-1, py-1);
                @(posedge clk);
            end
        end
        @(negedge clk);
        s_valid = 0; s_sof = 0; s_eol = 0; s_eof = 0;
        wait (received == W*H);
        $display("PASS: SR luma 3x3 synchronous line window, zero halo, metadata and backpressure");
        $finish;
    end
endmodule
