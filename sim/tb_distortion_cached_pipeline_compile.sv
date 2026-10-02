`timescale 1ns/1ps

module tb_distortion_cached_pipeline_compile;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire in_ready;
    wire req_valid;
    wire rsp_ready;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;
    wire cache_rd_cmd_en;
    wire [31:0] cache_rd_cmd_addr;
    wire [31:0] cache_rd_cmd_len;
    wire cache_rd_data_ready;

    always #5 clk = ~clk;

    distortion_image_pipeline #(
        .IMAGE_WIDTH(64),
        .IMAGE_HEIGHT(32),
        .COORD_WIDTH(12),
        .ADDR_WIDTH(32),
        .USE_OPTIMIZED_CORE(1),
        .USE_TILE_CACHE(1),
        .FRAME_BASE_BYTE_ADDR(32'h00002000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(1'b0),
        .in_sof(1'b0),
        .in_eol(1'b0),
        .in_ready(in_ready),
        .cfg_fx_q19(32'sd0),
        .cfg_fy_q19(32'sd0),
        .cfg_cx_q19(32'sd0),
        .cfg_cy_q19(32'sd0),
        .cfg_inv_fx_q30(32'sd0),
        .cfg_inv_fy_q30(32'sd0),
        .cfg_k1_q28(32'sd0),
        .cfg_k2_q28(32'sd0),
        .cfg_p1_q28(32'sd0),
        .cfg_p2_q28(32'sd0),
        .req_valid(req_valid),
        .req_ready(1'b0),
        .req_addr(),
        .rsp_valid(1'b0),
        .rsp_ready(rsp_ready),
        .rsp_data(24'd0),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol),
        .cache_rd_cmd_en(cache_rd_cmd_en),
        .cache_rd_cmd_ready(1'b0),
        .cache_rd_cmd_addr(cache_rd_cmd_addr),
        .cache_rd_cmd_len(cache_rd_cmd_len),
        .cache_rd_data_valid(1'b0),
        .cache_rd_data_ready(cache_rd_data_ready),
        .cache_rd_data(256'd0),
        .cache_rd_data_last(1'b0)
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (5) @(posedge clk);
        $display("TEST_PASS: distortion_cached_pipeline_compile");
        $finish;
    end
endmodule
