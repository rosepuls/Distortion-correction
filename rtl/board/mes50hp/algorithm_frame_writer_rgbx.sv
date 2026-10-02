`timescale 1ns/1ps

// RGBX8888 frame writer: one 32-bit word per pixel and eight words per
// 256-bit DDR beat.  The two line banks allow capture of the next line while
// the previous line is being drained to DDR.
module algorithm_frame_writer_rgbx #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer DDR_ADDR_WIDTH = 32,
    parameter [DDR_ADDR_WIDTH-1:0] OUTPUT_BASE_ADDR = {DDR_ADDR_WIDTH{1'b0}}
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

    reg [31:0] line_bank0 [0:IMAGE_WIDTH-1];
    reg [31:0] line_bank1 [0:IMAGE_WIDTH-1];
    reg [1:0] bank_full;
    reg [LINE_INDEX_WIDTH-1:0] bank_line0;
    reg [LINE_INDEX_WIDTH-1:0] bank_line1;
    reg fill_bank;
    reg [WORD_INDEX_WIDTH-1:0] fill_word_index;
    reg [LINE_INDEX_WIDTH-1:0] fill_line_index;
    reg drain_active;
    reg drain_bank;
    reg [BEAT_INDEX_WIDTH-1:0] drain_beat_index;

    integer pack_lane;
    integer pack_word_index;
    reg [255:0] packed_beat;
    always @* begin
        packed_beat = 256'd0;
        for (pack_lane = 0; pack_lane < 8; pack_lane = pack_lane + 1) begin
            pack_word_index = drain_beat_index * 8 + pack_lane;
            if (drain_bank)
                packed_beat[pack_lane*32 +: 32] = line_bank1[pack_word_index];
            else
                packed_beat[pack_lane*32 +: 32] = line_bank0[pack_word_index];
        end
    end

    assign wr_cmd_len = BEATS_PER_LINE;
    assign wr_ctrl_data = packed_beat;

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
            overflow <= 1'b0;
            frame_complete <= 1'b0;
            wr_cmd_en <= 1'b0;
            wr_cmd_addr <= OUTPUT_BASE_ADDR;
        end else begin
            wr_cmd_en <= 1'b0;
            frame_complete <= 1'b0;

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
                    if (fill_bank)
                        line_bank1[fill_word_index] <= {pixel_data, 8'h00};
                    else
                        line_bank0[fill_word_index] <= {pixel_data, 8'h00};

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
