`timescale 1ns/1ps

// Packs a possibly-stalled RGB888 algorithm stream into 256-bit DDR bursts.
// Each ping-pong line bank is an official wr_fram_buf block-RAM IP.  An RTL
// array with eight simultaneous 32-bit reads is replicated into LUT RAM by
// PDS and cannot be placed alongside the DDR3 PHY.
module algorithm_frame_writer #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer DDR_ADDR_WIDTH = 28,
    parameter [DDR_ADDR_WIDTH-1:0] OUTPUT_BASE_ADDR = 28'h0800000,
    parameter integer SIMULATION = 0
) (
    input wire clk, input wire rst_n,
    input wire pixel_valid, input wire [23:0] pixel_data,
    input wire pixel_sof, input wire pixel_eol,
    output reg overflow, output reg frame_complete,
    output reg wr_cmd_en, output reg [DDR_ADDR_WIDTH-1:0] wr_cmd_addr,
    output wire [31:0] wr_cmd_len, input wire wr_cmd_ready,
    input wire wr_cmd_done, input wire wr_bac,
    output wire [255:0] wr_ctrl_data, input wire wr_data_re
);
    localparam integer WORDS_PER_LINE = (IMAGE_WIDTH * 24) / 32;
    localparam integer BEATS_PER_LINE = WORDS_PER_LINE / 8;
    localparam integer WORD_INDEX_WIDTH =
        (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE);
    localparam integer BEAT_INDEX_WIDTH =
        (BEATS_PER_LINE <= 1) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer LINE_INDEX_WIDTH =
        (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);

    reg [1:0] bank_full;
    reg [LINE_INDEX_WIDTH-1:0] bank_line0, bank_line1;
    reg fill_bank;
    reg [WORD_INDEX_WIDTH-1:0] fill_word_index;
    reg [LINE_INDEX_WIDTH-1:0] fill_line_index;
    reg [1:0] pixel_mod4;
    reg [23:0] previous_pixel;

    reg bank_write_en, bank_write_sel;
    reg [WORD_INDEX_WIDTH-1:0] bank_write_addr;
    reg [31:0] bank_write_data;

    reg drain_state, drain_bank;
    reg [BEAT_INDEX_WIDTH-1:0] drain_beat_index;
    wire [WORD_INDEX_WIDTH-1:0] drain_word_base =
        {{(WORD_INDEX_WIDTH-BEAT_INDEX_WIDTH){1'b0}}, drain_beat_index} << 3;
    wire [LINE_INDEX_WIDTH-1:0] selected_line;
    wire [255:0] line_bank0_data, line_bank1_data;
    wire packed_word_valid = pixel_valid && !pixel_sof && (pixel_mod4 != 2'd0);
    reg [31:0] packed_word;

    always @(*) begin
        case (pixel_mod4)
            2'd1: packed_word = {pixel_data[7:0], previous_pixel};
            2'd2: packed_word = {pixel_data[15:0], previous_pixel[23:8]};
            default: packed_word = {pixel_data, previous_pixel[23:16]};
        endcase
    end

    assign wr_cmd_len = BEATS_PER_LINE;
    assign selected_line = drain_bank ? bank_line1 : bank_line0;
    assign wr_ctrl_data = drain_bank ? line_bank1_data : line_bank0_data;

    generate
        if (SIMULATION != 0) begin : g_simulation_line_banks
            reg [31:0] sim_line_bank0 [0:WORDS_PER_LINE-1];
            reg [31:0] sim_line_bank1 [0:WORDS_PER_LINE-1];
            always @(posedge clk) begin
                if (bank_write_en) begin
                    if (bank_write_sel)
                        sim_line_bank1[bank_write_addr] <= bank_write_data;
                    else
                        sim_line_bank0[bank_write_addr] <= bank_write_data;
                end
            end
            assign line_bank0_data = {
                sim_line_bank0[drain_word_base + 7],
                sim_line_bank0[drain_word_base + 6],
                sim_line_bank0[drain_word_base + 5],
                sim_line_bank0[drain_word_base + 4],
                sim_line_bank0[drain_word_base + 3],
                sim_line_bank0[drain_word_base + 2],
                sim_line_bank0[drain_word_base + 1],
                sim_line_bank0[drain_word_base]};
            assign line_bank1_data = {
                sim_line_bank1[drain_word_base + 7],
                sim_line_bank1[drain_word_base + 6],
                sim_line_bank1[drain_word_base + 5],
                sim_line_bank1[drain_word_base + 4],
                sim_line_bank1[drain_word_base + 3],
                sim_line_bank1[drain_word_base + 2],
                sim_line_bank1[drain_word_base + 1],
                sim_line_bank1[drain_word_base]};
        end else begin : g_hardware_line_banks
            // The imported IP has fixed 12-bit write and 9-bit read ports.
            wr_fram_buf line_bank0_ram (
                .wr_data(bank_write_data),
                .wr_addr({{(12-WORD_INDEX_WIDTH){1'b0}}, bank_write_addr}),
                .wr_en(bank_write_en && !bank_write_sel), .wr_clk(clk), .wr_rst(!rst_n),
                .rd_data(line_bank0_data),
                .rd_addr({{(9-BEAT_INDEX_WIDTH){1'b0}}, drain_beat_index}),
                .rd_clk(clk), .rd_rst(!rst_n)
            );
            wr_fram_buf line_bank1_ram (
                .wr_data(bank_write_data),
                .wr_addr({{(12-BEAT_INDEX_WIDTH){1'b0}}, bank_write_addr}),
                .wr_en(bank_write_en && bank_write_sel), .wr_clk(clk), .wr_rst(!rst_n),
                .rd_data(line_bank1_data),
                .rd_addr({{(9-BEAT_INDEX_WIDTH){1'b0}}, drain_beat_index}),
                .rd_clk(clk), .rd_rst(!rst_n)
            );
        end
    endgenerate

    initial begin
        if ((IMAGE_WIDTH % 32) != 0)
            $error("algorithm_frame_writer requires IMAGE_WIDTH divisible by 32");
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_full <= 2'b00;
            bank_line0 <= 0; bank_line1 <= 0;
            fill_bank <= 0; fill_word_index <= 0; fill_line_index <= 0;
            pixel_mod4 <= 0; previous_pixel <= 0;
            bank_write_en <= 0; bank_write_sel <= 0; bank_write_addr <= 0; bank_write_data <= 0;
            drain_state <= 0; drain_bank <= 0; drain_beat_index <= 0;
            wr_cmd_en <= 0; wr_cmd_addr <= OUTPUT_BASE_ADDR;
            overflow <= 0; frame_complete <= 0;
        end else begin
            wr_cmd_en <= 0;
            frame_complete <= 0;
            bank_write_en <= 0;

            if (pixel_valid) begin
                if (bank_full[fill_bank]) begin
                    overflow <= 1'b1;
                end else if (pixel_sof) begin
                    fill_line_index <= 0;
                    fill_word_index <= 0;
                    pixel_mod4 <= 2'd1;
                    previous_pixel <= pixel_data;
                end else begin
                    if (packed_word_valid) begin
                        bank_write_en <= 1'b1;
                        bank_write_sel <= fill_bank;
                        bank_write_addr <= fill_word_index;
                        bank_write_data <= packed_word;
                        fill_word_index <= fill_word_index + 1'b1;
                    end

                    case (pixel_mod4)
                        2'd0: begin previous_pixel <= pixel_data; pixel_mod4 <= 2'd1; end
                        2'd1: begin previous_pixel <= pixel_data; pixel_mod4 <= 2'd2; end
                        2'd2: begin previous_pixel <= pixel_data; pixel_mod4 <= 2'd3; end
                        default: begin previous_pixel <= pixel_data; pixel_mod4 <= 2'd0; end
                    endcase

                    if (pixel_eol) begin
                        bank_full[fill_bank] <= 1'b1;
                        if (fill_bank) bank_line1 <= fill_line_index;
                        else bank_line0 <= fill_line_index;
                        fill_bank <= ~fill_bank;
                        fill_word_index <= 0;
                        pixel_mod4 <= 0;
                        if (fill_line_index != IMAGE_HEIGHT - 1)
                            fill_line_index <= fill_line_index + 1'b1;
                    end
                end
            end

            if (!drain_state) begin
                drain_beat_index <= 0;
                if (bank_full[drain_bank] && wr_cmd_ready) begin
                    wr_cmd_addr <= OUTPUT_BASE_ADDR + selected_line * WORDS_PER_LINE;
                    wr_cmd_en <= 1'b1;
                    drain_state <= 1'b1;
                end
            end else begin
                if (wr_bac && (drain_beat_index != 0))
                    drain_beat_index <= drain_beat_index - 1'b1;
                else if (wr_data_re)
                    drain_beat_index <= drain_beat_index + 1'b1;

                if (wr_cmd_done) begin
                    bank_full[drain_bank] <= 1'b0;
                    if (selected_line == IMAGE_HEIGHT - 1)
                        frame_complete <= 1'b1;
                    drain_bank <= ~drain_bank;
                    drain_state <= 1'b0;
                end
            end
        end
    end
endmodule
