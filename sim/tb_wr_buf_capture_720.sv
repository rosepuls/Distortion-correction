`timescale 1ns/1ps

module tb_wr_buf_capture_720;
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer IMAGE_HEIGHT = 720;
    localparam integer BEATS_PER_LINE = IMAGE_WIDTH / 8;
    localparam integer TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    reg ddr_clk = 1'b0;
    reg pix_clk = 1'b0;
    reg ddr_rstn = 1'b0;
    reg wr_fsync = 1'b0;
    reg wr_en = 1'b0;
    reg [31:0] wr_data = 32'd0;
    reg ddr_wrdy = 1'b1;
    reg ddr_wdata_req = 1'b0;
    wire ddr_wreq;
    wire [27:0] ddr_waddr;
    wire [31:0] ddr_wr_len;
    wire [255:0] ddr_wdata;
    wire [5:0] frame_wcnt;
    wire frame_wirq;
    reg ddr_wdone = 1'b0;

    GTP_GRS GRS_INST(.GRS_N(ddr_rstn));

    reg burst_active = 1'b0;
    integer request_phase = 0;
    integer beat_index = 0;
    integer command_count = 0;
    integer current_line = 0;
    integer captured_pixels = 0;
    integer unknown_pixels = 0;
    integer mismatches = 0;
    integer first_bad_line = -1;
    integer first_bad_x = -1;
    integer drive_x;
    integer pixel_x;
    integer y;
    integer lane;
    integer beat_unknowns;
    integer beat_mismatches;
    integer wait_cycles = 0;
    reg [27:0] first_line_addr;

    always #4 ddr_clk = ~ddr_clk;
    always #6.5 pix_clk = ~pix_clk;

    wr_buf #(
        .ADDR_WIDTH(28), .ADDR_OFFSET(0), .H_NUM(IMAGE_WIDTH), .V_NUM(IMAGE_HEIGHT),
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

    // Stand in for an accepting DDR controller: one 256-bit beat every four
    // DDR clocks, with each accepted command checked as one captured line.
    always @(negedge ddr_clk) begin
        if (!ddr_rstn) begin
            burst_active <= 1'b0;
            request_phase <= 0;
            ddr_wdata_req <= 1'b0;
        end else if (burst_active && ddr_wdone) begin
            burst_active <= 1'b0;
            ddr_wdata_req <= 1'b0;
        end else if (!burst_active && ddr_wreq && ddr_wrdy) begin
            if (ddr_wr_len !== BEATS_PER_LINE)
                $fatal(1, "TEST_FAIL: line %0d burst length=%0d expected=%0d", command_count, ddr_wr_len, BEATS_PER_LINE);
            if (command_count == 0) begin
                first_line_addr = ddr_waddr;
                if ((first_line_addr != 28'd0) && (first_line_addr != 28'h0400000))
                    $fatal(1, "TEST_FAIL: unexpected input frame base=%0d", first_line_addr);
            end else if (ddr_waddr !== first_line_addr + command_count * IMAGE_WIDTH) begin
                $fatal(1, "TEST_FAIL: line %0d address=%0d expected=%0d", command_count, ddr_waddr, first_line_addr + command_count * IMAGE_WIDTH);
            end
            current_line <= command_count;
            command_count <= command_count + 1;
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

    always @(posedge ddr_clk) begin
        if (!ddr_rstn) begin
            beat_index <= 0;
            captured_pixels <= 0;
            ddr_wdone <= 1'b0;
        end else begin
            ddr_wdone <= 1'b0;
            if (burst_active && ddr_wdata_req) begin
                beat_unknowns = 0;
                beat_mismatches = 0;
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    pixel_x = beat_index * 8 + lane;
                    if ($isunknown(ddr_wdata[lane*32 +: 32])) begin
                        beat_unknowns = beat_unknowns + 1;
                        if (first_bad_line < 0) begin
                            first_bad_line <= current_line;
                            first_bad_x <= pixel_x;
                        end
                    end else if (ddr_wdata[lane*32 +: 32] !== pixel_word(current_line, pixel_x)) begin
                        beat_mismatches = beat_mismatches + 1;
                        if (first_bad_line < 0) begin
                            first_bad_line <= current_line;
                            first_bad_x <= pixel_x;
                        end
                    end
                end
                unknown_pixels <= unknown_pixels + beat_unknowns;
                mismatches <= mismatches + beat_mismatches;
                captured_pixels <= captured_pixels + 8;
                if (beat_index == BEATS_PER_LINE-1) begin
                    beat_index <= 0;
                    ddr_wdone <= 1'b1;
                end else begin
                    beat_index <= beat_index + 1;
                end
            end
        end
    end

    function automatic [31:0] pixel_word(input integer pixel_y, input integer pixel_x);
        pixel_word = {pixel_y[15:0], pixel_x[15:0]};
    endfunction

    initial begin
        repeat (8) @(posedge ddr_clk);
        ddr_rstn = 1'b1;
        repeat (8) @(posedge ddr_clk);

        @(negedge pix_clk); wr_fsync = 1'b1;
        repeat (3) @(negedge pix_clk);
        wr_fsync = 1'b0;
        repeat (4) @(negedge pix_clk);

        for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
            for (drive_x = 0; drive_x < IMAGE_WIDTH; drive_x = drive_x + 1) begin
                @(negedge pix_clk);
                wr_en = 1'b1;
                wr_data = pixel_word(y, drive_x);
            end
            @(negedge pix_clk);
            wr_en = 1'b0;
            repeat (4) @(negedge pix_clk);
        end

        while (captured_pixels < TOTAL_PIXELS && wait_cycles < 5000000) begin
            @(posedge ddr_clk);
            wait_cycles = wait_cycles + 1;
        end
        repeat (8) @(posedge ddr_clk);

        if (captured_pixels != TOTAL_PIXELS)
            $fatal(1, "TEST_FAIL: captured_pixels=%0d expected=%0d commands=%0d", captured_pixels, TOTAL_PIXELS, command_count);
        if (command_count != IMAGE_HEIGHT)
            $fatal(1, "TEST_FAIL: line commands=%0d expected=%0d", command_count, IMAGE_HEIGHT);
        if (unknown_pixels != 0 || mismatches != 0)
            $fatal(1, "TEST_FAIL: 720p capture unknown=%0d mismatch=%0d first_bad=(%0d,%0d)", unknown_pixels, mismatches, first_bad_line, first_bad_x);

        $display("TEST_PASS: wr_buf_capture_720 lines=%0d pixels=%0d beats=%0d frame_count=%0d", command_count, captured_pixels, command_count*BEATS_PER_LINE, frame_wcnt);
        $finish;
    end
endmodule
