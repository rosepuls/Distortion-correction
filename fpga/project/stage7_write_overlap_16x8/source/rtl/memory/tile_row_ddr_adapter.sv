`timescale 1ns / 1ps

// Fetch the four 32-pixel rows of one tile. All four four-beat row bursts are
// issued with transform ID 1 before cache writeback begins. The DDR R channel
// has no backpressure in this design, so this adapter reserves a complete
// 16-beat tile buffer before accepting the tile request.
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
    output wire [27:0]  read_addr,
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
    output wire [1:0]   fill_out_row_index,
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
    localparam [1:0] ACTIVE = 2'd1;
    localparam [1:0] OUTPUT = 2'd2;
    localparam integer TILE_WIDTH = 32;
    localparam integer TILE_HEIGHT = 4;
    localparam integer ROW_BEATS = 4;
    localparam integer TILE_BEATS = TILE_HEIGHT * ROW_BEATS;

    reg [1:0] state;
    reg [2:0] issue_rows;
    reg [4:0] received_beats;
    reg [4:0] output_beat;
    reg [1:0] active_frame_slot;
    reg [11:0] active_tile_x;
    reg [11:0] active_tile_y;
    reg [255:0] tile_beats [0:TILE_BEATS-1];

    wire request_in_range = (frame_slot < 2'd3) &&
        (fill_tile_x < IMAGE_WIDTH / TILE_WIDTH) &&
        (fill_tile_y < IMAGE_HEIGHT / TILE_HEIGHT);
    wire [1:0] issue_row_index = issue_rows[1:0];
    wire [27:0] issue_pixel_offset =
        ((active_tile_y * TILE_HEIGHT + issue_row_index) * IMAGE_WIDTH)
        + active_tile_x * TILE_WIDTH;
    wire [27:0] active_slot_base =
        {4'b0000, active_frame_slot, {SLOT_WORD_BITS{1'b0}}};
    wire [1:0] receive_beat = received_beats[1:0];
    wire [1:0] output_row = output_beat[3:2];

    assign idle = (state == IDLE) && !fatal_fault;
    assign fill_req_ready = rstn && idle;
    assign read_valid = rstn && (state == ACTIVE) &&
                        (issue_rows < TILE_HEIGHT) && !fatal_fault;
    assign read_addr = active_slot_base + issue_pixel_offset;
    assign read_len = 4'd3;
    // The adapter owns all 16 response slots from tile acceptance until all
    // four bursts have completed; the arbiter may therefore grant each row.
    assign read_reserve = rstn && (state == ACTIVE) && !fatal_fault;
    assign fill_data_valid = rstn && (state == OUTPUT) && !fatal_fault;
    assign fill_data = tile_beats[output_beat];
    assign fill_out_row_index = output_row;
    assign fill_beat_index = output_beat[1:0];
    assign read_response_wait = (state == ACTIVE) &&
        (received_beats < {issue_rows, 2'b00}) && !read_rvalid;
    assign first_beat_wait = read_response_wait && (receive_beat == 2'd0);
    assign interbeat_wait = read_response_wait && (receive_beat != 2'd0);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            issue_rows <= 3'd0;
            received_beats <= 5'd0;
            output_beat <= 5'd0;
            active_frame_slot <= 2'd0;
            active_tile_x <= 12'd0;
            active_tile_y <= 12'd0;
            fill_out_tile_x <= 12'd0;
            fill_out_tile_y <= 12'd0;
            fatal_fault <= 1'b0;
            protocol_error_count <= 16'd0;
            completed_rows <= 32'd0;
        end else if (read_rvalid && state != ACTIVE) begin
            fatal_fault <= 1'b1;
            if (protocol_error_count != 16'hffff)
                protocol_error_count <= protocol_error_count + 1'b1;
        end else begin
            if (state == IDLE && fill_req_valid && fill_req_ready) begin
                if (request_in_range) begin
                    active_frame_slot <= frame_slot;
                    active_tile_x <= fill_tile_x;
                    active_tile_y <= fill_tile_y;
                    fill_out_tile_x <= fill_tile_x;
                    fill_out_tile_y <= fill_tile_y;
                    issue_rows <= 3'd0;
                    received_beats <= 5'd0;
                    output_beat <= 5'd0;
                    state <= ACTIVE;
                end else begin
                    fatal_fault <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end
            end

            if (read_valid && read_ready)
                issue_rows <= issue_rows + 3'd1;

            if (state == ACTIVE && read_rvalid) begin
                if ((received_beats >= TILE_BEATS) ||
                    (read_rlast != (receive_beat == ROW_BEATS-1))) begin
                    fatal_fault <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end else begin
                    tile_beats[received_beats] <= read_rdata;
                    received_beats <= received_beats + 5'd1;
                    if (received_beats == TILE_BEATS-1) begin
                        output_beat <= 5'd0;
                        state <= OUTPUT;
                    end
                end
            end

            if (state == OUTPUT && fill_data_valid && fill_data_ready) begin
                if (fill_beat_index == ROW_BEATS-1)
                    completed_rows <= completed_rows + 1'b1;
                if (output_beat == TILE_BEATS-1) begin
                    output_beat <= 5'd0;
                    issue_rows <= 3'd0;
                    received_beats <= 5'd0;
                    state <= IDLE;
                end else begin
                    output_beat <= output_beat + 5'd1;
                end
            end
        end
    end
endmodule
