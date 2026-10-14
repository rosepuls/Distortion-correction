`timescale 1ns/1ps

// Reads one 32-pixel RGBX8888 Tile row as four 256-bit DDR beats.
// rd_cmd_addr is a 32-byte-aligned byte address; the board adapter may convert
// it to the address units required by the official DDR controller.
module ddr_burst_reader #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer ADDR_WIDTH = 32,
    parameter [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = {ADDR_WIDTH{1'b0}},
    parameter integer TILE_WIDTH = 32,
    parameter integer TILE_HEIGHT = 4,
    parameter integer BYTES_PER_PIXEL = 4,
    parameter integer BEATS_PER_ROW = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    fill_req_valid,
    output wire                    fill_req_ready,
    input  wire [11:0]             fill_tile_x,
    input  wire [11:0]             fill_tile_y,
    input  wire [1:0]              fill_row_index,

    output wire                    rd_cmd_en,
    input  wire                    rd_cmd_ready,
    output wire [ADDR_WIDTH-1:0]   rd_cmd_addr,
    output wire [31:0]             rd_cmd_len,
    input  wire                    rd_data_valid,
    output wire                    rd_data_ready,
    input  wire [255:0]            rd_data,
    input  wire                    rd_data_last,

    output wire                    fill_data_valid,
    input  wire                    fill_data_ready,
    output wire [255:0]            fill_data,
    output wire [11:0]             fill_out_tile_x,
    output wire [11:0]             fill_out_tile_y,
    output wire [1:0]              fill_out_row_index,
    output wire [1:0]              fill_beat_index
);
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_DATA = 2'd1;

    reg [1:0] state;
    reg [11:0] tile_x_reg;
    reg [11:0] tile_y_reg;
    reg [1:0] row_index_reg;
    reg [1:0] beat_index_reg;

    wire fill_req_fire = fill_req_valid && fill_req_ready;
    wire rd_data_fire = rd_data_valid && rd_data_ready;
    wire unused_rd_data_last = rd_data_last;

    // A row-fill request and its DDR command are one transaction: make the
    // command valid in the request cycle, rather than consuming an extra
    // STATE_CMD cycle.  The request is only accepted when the DDR endpoint
    // is ready, so the Tile Cache still observes standard ready/valid
    // semantics and no command information needs a staging register.
    assign fill_req_ready = (state == STATE_IDLE) && rd_cmd_ready && rst_n;
    assign rd_cmd_en = (state == STATE_IDLE) && fill_req_valid && rst_n;
    assign rd_cmd_len = BEATS_PER_ROW;
    assign rd_data_ready = (state == STATE_DATA) && fill_data_ready;

    assign rd_cmd_addr = (state == STATE_IDLE)
                         ? row_byte_address(
                             fill_tile_x, fill_tile_y, fill_row_index
                           )
                         : row_byte_address(
                             tile_x_reg, tile_y_reg, row_index_reg
                           );

    assign fill_data_valid = (state == STATE_DATA) && rd_data_valid;
    assign fill_data = rd_data;
    assign fill_out_tile_x = tile_x_reg;
    assign fill_out_tile_y = tile_y_reg;
    assign fill_out_row_index = row_index_reg;
    assign fill_beat_index = beat_index_reg;

    function automatic [ADDR_WIDTH-1:0] row_byte_address(
        input [11:0] tile_x,
        input [11:0] tile_y,
        input [1:0] row_index
    );
        reg [63:0] pixel_index;
        begin
            pixel_index = ((tile_y * TILE_HEIGHT + row_index) * IMAGE_WIDTH)
                          + tile_x * TILE_WIDTH;
            row_byte_address = FRAME_BASE_BYTE_ADDR
                               + pixel_index * BYTES_PER_PIXEL;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            tile_x_reg <= 12'd0;
            tile_y_reg <= 12'd0;
            row_index_reg <= 2'd0;
            beat_index_reg <= 2'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    beat_index_reg <= 2'd0;
                    if (fill_req_fire) begin
                        tile_x_reg <= fill_tile_x;
                        tile_y_reg <= fill_tile_y;
                        row_index_reg <= fill_row_index;
                        // fill_req_ready requires rd_cmd_ready, so this is
                        // also a command handshake in this cycle.
                        state <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    if (rd_data_fire) begin
                        if (beat_index_reg == BEATS_PER_ROW - 1) begin
                            beat_index_reg <= 2'd0;
                            state <= STATE_IDLE;
                        end else begin
                            beat_index_reg <= beat_index_reg + 1'b1;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
