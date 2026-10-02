`timescale 1ns/1ps

// RGBX8888 frame reader used by the 1080P30 board path.  The simulation
// storage is a frame-sized word array; the synthesis project can replace the
// array with the matching dual-clock vendor RAM without changing the command
// and pixel-clock interfaces.
module ddr3_frame_reader_rgbx #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer DDR_ADDR_WIDTH = 32,
    parameter [DDR_ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = {DDR_ADDR_WIDTH{1'b0}}
) (
    input  wire                         ddr_clk,
    input  wire                         ddr_rst_n,
    input  wire                         pixel_clk,
    input  wire                         pixel_rst_n,
    input  wire                         display_enable,
    input  wire                         rd_fsync,
    input  wire                         rd_en,
    output wire                         vout_de,
    output reg  [23:0]                  vout_data,
    output reg                          underflow,
    output reg                          rd_cmd_en,
    output reg  [DDR_ADDR_WIDTH-1:0]    rd_cmd_addr,
    output wire [31:0]                  rd_cmd_len,
    input  wire                         rd_cmd_ready,
    input  wire                         rd_cmd_done,
    input  wire [255:0]                 rd_data,
    input  wire                         rd_data_valid,
    output wire                         rd_data_ready
);
    localparam integer BEATS_PER_LINE = IMAGE_WIDTH / 8;
    localparam integer LINE_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT + 1);
    localparam integer WORD_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam integer READ_INDEX_WIDTH =
        (IMAGE_WIDTH * IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_WIDTH * IMAGE_HEIGHT);

    localparam [1:0] CMD_IDLE = 2'd0;
    localparam [1:0] CMD_BUSY = 2'd1;

    reg fsync_ddr_1;
    reg fsync_ddr_2;
    reg fsync_ddr_3;
    reg active_ddr_1;
    reg active_ddr_2;
    reg active_ddr_3;
    wire frame_start_ddr = fsync_ddr_2 && !fsync_ddr_3;
    wire line_start_ddr = active_ddr_2 && !active_ddr_3;

    reg [1:0] cmd_state;
    reg cmd_pending;
    reg [LINE_WIDTH-1:0] next_line_index;
    reg [LINE_WIDTH-1:0] write_line_index;
    reg [WORD_WIDTH-1:0] write_word_index;
    reg prefetch_seen_ddr;

    reg [31:0] sim_words [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];
    integer lane;
    integer write_index;

    assign rd_cmd_len = BEATS_PER_LINE;
    assign rd_data_ready = display_enable && ddr_rst_n;

    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            fsync_ddr_1 <= 1'b0;
            fsync_ddr_2 <= 1'b0;
            fsync_ddr_3 <= 1'b0;
            active_ddr_1 <= 1'b0;
            active_ddr_2 <= 1'b0;
            active_ddr_3 <= 1'b0;
        end else begin
            fsync_ddr_1 <= rd_fsync;
            fsync_ddr_2 <= fsync_ddr_1;
            fsync_ddr_3 <= fsync_ddr_2;
            active_ddr_1 <= rd_en;
            active_ddr_2 <= active_ddr_1;
            active_ddr_3 <= active_ddr_2;
        end
    end

    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            cmd_state <= CMD_IDLE;
            cmd_pending <= 1'b0;
            next_line_index <= 0;
            write_line_index <= 0;
            write_word_index <= 0;
            prefetch_seen_ddr <= 1'b0;
            rd_cmd_en <= 1'b0;
            rd_cmd_addr <= FRAME_BASE_BYTE_ADDR;
        end else begin
            rd_cmd_en <= 1'b0;

            if (!display_enable) begin
                cmd_state <= CMD_IDLE;
                cmd_pending <= 1'b0;
                next_line_index <= 0;
                write_word_index <= 0;
                prefetch_seen_ddr <= 1'b0;
            end else begin
                if (frame_start_ddr) begin
                    cmd_pending <= 1'b1;
                    next_line_index <= 0;
                    prefetch_seen_ddr <= 1'b0;
                end else if (line_start_ddr && (next_line_index < IMAGE_HEIGHT)) begin
                    cmd_pending <= 1'b1;
                end

                if ((cmd_state == CMD_IDLE) && cmd_pending && rd_cmd_ready) begin
                    rd_cmd_addr <= FRAME_BASE_BYTE_ADDR
                                   + next_line_index * IMAGE_WIDTH * 4;
                    rd_cmd_en <= 1'b1;
                    write_line_index <= next_line_index;
                    write_word_index <= 0;
                    next_line_index <= next_line_index + 1'b1;
                    cmd_pending <= 1'b0;
                    cmd_state <= CMD_BUSY;
                end else if ((cmd_state == CMD_BUSY) && rd_cmd_done) begin
                    cmd_state <= CMD_IDLE;
                end

                if (rd_data_valid && rd_data_ready) begin
                    for (lane = 0; lane < 8; lane = lane + 1) begin
                        write_index = write_line_index * IMAGE_WIDTH
                                      + write_word_index + lane;
                        sim_words[write_index] <= rd_data[lane*32 +: 32];
                    end
                    write_word_index <= write_word_index + 8;
                    prefetch_seen_ddr <= 1'b1;
                end
            end
        end
    end

    reg fsync_pixel_d;
    reg rd_en_d;
    reg [READ_INDEX_WIDTH-1:0] read_pixel_index;
    wire frame_start_pixel = rd_fsync && !fsync_pixel_d;
    assign vout_de = rd_en_d;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            fsync_pixel_d <= 1'b0;
            rd_en_d <= 1'b0;
            read_pixel_index <= 0;
            vout_data <= 24'd0;
            underflow <= 1'b0;
        end else begin
            fsync_pixel_d <= rd_fsync;
            rd_en_d <= rd_en;

            if (frame_start_pixel)
                read_pixel_index <= 0;
            else if (rd_en)
                read_pixel_index <= read_pixel_index + 1'b1;

            if (rd_en)
                vout_data <= sim_words[read_pixel_index][31:8];
            else
                vout_data <= 24'd0;

            if (rd_en && !prefetch_seen_ddr)
                underflow <= 1'b1;
            if (frame_start_pixel)
                underflow <= 1'b0;
        end
    end
endmodule
