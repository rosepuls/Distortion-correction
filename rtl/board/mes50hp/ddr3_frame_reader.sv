`timescale 1ns/1ps

// Fixed-base corrected-frame reader. It prefetches one packed RGB888 line at
// frame start and one following line at each active-line edge. The synthesis
// branch uses the official 256-bit-to-32-bit dual-clock RAM.
module ddr3_frame_reader #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer DDR_ADDR_WIDTH = 28,
    parameter [DDR_ADDR_WIDTH-1:0] FRAME_BASE_ADDR = 28'h0800000,
    parameter integer SIMULATION = 0
) (
    input  wire                      ddr_clk,
    input  wire                      ddr_rst_n,
    input  wire                      pixel_clk,
    input  wire                      pixel_rst_n,
    input  wire                      display_enable,
    input  wire                      rd_fsync,
    input  wire                      rd_en,
    output wire                      vout_de,
    output reg  [23:0]               vout_data,
    output reg                       underflow,

    output reg                       rd_cmd_en,
    output reg  [DDR_ADDR_WIDTH-1:0] rd_cmd_addr,
    output wire [31:0]               rd_cmd_len,
    input  wire                      rd_cmd_ready,
    input  wire                      rd_cmd_done,
    input  wire [255:0]              rd_data,
    input  wire                      rd_data_valid,
    output wire                      rd_data_ready
);
    localparam integer WORDS_PER_LINE = (IMAGE_WIDTH * 24) / 32;
    localparam integer BEATS_PER_LINE = WORDS_PER_LINE / 8;
    localparam integer LINE_INDEX_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT + 1);

    localparam CMD_IDLE = 1'b0;
    localparam CMD_BUSY = 1'b1;

    reg fsync_ddr_1;
    reg fsync_ddr_2;
    reg fsync_ddr_3;
    reg active_ddr_1;
    reg active_ddr_2;
    reg active_ddr_3;
    wire frame_start_ddr;
    wire line_start_ddr;

    reg cmd_state;
    reg cmd_pending;
    reg [LINE_INDEX_WIDTH-1:0] next_line_index;
    reg [8:0] write_beat_addr;
    reg prefetch_seen_ddr;

    assign frame_start_ddr = fsync_ddr_2 && !fsync_ddr_3;
    assign line_start_ddr = active_ddr_2 && !active_ddr_3;
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
            next_line_index <= {LINE_INDEX_WIDTH{1'b0}};
            rd_cmd_en <= 1'b0;
            rd_cmd_addr <= FRAME_BASE_ADDR;
            write_beat_addr <= 9'd0;
            prefetch_seen_ddr <= 1'b0;
        end else begin
            rd_cmd_en <= 1'b0;

            if (!display_enable) begin
                cmd_state <= CMD_IDLE;
                cmd_pending <= 1'b0;
                next_line_index <= {LINE_INDEX_WIDTH{1'b0}};
                write_beat_addr <= 9'd0;
                prefetch_seen_ddr <= 1'b0;
            end else begin
                if (frame_start_ddr) begin
                    cmd_pending <= 1'b1;
                    next_line_index <= {LINE_INDEX_WIDTH{1'b0}};
                    write_beat_addr <= 9'd0;
                    prefetch_seen_ddr <= 1'b0;
                end else if (line_start_ddr && (next_line_index < IMAGE_HEIGHT)) begin
                    cmd_pending <= 1'b1;
                end

                if ((cmd_state == CMD_IDLE) && cmd_pending && rd_cmd_ready) begin
                    rd_cmd_addr <= FRAME_BASE_ADDR + next_line_index * WORDS_PER_LINE;
                    rd_cmd_en <= 1'b1;
                    cmd_pending <= 1'b0;
                    next_line_index <= next_line_index + 1'b1;
                    cmd_state <= CMD_BUSY;
                end else if ((cmd_state == CMD_BUSY) && rd_cmd_done) begin
                    cmd_state <= CMD_IDLE;
                end

                if (rd_data_valid && rd_data_ready) begin
                    write_beat_addr <= write_beat_addr + 1'b1;
                    prefetch_seen_ddr <= 1'b1;
                end
            end
        end
    end

    reg [11:0] read_word_addr;
    reg [1:0] pixel_mod4;
    reg rd_en_1d;
    reg rd_en_2d;
    reg fsync_pixel_1d;
    reg [31:0] buffer_word_1d;
    wire [31:0] buffer_word;
    wire read_word_enable;
    wire frame_start_pixel;

    assign frame_start_pixel = rd_fsync && !fsync_pixel_1d;
    assign read_word_enable = rd_en && (pixel_mod4 != 2'd3);
    assign vout_de = rd_en_2d;

    generate
        if (SIMULATION != 0) begin : generate_sim_buffer
            reg [31:0] sim_words [0:4095];
            reg [31:0] sim_read_word;
            integer lane;

            always @(posedge ddr_clk) begin
                if (rd_data_valid && rd_data_ready) begin
                    for (lane = 0; lane < 8; lane = lane + 1)
                        sim_words[{write_beat_addr, 3'b000} + lane] <= rd_data[lane*32 +: 32];
                end
            end

            always @(posedge pixel_clk) begin
                if (!pixel_rst_n)
                    sim_read_word <= 32'd0;
                else
                    sim_read_word <= sim_words[read_word_addr];
            end

            assign buffer_word = sim_read_word;
        end else begin : generate_pango_buffer
            rd_fram_buf output_line_buffer (
                .wr_data(rd_data),
                .wr_addr(write_beat_addr),
                .wr_en(rd_data_valid && rd_data_ready),
                .wr_clk(ddr_clk),
                .wr_rst(~ddr_rst_n),
                .rd_data(buffer_word),
                .rd_addr(read_word_addr),
                .rd_clk(pixel_clk),
                .rd_rst(~pixel_rst_n)
            );
        end
    endgenerate

    reg prefetch_pixel_1;
    reg prefetch_pixel_2;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            rd_en_1d <= 1'b0;
            rd_en_2d <= 1'b0;
            fsync_pixel_1d <= 1'b0;
            read_word_addr <= 12'd0;
            pixel_mod4 <= 2'd0;
            buffer_word_1d <= 32'd0;
            vout_data <= 24'd0;
            prefetch_pixel_1 <= 1'b0;
            prefetch_pixel_2 <= 1'b0;
            underflow <= 1'b0;
        end else begin
            rd_en_1d <= rd_en;
            rd_en_2d <= rd_en_1d;
            fsync_pixel_1d <= rd_fsync;
            buffer_word_1d <= buffer_word;
            prefetch_pixel_1 <= prefetch_seen_ddr;
            prefetch_pixel_2 <= prefetch_pixel_1;

            if (frame_start_pixel) begin
                read_word_addr <= 12'd0;
                pixel_mod4 <= 2'd0;
                underflow <= 1'b0;
            end else begin
                if (read_word_enable)
                    read_word_addr <= read_word_addr + 1'b1;

                if (rd_en)
                    pixel_mod4 <= pixel_mod4 + 1'b1;
                else
                    pixel_mod4 <= 2'd0;

                if (rd_en && !prefetch_pixel_2)
                    underflow <= 1'b1;
            end

            if (rd_en_1d) begin
                case (pixel_mod4)
                    2'd1: vout_data <= buffer_word[23:0];
                    2'd2: vout_data <= {buffer_word[15:0], buffer_word_1d[31:24]};
                    2'd3: vout_data <= {buffer_word[7:0], buffer_word_1d[31:16]};
                    default: vout_data <= buffer_word_1d[31:8];
                endcase
            end else begin
                vout_data <= 24'd0;
            end
        end
    end
endmodule
