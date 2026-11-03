`timescale 1ns / 1ps

// Eight-channel 3x3 sliding window. The input feature raster includes a
// one-pixel zero halo on all sides; tap order is row-major, with eight uint8
// channels packed into each 64-bit tap.
module sr_feature_window3x3 #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer PADDED_WIDTH = IMAGE_WIDTH + 2,
    parameter integer PADDED_HEIGHT = IMAGE_HEIGHT + 2,
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10,
    parameter integer FRAME_ID_WIDTH = 32,
    parameter integer X_ADDR_WIDTH = (PADDED_WIDTH <= 2) ? 1 : $clog2(PADDED_WIDTH)
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [63:0]               s_features,
    input  wire [X_WIDTH-1:0]        s_x,
    input  wire [Y_WIDTH-1:0]        s_y,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input  wire                      s_sof,
    input  wire                      s_eol,
    input  wire                      s_eof,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [575:0]              m_window,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [20:0]               m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    wire [63:0] line_q [0:2];
    reg [1:0] write_bank;
    reg [1:0] response_bank_mid, response_bank_top;
    reg [63:0] response_features;
    reg [X_WIDTH-1:0] response_x;
    reg [Y_WIDTH-1:0] response_y;
    reg [FRAME_ID_WIDTH-1:0] response_frame_id;
    reg response_valid;

    reg [63:0] top_xm2, top_xm1;
    reg [63:0] mid_xm2, mid_xm1;
    reg [63:0] bot_xm2, bot_xm1;
    reg output_valid;
    reg [575:0] output_window;
    reg [X_WIDTH-1:0] output_x;
    reg [Y_WIDTH-1:0] output_y;
    reg [20:0] output_pixel_id;
    reg [20:0] next_pixel_id;
    reg [FRAME_ID_WIDTH-1:0] output_frame_id;

    wire output_ready = !output_valid || m_ready;
    wire response_ready = !response_valid || output_ready;
    wire input_fire = s_valid && s_ready;
    wire [1:0] active_write_bank = s_sof ? 2'd0 : write_bank;
    wire [1:0] active_mid_bank = (active_write_bank == 0) ? 2'd2 : active_write_bank - 1'b1;
    wire [1:0] active_top_bank = (active_write_bank == 0) ? 2'd1 :
                                 (active_write_bank == 1) ? 2'd2 : 2'd0;
    wire [1:0] next_write_bank = (write_bank == 2) ? 2'd0 : write_bank + 1'b1;
    wire rows_available = (s_y >= 2);

    assign s_ready = rstn && response_ready;
    assign m_valid = rstn && output_valid;
    assign m_window = output_window;
    assign m_x = output_x;
    assign m_y = output_y;
    assign m_pixel_id = output_pixel_id;
    assign m_frame_id = output_frame_id;
    assign m_sof = output_valid && (output_x == 0) && (output_y == 0);
    assign m_eol = output_valid && (output_x == IMAGE_WIDTH-1);
    assign m_eof = output_valid && (output_x == IMAGE_WIDTH-1) &&
                   (output_y == IMAGE_HEIGHT-1);

    wire [63:0] response_mid = line_q[response_bank_mid];
    wire [63:0] response_top = line_q[response_bank_top];

    genvar bank;
    generate
        for (bank = 0; bank < 3; bank = bank + 1) begin: g_line_ram
            wire write_enable = input_fire && (active_write_bank == bank);
            wire read_enable = input_fire &&
                (((active_mid_bank == bank) && (s_y >= 1)) ||
                 ((active_top_bank == bank) && (s_y >= 2)));
            sr_feature_line_ram #(
                .DATA_WIDTH(64), .DEPTH(PADDED_WIDTH), .ADDR_WIDTH(X_ADDR_WIDTH)
            ) row_store (
                .clk(clk), .wr_en(write_enable),
                .wr_addr(s_x[X_ADDR_WIDTH-1:0]), .wr_data(s_features),
                .rd_en(read_enable), .rd_addr(s_x[X_ADDR_WIDTH-1:0]),
                .rd_data(line_q[bank])
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (!rstn) begin
            write_bank <= 2'd0;
            next_pixel_id <= 21'd0;
            response_valid <= 1'b0;
            output_valid <= 1'b0;
        end else begin
            if (s_sof && input_fire) begin
                write_bank <= s_eol ? 2'd1 : 2'd0;
                next_pixel_id <= 21'd0;
            end else if (s_eol && input_fire)
                write_bank <= next_write_bank;

            if (response_ready) begin
                response_valid <= input_fire && rows_available;
                if (input_fire) begin
                    response_features <= s_features;
                    response_x <= s_x;
                    response_y <= s_y;
                    response_frame_id <= s_frame_id;
                    response_bank_mid <= active_mid_bank;
                    response_bank_top <= active_top_bank;
                end
            end

            if (output_ready) begin
                output_valid <= response_valid && (response_x >= 2);
                if (response_valid && (response_x >= 2)) begin
                    output_window <= {
                        top_xm2, top_xm1, response_top,
                        mid_xm2, mid_xm1, response_mid,
                        bot_xm2, bot_xm1, response_features
                    };
                    output_x <= response_x - 2'd2;
                    output_y <= response_y - 2'd2;
                    output_pixel_id <= next_pixel_id;
                    next_pixel_id <= next_pixel_id + 1'b1;
                    output_frame_id <= response_frame_id;
                end
            end

            if (response_valid && output_ready) begin
                if (response_x == 0) begin
                    top_xm2 <= 64'd0; top_xm1 <= response_top;
                    mid_xm2 <= 64'd0; mid_xm1 <= response_mid;
                    bot_xm2 <= 64'd0; bot_xm1 <= response_features;
                end else begin
                    top_xm2 <= top_xm1; top_xm1 <= response_top;
                    mid_xm2 <= mid_xm1; mid_xm1 <= response_mid;
                    bot_xm2 <= bot_xm1; bot_xm1 <= response_features;
                end
            end
        end
    end
endmodule
