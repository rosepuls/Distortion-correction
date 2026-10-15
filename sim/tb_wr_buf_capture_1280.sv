`timescale 1ns/1ps

module tb_wr_buf_capture_1280;
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer BEATS_PER_LINE = IMAGE_WIDTH / 8;

    reg ddr_clk = 1'b0;
    reg pix_clk = 1'b0;
    reg ddr_rstn = 1'b0;
    reg wr_fsync = 1'b0;
    reg wr_en = 1'b0;
    reg [31:0] wr_data = 32'd0;
    reg ddr_wrdy = 1'b1;
    wire ddr_wdone;
    reg ddr_wdata_req = 1'b0;
    wire ddr_wreq;
    wire [27:0] ddr_waddr;
    wire [31:0] ddr_wr_len;
    wire [255:0] ddr_wdata;
    wire [5:0] frame_wcnt;
    wire frame_wirq;

    reg burst_active = 1'b0;
    integer request_phase = 0;
    integer beat_index = 0;
    reg [255:0] captured_beats [0:BEATS_PER_LINE-1];
    integer captured_count = 0;
    integer unknown_words = 0;
    integer mismatches = 0;
    integer x;
    integer lane;
    integer wait_cycles = 0;

    always #4 ddr_clk = ~ddr_clk;
    always #6.5 pix_clk = ~pix_clk;

    wr_buf #(
        .ADDR_WIDTH(28), .ADDR_OFFSET(0), .H_NUM(IMAGE_WIDTH), .V_NUM(1),
        .DQ_WIDTH(32), .LEN_WIDTH(32), .PIX_WIDTH(32),
        .LINE_ADDR_WIDTH(22), .FRAME_CNT_WIDTH(6)
    ) dut (
        .ddr_clk(ddr_clk), .ddr_rstn(ddr_rstn), .wr_clk(pix_clk),
        .wr_fsync(wr_fsync), .wr_en(wr_en), .wr_data(wr_data),
        .rd_bac(1'b0), .ddr_wreq(ddr_wreq), .ddr_waddr(ddr_waddr),
        .ddr_wr_len(ddr_wr_len), .ddr_wrdy(ddr_wrdy), .ddr_wdone(ddr_wdone),
        .ddr_wdata(ddr_wdata), .ddr_wdata_req(ddr_wdata_req),
        .frame_wcnt(frame_wcnt), .frame_wirq(frame_wirq)
    );

    // Model a command accepted by DDR and one 256-bit data request every
    // four DDR clocks. Capture on the rising edge where the request is valid.
    always @(negedge ddr_clk) begin
        if (!ddr_rstn) begin
            burst_active <= 1'b0;
            request_phase <= 0;
            ddr_wdata_req <= 1'b0;
        end else if (burst_active && beat_index == BEATS_PER_LINE) begin
            burst_active <= 1'b0;
            ddr_wdata_req <= 1'b0;
        end else if (!burst_active && ddr_wreq && ddr_wrdy) begin
            burst_active <= 1'b1;
            request_phase <= 0;
            ddr_wdata_req <= 1'b0;
        end else if (burst_active) begin
            ddr_wdata_req <= (request_phase == 3);
            request_phase <= (request_phase == 3) ? 0 : request_phase + 1;
        end else begin
            ddr_wdata_req <= 1'b0;
        end
    end

    assign ddr_wdone = burst_active && ddr_wdata_req && (beat_index == BEATS_PER_LINE-1);

    always @(posedge ddr_clk) begin
        if (!ddr_rstn) begin
            beat_index <= 0;
            captured_count <= 0;
        end else if (!burst_active && ddr_wreq && ddr_wrdy) begin
            beat_index <= 0;
        end else if (burst_active && ddr_wdata_req) begin
            captured_beats[beat_index] <= ddr_wdata;
            captured_count <= captured_count + 1;
            if (beat_index == BEATS_PER_LINE-1) begin
                beat_index <= BEATS_PER_LINE;
            end else begin
                beat_index <= beat_index + 1;
            end
        end
    end

    function automatic [31:0] pixel_word(input integer pixel_x);
        pixel_word = {8'h5a, pixel_x[15:8], pixel_x[7:0], 8'ha5};
    endfunction

    initial begin
        repeat (8) @(posedge ddr_clk);
        ddr_rstn = 1'b1;
        repeat (8) @(posedge ddr_clk);

        @(negedge pix_clk); wr_fsync = 1'b1;
        repeat (3) @(negedge pix_clk);
        wr_fsync = 1'b0;
        repeat (3) @(negedge pix_clk);

        for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
            @(negedge pix_clk);
            wr_en = 1'b1;
            wr_data = pixel_word(x);
        end
        @(negedge pix_clk);
        wr_en = 1'b0;

        while (captured_count < BEATS_PER_LINE && wait_cycles < 50000) begin
            @(posedge ddr_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (captured_count != BEATS_PER_LINE)
            $fatal(1, "TEST_FAIL: DDR capture beat timeout count=%0d expected=%0d", captured_count, BEATS_PER_LINE);
        if (ddr_wr_len != BEATS_PER_LINE)
            $fatal(1, "TEST_FAIL: wrong capture burst length=%0d", ddr_wr_len);

        for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
            lane = x % 8;
            if ($isunknown(captured_beats[x / 8][lane*32 +: 32])) begin
                unknown_words = unknown_words + 1;
                if (unknown_words < 5)
                    $display("UNKNOWN_WORD: pixel_word=%0d beat=%0d lane=%0d", x, x/8, lane);
            end else if (captured_beats[x / 8][lane*32 +: 32] !== pixel_word(x)) begin
                mismatches = mismatches + 1;
                if (mismatches < 5)
                    $display("DATA_MISMATCH: pixel_word=%0d got=%08x expected=%08x", x, captured_beats[x/8][lane*32 +: 32], pixel_word(x));
            end
        end

        if (unknown_words != 0 || mismatches != 0)
            $fatal(1, "TEST_FAIL: 1280-pixel capture unknown_words=%0d mismatches=%0d", unknown_words, mismatches);

        $display("TEST_PASS: wr_buf_capture_1280 beats=%0d words=%0d frame_count=%0d", captured_count, IMAGE_WIDTH, frame_wcnt);
        $finish;
    end
endmodule
