`timescale 1ns / 1ps

// Fetch one 32-pixel RGBX8888 tile row from a completed input-frame slot.
// Pango addresses count 32-bit pixels/words; each 256-bit return beat holds
// eight pixels. The DDR read interface has no RREADY, so all four beats are
// reserved locally before AR is presented to the read arbiter.
module tile_row_ddr_adapter #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer SLOT_WORD_BITS = 22
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         fill_req_valid,
    output wire         fill_req_ready,
    input  wire [1:0]   frame_slot,
    input  wire [11:0]  fill_tile_x,
    input  wire [11:0]  fill_tile_y,
    input  wire [1:0]   fill_row_index,
    output wire         read_valid,
    output reg  [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         fill_data_valid,
    input  wire         fill_data_ready,
    output wire [255:0] fill_data,
    output reg  [11:0]  fill_out_tile_x,
    output reg  [11:0]  fill_out_tile_y,
    output reg  [1:0]   fill_out_row_index,
    output wire [1:0]   fill_beat_index,
    output wire         idle,
    output wire         read_response_wait,
    output wire         first_beat_wait,
    output wire         interbeat_wait,
    output reg          fatal_fault,
    output reg  [15:0]  protocol_error_count,
    output reg  [31:0]  completed_rows
);
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] WAIT_AR = 2'd1;
    localparam [1:0] RECEIVE = 2'd2;
    localparam [1:0] OUTPUT = 2'd3;
    localparam integer TILE_WIDTH = 32;
    localparam integer TILE_HEIGHT = 4;
    localparam integer BEATS_PER_ROW = 4;

    reg [1:0] state;
    reg [1:0] receive_index;
    reg [1:0] output_index;
    reg [255:0] row_beats [0:BEATS_PER_ROW-1];

    wire request_in_range = (frame_slot < 2'd3) &&
        (fill_tile_x < IMAGE_WIDTH / TILE_WIDTH) &&
        (fill_tile_y < IMAGE_HEIGHT / TILE_HEIGHT);
    wire [27:0] pixel_offset =
        ((fill_tile_y * TILE_HEIGHT + fill_row_index) * IMAGE_WIDTH)
        + fill_tile_x * TILE_WIDTH;
    wire [27:0] slot_base = {4'b0000, frame_slot, {SLOT_WORD_BITS{1'b0}}};

    assign idle = state == IDLE && !fatal_fault;
    assign fill_req_ready = rstn && idle;
    assign read_valid = rstn && state == WAIT_AR && !fatal_fault;
    assign read_reserve = read_valid;
    assign read_len = 4'd3;
    assign fill_data_valid = rstn && state == OUTPUT && !fatal_fault;
    assign fill_data = row_beats[output_index];
    assign fill_beat_index = output_index;
    assign read_response_wait = (state == RECEIVE) && !read_rvalid;
    assign first_beat_wait = read_response_wait && (receive_index == 2'd0);
    assign interbeat_wait = read_response_wait && (receive_index != 2'd0);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            read_addr <= 28'd0;
            fill_out_tile_x <= 12'd0;
            fill_out_tile_y <= 12'd0;
            fill_out_row_index <= 2'd0;
            receive_index <= 2'd0;
            output_index <= 2'd0;
            fatal_fault <= 1'b0;
            protocol_error_count <= 16'd0;
            completed_rows <= 32'd0;
        end else if (read_rvalid && state != RECEIVE) begin
            // A response without ownership cannot be safely assigned to a row.
            fatal_fault <= 1'b1;
            if (protocol_error_count != 16'hffff)
                protocol_error_count <= protocol_error_count + 1'b1;
        end else begin
            case (state)
                IDLE: if (fill_req_valid && fill_req_ready) begin
                    if (request_in_range) begin
                        read_addr <= slot_base + pixel_offset;
                        fill_out_tile_x <= fill_tile_x;
                        fill_out_tile_y <= fill_tile_y;
                        fill_out_row_index <= fill_row_index;
                        receive_index <= 2'd0;
                        output_index <= 2'd0;
                        state <= WAIT_AR;
                    end else begin
                        fatal_fault <= 1'b1;
                        if (protocol_error_count != 16'hffff)
                            protocol_error_count <= protocol_error_count + 1'b1;
                    end
                end
                WAIT_AR: if (read_valid && read_ready)
                    state <= RECEIVE;
                RECEIVE: if (read_rvalid) begin
                    if (read_rlast != (receive_index == BEATS_PER_ROW-1)) begin
                        fatal_fault <= 1'b1;
                        if (protocol_error_count != 16'hffff)
                            protocol_error_count <= protocol_error_count + 1'b1;
                    end else begin
                        row_beats[receive_index] <= read_rdata;
                        if (receive_index == BEATS_PER_ROW-1)
                            state <= OUTPUT;
                        else
                            receive_index <= receive_index + 1'b1;
                    end
                end
                OUTPUT: if (fill_data_valid && fill_data_ready) begin
                    if (output_index == BEATS_PER_ROW-1) begin
                        state <= IDLE;
                        completed_rows <= completed_rows + 1'b1;
                    end else
                        output_index <= output_index + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
