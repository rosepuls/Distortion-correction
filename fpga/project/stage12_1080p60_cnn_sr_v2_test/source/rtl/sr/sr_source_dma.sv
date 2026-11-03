`timescale 1ns / 1ps

// One-row-at-a-time source reader for the standalone CNN SR path.
// Each source row is read as 16-beat DDR bursts into eight interleaved
// synchronous RAM banks, then emitted with a one-pixel zero halo. Top and
// bottom halo rows are generated without DDR traffic. The row RAM is never
// written while its pixels are being emitted.
module sr_source_dma #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer SLOT_WORD_BITS = 22,
    parameter integer ROW_WORDS = IMAGE_WIDTH / 8,
    parameter integer ROW_ADDR_WIDTH = (ROW_WORDS <= 1) ? 1 : $clog2(ROW_WORDS),
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10
) (
    input  wire                  clk,
    input  wire                  rstn,
    input  wire                  source_frame_start,
    input  wire [1:0]            source_frame_slot,
    input  wire [31:0]           source_frame_id,
    output wire                  m_valid,
    input  wire                  m_ready,
    output wire [31:0]           m_rgbx,
    output wire [20:0]           m_pixel_id,
    output wire [31:0]           m_frame_id,
    output wire [X_WIDTH-1:0]    m_x,
    output wire [Y_WIDTH-1:0]    m_y,
    output wire                  m_sof,
    output wire                  m_eol,
    output wire                  m_eof,
    output wire                  read_valid,
    output wire [27:0]           read_addr,
    output wire [3:0]            read_len,
    output wire                  read_reserve,
    input  wire                  read_ready,
    input  wire                  read_rvalid,
    input  wire [255:0]          read_rdata,
    input  wire                  read_rlast,
    output reg                   source_done,
    output reg                   fatal_fault,
    output reg [15:0]            read_error_count
);
    localparam integer PADDED_WIDTH = IMAGE_WIDTH + 2;
    localparam integer PADDED_HEIGHT = IMAGE_HEIGHT + 2;
    localparam integer BURSTS_PER_ROW = ROW_WORDS / 16;
    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_TOP = 4'd1;
    localparam [3:0] ST_AR = 4'd2;
    localparam [3:0] ST_DATA = 4'd3;
    localparam [3:0] ST_LEFT = 4'd4;
    localparam [3:0] ST_PIXELS = 4'd5;
    localparam [3:0] ST_RIGHT = 4'd6;
    localparam [3:0] ST_BOTTOM = 4'd7;
    localparam [3:0] ST_DRAIN = 4'd8;
    localparam [3:0] ST_PIXEL_OUT = 4'd9;

    reg [3:0] state;
    reg [1:0] active_frame_slot;
    reg [31:0] active_frame_id;
    reg [9:0] load_row;
    reg [3:0] burst_index;
    reg [4:0] beat_index;
    reg [27:0] request_addr;
    reg [X_WIDTH-1:0] emit_x;
    reg [Y_WIDTH-1:0] emit_y;
    reg [10:0] source_x;
    reg [20:0] pixel_count;
    reg [31:0] pixel_read_data;
    reg [10:0] pixel_read_x;

    (* ram_style = "block" *) reg [31:0] row_mem [0:7][0:ROW_WORDS-1];
    reg out_valid;
    reg [31:0] out_rgbx;
    reg [20:0] out_pixel_id;
    reg [31:0] out_frame_id;
    reg [X_WIDTH-1:0] out_x;
    reg [Y_WIDTH-1:0] out_y;
    reg out_sof, out_eol, out_eof;

    wire output_slot = !out_valid || m_ready;
    wire output_fire = out_valid && m_ready;
    wire read_fire = read_valid && read_ready;
    wire response_fire = (state == ST_DATA) && read_rvalid;
    wire [ROW_ADDR_WIDTH-1:0] row_read_addr = source_x >> 3;
    wire [2:0] row_read_bank = source_x[2:0];

    assign m_valid = rstn && out_valid;
    assign m_rgbx = out_rgbx;
    assign m_pixel_id = out_pixel_id;
    assign m_frame_id = out_frame_id;
    assign m_x = out_x;
    assign m_y = out_y;
    assign m_sof = out_sof;
    assign m_eol = out_eol;
    assign m_eof = out_eof;
    assign read_valid = rstn && (state == ST_AR) && !fatal_fault;
    assign read_addr = request_addr;
    assign read_len = 4'd15;
    assign read_reserve = read_valid;

    integer lane;
    always @(posedge clk) begin
        if (response_fire) begin
            for (lane = 0; lane < 8; lane = lane + 1)
                row_mem[lane][({4'd0, burst_index} << 4) + beat_index[3:0]] <=
                    read_rdata[lane*32 +: 32];
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= ST_IDLE;
            active_frame_slot <= 2'd0;
            active_frame_id <= 32'd0;
            load_row <= 10'd0;
            burst_index <= 4'd0;
            beat_index <= 5'd0;
            request_addr <= 28'd0;
            emit_x <= {X_WIDTH{1'b0}};
            emit_y <= {Y_WIDTH{1'b0}};
            source_x <= 11'd0;
            pixel_count <= 21'd0;
            out_valid <= 1'b0;
            out_rgbx <= 32'd0;
            out_pixel_id <= 21'd0;
            out_frame_id <= 32'd0;
            out_x <= {X_WIDTH{1'b0}};
            out_y <= {Y_WIDTH{1'b0}};
            out_sof <= 1'b0;
            out_eol <= 1'b0;
            out_eof <= 1'b0;
            source_done <= 1'b0;
            fatal_fault <= 1'b0;
            read_error_count <= 16'd0;
        end else begin
            source_done <= 1'b0;
            if ((state == ST_PIXELS) && output_slot)
                pixel_read_data <= row_mem[row_read_bank][row_read_addr];
            if (output_slot) begin
                out_valid <= 1'b0;
                case (state)
                    ST_TOP: begin
                        out_valid <= 1'b1;
                        out_rgbx <= 32'd0;
                        out_pixel_id <= pixel_count;
                        out_frame_id <= active_frame_id;
                        out_x <= emit_x;
                        out_y <= emit_y;
                        out_sof <= (pixel_count == 0);
                        out_eol <= (emit_x == PADDED_WIDTH-1);
                        out_eof <= 1'b0;
                        pixel_count <= pixel_count + 1'b1;
                        if (emit_x == PADDED_WIDTH-1) begin
                            emit_x <= {X_WIDTH{1'b0}};
                            emit_y <= 1;
                            state <= ST_AR;
                        end else emit_x <= emit_x + 1'b1;
                    end
                    ST_LEFT: begin
                        out_valid <= 1'b1;
                        out_rgbx <= 32'd0;
                        out_pixel_id <= pixel_count;
                        out_frame_id <= active_frame_id;
                        out_x <= 0;
                        out_y <= emit_y;
                        out_sof <= 1'b0;
                        out_eol <= 1'b0;
                        out_eof <= 1'b0;
                        pixel_count <= pixel_count + 1'b1;
                        source_x <= 0;
                        state <= ST_PIXELS;
                    end
                    ST_PIXELS: begin
                        pixel_read_x <= source_x;
                        state <= ST_PIXEL_OUT;
                    end
                    ST_PIXEL_OUT: begin
                        out_valid <= 1'b1;
                        out_rgbx <= pixel_read_data;
                        out_pixel_id <= pixel_count;
                        out_frame_id <= active_frame_id;
                        out_x <= pixel_read_x + 1'b1;
                        out_y <= emit_y;
                        out_sof <= 1'b0;
                        out_eol <= 1'b0;
                        out_eof <= 1'b0;
                        pixel_count <= pixel_count + 1'b1;
                        if (pixel_read_x == IMAGE_WIDTH-1) state <= ST_RIGHT;
                        else begin
                            source_x <= source_x + 1'b1;
                            state <= ST_PIXELS;
                        end
                    end
                    ST_RIGHT: begin
                        out_valid <= 1'b1;
                        out_rgbx <= 32'd0;
                        out_pixel_id <= pixel_count;
                        out_frame_id <= active_frame_id;
                        out_x <= PADDED_WIDTH-1;
                        out_y <= emit_y;
                        out_sof <= 1'b0;
                        out_eol <= 1'b1;
                        out_eof <= 1'b0;
                        pixel_count <= pixel_count + 1'b1;
                        if (load_row == IMAGE_HEIGHT-1) begin
                            emit_x <= 0;
                            emit_y <= IMAGE_HEIGHT+1;
                            state <= ST_BOTTOM;
                        end else begin
                            load_row <= load_row + 1'b1;
                            emit_y <= emit_y + 1'b1;
                            request_addr <= request_addr - ((BURSTS_PER_ROW-1) * 128) + IMAGE_WIDTH;
                            burst_index <= 0;
                            state <= ST_AR;
                        end
                    end
                    ST_BOTTOM: begin
                        out_valid <= 1'b1;
                        out_rgbx <= 32'd0;
                        out_pixel_id <= pixel_count;
                        out_frame_id <= active_frame_id;
                        out_x <= emit_x;
                        out_y <= emit_y;
                        out_sof <= 1'b0;
                        out_eol <= (emit_x == PADDED_WIDTH-1);
                        out_eof <= (emit_x == PADDED_WIDTH-1);
                        pixel_count <= pixel_count + 1'b1;
                        if (emit_x == PADDED_WIDTH-1) state <= ST_DRAIN;
                        else emit_x <= emit_x + 1'b1;
                    end
                    default: begin end
                endcase
            end

            if (read_fire) begin
                state <= ST_DATA;
                beat_index <= 0;
            end
            if (response_fire) begin
                if (read_rlast != (beat_index == 15)) begin
                    if (read_error_count != 16'hffff)
                        read_error_count <= read_error_count + 1'b1;
                    fatal_fault <= 1'b1;
                    state <= ST_DRAIN;
                end else if (read_rlast) begin
                    if (burst_index == BURSTS_PER_ROW-1) begin
                        burst_index <= 0;
                        source_x <= 0;
                        state <= ST_LEFT;
                    end else begin
                        burst_index <= burst_index + 1'b1;
                        request_addr <= request_addr + 28'd128;
                        state <= ST_AR;
                    end
                end else beat_index <= beat_index + 1'b1;
            end

            if (state == ST_DRAIN && output_fire && out_eof) begin
                source_done <= 1'b1;
                state <= ST_IDLE;
                out_valid <= 1'b0;
            end

            if (state == ST_IDLE && source_frame_start && !fatal_fault) begin
                active_frame_slot <= source_frame_slot;
                active_frame_id <= source_frame_id;
                load_row <= 0;
                burst_index <= 0;
                beat_index <= 0;
                request_addr <= {4'b0000, source_frame_slot, {SLOT_WORD_BITS{1'b0}}};
                emit_x <= 0;
                emit_y <= 0;
                source_x <= 0;
                pixel_count <= 0;
                state <= ST_TOP;
            end
        end
    end
endmodule

