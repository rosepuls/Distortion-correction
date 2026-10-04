`timescale 1ns/1ps

module tb_pixel_tile_cache_packed;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg invalidate = 1'b0;
    reg lookup_valid = 1'b0;
    wire lookup_ready;
    reg [11:0] lookup_x0 = 12'd0;
    reg [11:0] lookup_y0 = 12'd0;
    wire lookup_rsp_valid;
    reg lookup_rsp_ready = 1'b1;
    wire [31:0] pixel_p00;
    wire [31:0] pixel_p10;
    wire [31:0] pixel_p01;
    wire [31:0] pixel_p11;
    wire cache_hit;
    wire coord_valid;
    wire fill_req_valid;
    reg fill_req_ready = 1'b1;
    wire [11:0] fill_tile_x;
    wire [11:0] fill_tile_y;
    wire [1:0] fill_row_index;
    reg fill_data_valid = 1'b0;
    wire fill_data_ready;
    reg [255:0] fill_data = 256'd0;
    reg [1:0] fill_data_row_index = 2'd0;
    reg [1:0] fill_data_beat_index = 2'd0;

    always #5 clk = ~clk;

    pixel_tile_cache #(
        .IMAGE_WIDTH(640),
        .IMAGE_HEIGHT(40),
        .SET_COUNT(16),
        .WAYS(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .invalidate(invalidate),
        .lookup_valid(lookup_valid),
        .lookup_ready(lookup_ready),
        .lookup_x0(lookup_x0),
        .lookup_y0(lookup_y0),
        .lookup_rsp_valid(lookup_rsp_valid),
        .lookup_rsp_ready(lookup_rsp_ready),
        .pixel_p00(pixel_p00),
        .pixel_p10(pixel_p10),
        .pixel_p01(pixel_p01),
        .pixel_p11(pixel_p11),
        .cache_hit(cache_hit),
        .coord_valid(coord_valid),
        .fill_req_valid(fill_req_valid),
        .fill_req_ready(fill_req_ready),
        .fill_tile_x(fill_tile_x),
        .fill_tile_y(fill_tile_y),
        .fill_row_index(fill_row_index),
        .fill_data_valid(fill_data_valid),
        .fill_data_ready(fill_data_ready),
        .fill_data(fill_data),
        .fill_data_row_index(fill_data_row_index),
        .fill_data_beat_index(fill_data_beat_index)
    );

    initial begin
        if ($bits(dut.bank0_ram.rd_data) != 128
            || $bits(dut.bank1_ram.rd_data) != 128
            || $bits(dut.bank2_ram.rd_data) != 128
            || $bits(dut.bank3_ram.rd_data) != 128) begin
            $fatal(1, "TEST_FAIL: cache banks must expose four RGBX pixels per synchronous word");
        end

        $display("TEST_PASS: pixel_tile_cache_packed");
        $finish;
    end
endmodule
