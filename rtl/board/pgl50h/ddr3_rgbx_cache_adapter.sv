`timescale 1ns/1ps

// Bridges the portable RGBX Tile Cache interface to the MES50HP DDR command
// controller.  The cache uses byte addresses; wr_rd_ctrl_top uses 32-bit-word
// addresses.  The adapter also derives burst-last from the accepted beat count
// because the controller exposes completion separately from read data.
module ddr3_rgbx_cache_adapter #(
    parameter integer CACHE_ADDR_WIDTH = 32,
    parameter integer CTRL_ADDR_WIDTH = 28
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [CTRL_ADDR_WIDTH-1:0]    frame_base_word_addr,

    input  wire                         cache_cmd_en,
    output wire                         cache_cmd_ready,
    input  wire [CACHE_ADDR_WIDTH-1:0]  cache_cmd_byte_addr,
    input  wire [31:0]                  cache_cmd_len,

    output wire                         ctrl_cmd_en,
    input  wire                         ctrl_cmd_ready,
    output wire [CTRL_ADDR_WIDTH-1:0]   ctrl_cmd_word_addr,
    output wire [31:0]                  ctrl_cmd_len,

    input  wire                         ctrl_data_valid,
    output wire                         ctrl_data_ready,
    input  wire [255:0]                 ctrl_data,

    output wire                         cache_data_valid,
    input  wire                         cache_data_ready,
    output wire [255:0]                 cache_data,
    output wire                         cache_data_last
);
    reg transaction_active;
    reg [31:0] beats_remaining;

    wire command_fire = cache_cmd_en && cache_cmd_ready;
    wire data_fire = cache_data_valid && cache_data_ready;

    assign cache_cmd_ready = rst_n && !transaction_active && ctrl_cmd_ready;
    assign ctrl_cmd_en = cache_cmd_en && !transaction_active && rst_n;
    assign ctrl_cmd_word_addr = frame_base_word_addr
                                + cache_cmd_byte_addr[CTRL_ADDR_WIDTH+1:2];
    assign ctrl_cmd_len = cache_cmd_len;

    assign cache_data_valid = transaction_active && ctrl_data_valid;
    assign ctrl_data_ready = transaction_active && cache_data_ready;
    assign cache_data = ctrl_data;
    assign cache_data_last = cache_data_valid && (beats_remaining == 32'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            transaction_active <= 1'b0;
            beats_remaining <= 32'd0;
        end else begin
            if (command_fire) begin
                transaction_active <= (cache_cmd_len != 0);
                beats_remaining <= cache_cmd_len;
            end else if (data_fire) begin
                if (beats_remaining == 32'd1) begin
                    transaction_active <= 1'b0;
                    beats_remaining <= 32'd0;
                end else begin
                    beats_remaining <= beats_remaining - 1'b1;
                end
            end
        end
    end
endmodule
