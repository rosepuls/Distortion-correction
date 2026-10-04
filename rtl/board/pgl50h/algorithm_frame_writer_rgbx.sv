`timescale 1ns/1ps

// RGBX8888 frame writer: one 32-bit word per pixel and eight words per
// 256-bit DDR beat.  The two line banks allow capture of the next line while
// the previous line is being drained to DDR.
module algorithm_frame_writer_rgbx #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer DDR_ADDR_WIDTH = 32,
    parameter [DDR_ADDR_WIDTH-1:0] OUTPUT_BASE_ADDR = {DDR_ADDR_WIDTH{1'b0}},
    parameter integer SIMULATION = 0
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         pixel_valid,
    input  wire [23:0]                  pixel_data,
    input  wire                         pixel_sof,
    input  wire                         pixel_eol,
    output reg                          overflow,
    output reg                          frame_complete,
    output reg                          wr_cmd_en,
    output reg [DDR_ADDR_WIDTH-1:0]     wr_cmd_addr,
    output wire [31:0]                  wr_cmd_len,
    input  wire                         wr_cmd_ready,
    input  wire                         wr_cmd_done,
    input  wire                         wr_bac,
    output wire [255:0]                 wr_ctrl_data,
    input  wire                         wr_data_re
);
    localparam integer BEATS_PER_LINE = IMAGE_WIDTH / 8;
    localparam integer WORD_INDEX_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam integer BEAT_INDEX_WIDTH = (BEATS_PER_LINE <= 1) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer LINE_INDEX_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);

    reg [1:0] bank_full;
    reg [LINE_INDEX_WIDTH-1:0] bank_line0;
    reg [LINE_INDEX_WIDTH-1:0] bank_line1;
    reg fill_bank;
    reg [WORD_INDEX_WIDTH-1:0] fill_word_index;
    reg [LINE_INDEX_WIDTH-1:0] fill_line_index;
    reg drain_active;
    reg drain_bank;
    reg [BEAT_INDEX_WIDTH-1:0] drain_beat_index;
    reg bank_write_en;
    reg bank_write_sel;
    reg [WORD_INDEX_WIDTH-1:0] bank_write_addr;
    reg [31:0] bank_write_data;
    wire [WORD_INDEX_WIDTH-1:0] drain_word_base = drain_beat_index << 3;
    wire [255:0] line_bank0_data;
    wire [255:0] line_bank1_data;

    generate
        if (SIMULATION != 0) begin : g_simulation_line_banks
            reg [31:0] sim_line_bank0 [0:IMAGE_WIDTH-1];
            reg [31:0] sim_line_bank1 [0:IMAGE_WIDTH-1];

            always @(posedge clk) begin
                if (bank_write_en) begin
                    if (bank_write_sel)
                        sim_line_bank1[bank_write_addr] <= bank_write_data;
                    else
                        sim_line_bank0[bank_write_addr] <= bank_write_data;
                end
            end

            assign line_bank0_data = {
                sim_line_bank0[drain_word_base + 7], sim_line_bank0[drain_word_base + 6],
                sim_line_bank0[drain_word_base + 5], sim_line_bank0[drain_word_base + 4],
                sim_line_bank0[drain_word_base + 3], sim_line_bank0[drain_word_base + 2],
                sim_line_bank0[drain_word_base + 1], sim_line_bank0[drain_word_base]
            };
            assign line_bank1_data = {
                sim_line_bank1[drain_word_base + 7], sim_line_bank1[drain_word_base + 6],
                sim_line_bank1[drain_word_base + 5], sim_line_bank1[drain_word_base + 4],
                sim_line_bank1[drain_word_base + 3], sim_line_bank1[drain_word_base + 2],
                sim_line_bank1[drain_word_base + 1], sim_line_bank1[drain_word_base]
            };
        end else begin : g_pango_line_banks
            // This is the vendor-generated 32-bit-write / 256-bit-read DRM
            // used by the official DDR examples.  It keeps the board build
            // independent of inferred multi-read-port LUT RAM.
            wr_fram_buf line_bank0_ram (
                .wr_data(bank_write_data),
                .wr_addr({{(12-WORD_INDEX_WIDTH){1'b0}}, bank_write_addr}),
                .wr_en(bank_write_en && !bank_write_sel),
                .wr_clk(clk), .wr_rst(!rst_n),
                .rd_data(line_bank0_data),
                .rd_addr({{(9-BEAT_INDEX_WIDTH){1'b0}}, drain_beat_index}),
                .rd_clk(clk), .rd_rst(!rst_n)
            );
            wr_fram_buf line_bank1_ram (
                .wr_data(bank_write_data),
                .wr_addr({{(12-WORD_INDEX_WIDTH){1'b0}}, bank_write_addr}),
                .wr_en(bank_write_en && bank_write_sel),
                .wr_clk(clk), .wr_rst(!rst_n),
                .rd_data(line_bank1_data),
                .rd_addr({{(9-BEAT_INDEX_WIDTH){1'b0}}, drain_beat_index}),
                .rd_clk(clk), .rd_rst(!rst_n)
            );
        end
    endgenerate

    assign wr_cmd_len = BEATS_PER_LINE;
    assign wr_ctrl_data = drain_bank ? line_bank1_data : line_bank0_data;

    initial begin
        if ((IMAGE_WIDTH % 8) != 0)
            $error("algorithm_frame_writer_rgbx requires IMAGE_WIDTH divisible by 8");
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_full <= 2'b00;
            bank_line0 <= 0;
            bank_line1 <= 0;
            fill_bank <= 1'b0;
            fill_word_index <= 0;
            fill_line_index <= 0;
            drain_active <= 1'b0;
            drain_bank <= 1'b0;
            drain_beat_index <= 0;
            bank_write_en <= 1'b0;
            bank_write_sel <= 1'b0;
            bank_write_addr <= 0;
            bank_write_data <= 32'd0;
            overflow <= 1'b0;
            frame_complete <= 1'b0;
            wr_cmd_en <= 1'b0;
            wr_cmd_addr <= OUTPUT_BASE_ADDR;
        end else begin
            wr_cmd_en <= 1'b0;
            frame_complete <= 1'b0;
            bank_write_en <= 1'b0;

            if (pixel_valid) begin
                if (pixel_sof) begin
                    bank_full <= 2'b00;
                    fill_bank <= 1'b0;
                    fill_word_index <= 0;
                    fill_line_index <= 0;
                end

                if (bank_full[fill_bank]) begin
                    overflow <= 1'b1;
                end else if (pixel_sof || !bank_full[fill_bank]) begin
                    bank_write_en <= 1'b1;
                    bank_write_sel <= fill_bank;
                    bank_write_addr <= fill_word_index;
                    bank_write_data <= {pixel_data, 8'h00};

                    if (pixel_eol) begin
                        bank_full[fill_bank] <= 1'b1;
                        if (fill_bank)
                            bank_line1 <= fill_line_index;
                        else
                            bank_line0 <= fill_line_index;
                        fill_bank <= ~fill_bank;
                        fill_word_index <= 0;
                        if (fill_line_index != IMAGE_HEIGHT - 1)
                            fill_line_index <= fill_line_index + 1'b1;
                    end else begin
                        fill_word_index <= fill_word_index + 1'b1;
                    end
                end
            end

            if (!drain_active) begin
                drain_beat_index <= 0;
                if (bank_full[drain_bank] && wr_cmd_ready) begin
                    wr_cmd_addr <= OUTPUT_BASE_ADDR
                                   + (drain_bank ? bank_line1 : bank_line0)
                                     * IMAGE_WIDTH * 4;
                    wr_cmd_en <= 1'b1;
                    drain_active <= 1'b1;
                end
            end else begin
                if (wr_bac && (drain_beat_index != 0))
                    drain_beat_index <= drain_beat_index - 1'b1;
                else if (wr_data_re)
                    drain_beat_index <= drain_beat_index + 1'b1;

                if (wr_cmd_done) begin
                    bank_full[drain_bank] <= 1'b0;
                    if ((drain_bank ? bank_line1 : bank_line0) == IMAGE_HEIGHT - 1)
                        frame_complete <= 1'b1;
                    drain_bank <= ~drain_bank;
                    drain_active <= 1'b0;
                    drain_beat_index <= 0;
                end
            end
        end
    end
endmodule
