`timescale 1ns / 1ps

// Sequential 3:2 resizer source reader. It keeps three tagged source rows in
// 8 interleaved BRAM banks per row, fetches rows in 16-beat DDR bursts, and
// protects rows until all accepted pixel lookups have returned.
module streaming_linebuffer_reader #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer SLOT_WORD_BITS = 22,
    parameter integer ROW_WORDS = IMAGE_WIDTH / 8,
    parameter integer ROW_ADDR_WIDTH = (ROW_WORDS <= 1) ? 1 : $clog2(ROW_WORDS)
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         source_frame_start,
    input  wire [1:0]   source_frame_slot,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [10:0]  s_x0,
    input  wire [10:0]  s_x1,
    input  wire [9:0]   s_y0,
    input  wire [9:0]   s_y1,
    input  wire [15:0]  s_fx,
    input  wire [15:0]  s_fy,
    input  wire [3:0]   s_neighbor_valid,
    input  wire         s_geometry_valid,
    input  wire [20:0]  s_pixel_id,
    input  wire [31:0]  s_frame_id,
    input  wire [15:0]  s_param_version,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_eof,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [31:0]  m_p00,
    output wire [31:0]  m_p10,
    output wire [31:0]  m_p01,
    output wire [31:0]  m_p11,
    output reg  [15:0]  m_fx,
    output reg  [15:0]  m_fy,
    output reg  [3:0]   m_neighbor_valid,
    output reg          m_geometry_valid,
    output reg  [20:0]  m_pixel_id,
    output reg  [31:0]  m_frame_id,
    output reg  [15:0]  m_param_version,
    output reg          m_sof,
    output reg          m_eol,
    output reg          m_eof,
    output wire         read_valid,
    output wire [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         idle,
    output reg          fatal_fault,
    output reg  [15:0]  read_error_count,
    output reg  [31:0]  fetched_rows
);
    localparam [1:0] DMA_IDLE = 2'd0;
    localparam [1:0] DMA_AR = 2'd1;
    localparam [1:0] DMA_DATA = 2'd2;
    localparam integer BURSTS_PER_ROW = ROW_WORDS / 16;

    reg [1:0] dma_state;
    reg [1:0] active_frame_slot;
    reg [9:0] next_row;
    reg [9:0] load_row;
    reg [1:0] load_slot;
    reg [3:0] burst_index;
    reg [3:0] beat_index;
    reg [2:0] valid_rows;
    reg [9:0] row_tag [0:2];
    reg [15:0] row_refs [0:2];
    reg [9:0] required_y0;

    reg response_valid;
    reg [1:0] response_slot0, response_slot1;
    reg [2:0] response_bank0, response_bank1;
    reg [7:0] response_addr0, response_addr1;
    reg response_same_row, response_same_x;

    wire [31:0] bank_data [0:2][0:7];
    reg [7:0] bank_read_enable [0:2];
    reg [7:0] bank_read_addr [0:2][0:7];
    wire [1:0] query_slot0, query_slot1;
    wire query_rows_found;
    reg [1:0] found_slot0, found_slot1;
    reg found_row0, found_row1;
    reg free_found;
    reg [1:0] free_slot;
    integer i;
    integer k0, k1, a0, b0, d0;

    wire response_fire = response_valid && m_ready;
    wire lookup_fire = s_valid && s_ready;
    wire [2:0] query_bank0 = s_x0[2:0];
    wire [2:0] query_bank1 = s_x1[2:0];
    wire [7:0] query_addr0 = s_x0[10:3];
    wire [7:0] query_addr1 = s_x1[10:3];
    reg signed [2:0] ref_delta [0:2];

    assign query_slot0 = found_slot0;
    assign query_slot1 = (s_y1 == s_y0) ? found_slot0 : found_slot1;
    assign query_rows_found = found_row0 &&
        ((s_y1 == s_y0) || found_row1);
    assign s_ready = rstn && !source_frame_start && !fatal_fault &&
        query_rows_found && (!response_valid || m_ready);
    assign m_valid = response_valid;
    assign m_p00 = m_neighbor_valid[0] ?
        bank_data[response_slot0][response_bank0] : 32'd0;
    assign m_p10 = m_neighbor_valid[1] ?
        (response_same_x ? bank_data[response_slot0][response_bank0] :
                           bank_data[response_slot0][response_bank1]) : 32'd0;
    assign m_p01 = m_neighbor_valid[2] ?
        (response_same_row ? bank_data[response_slot0][response_bank0] :
                             bank_data[response_slot1][response_bank0]) : 32'd0;
    assign m_p11 = m_neighbor_valid[3] ?
        (response_same_row ?
            (response_same_x ? bank_data[response_slot0][response_bank0] :
                               bank_data[response_slot0][response_bank1]) :
            (response_same_x ? bank_data[response_slot1][response_bank0] :
                               bank_data[response_slot1][response_bank1])) : 32'd0;

    assign read_valid = rstn && (dma_state == DMA_AR) && !fatal_fault;
    assign read_reserve = read_valid;
    assign read_len = 4'd15;
    assign read_addr = {4'b0000, active_frame_slot, {SLOT_WORD_BITS{1'b0}}} +
        (load_row * IMAGE_WIDTH) + (burst_index * 16 * 8);
    assign idle = (dma_state == DMA_IDLE) && !response_valid &&
        (row_refs[0] == 0) && (row_refs[1] == 0) && (row_refs[2] == 0);

    always @* begin
        found_slot0 = 2'd0;
        found_slot1 = 2'd0;
        found_row0 = 1'b0;
        found_row1 = 1'b0;
        for (k0 = 0; k0 < 3; k0 = k0 + 1) begin
            if (valid_rows[k0] && row_tag[k0] == s_y0) begin
                found_slot0 = k0;
                found_row0 = 1'b1;
            end
            if (valid_rows[k0] && row_tag[k0] == s_y1) begin
                found_slot1 = k0;
                found_row1 = 1'b1;
            end
        end
    end

    always @* begin
        free_found = 1'b0;
        free_slot = 2'd0;
        for (k1 = 0; k1 < 3; k1 = k1 + 1) begin
            if (!free_found && (!valid_rows[k1] ||
                ((row_tag[k1] < required_y0) && (row_refs[k1] == 0)))) begin
                free_found = 1'b1;
                free_slot = k1;
            end
        end
    end

    always @* begin
        for (a0 = 0; a0 < 3; a0 = a0 + 1) begin
            bank_read_enable[a0] = 8'd0;
            for (b0 = 0; b0 < 8; b0 = b0 + 1)
                bank_read_addr[a0][b0] = 8'd0;
        end
        if (lookup_fire) begin
            bank_read_enable[query_slot0][query_bank0] = 1'b1;
            bank_read_addr[query_slot0][query_bank0] = query_addr0;
            if (!(query_bank0 == query_bank1 && query_addr0 == query_addr1)) begin
                bank_read_enable[query_slot0][query_bank1] = 1'b1;
                bank_read_addr[query_slot0][query_bank1] = query_addr1;
            end
            if (query_slot1 != query_slot0) begin
                bank_read_enable[query_slot1][query_bank0] = 1'b1;
                bank_read_addr[query_slot1][query_bank0] = query_addr0;
                if (!(query_bank0 == query_bank1 && query_addr0 == query_addr1)) begin
                    bank_read_enable[query_slot1][query_bank1] = 1'b1;
                    bank_read_addr[query_slot1][query_bank1] = query_addr1;
                end
            end
        end
    end

    always @* begin
        for (d0 = 0; d0 < 3; d0 = d0 + 1)
            ref_delta[d0] = 3'sd0;
        if (lookup_fire) begin
            ref_delta[query_slot0] = ref_delta[query_slot0] + 1'b1;
            if (query_slot1 != query_slot0)
                ref_delta[query_slot1] = ref_delta[query_slot1] + 1'b1;
        end
        if (response_fire) begin
            ref_delta[response_slot0] = ref_delta[response_slot0] - 1'b1;
            if (response_slot1 != response_slot0)
                ref_delta[response_slot1] = ref_delta[response_slot1] - 1'b1;
        end
    end

    genvar slot, bank;
    generate
        for (slot = 0; slot < 3; slot = slot + 1) begin: g_slot
            for (bank = 0; bank < 8; bank = bank + 1) begin: g_bank
                streaming_line_buffer_bank #(
                    .DEPTH(ROW_WORDS), .ADDR_WIDTH(ROW_ADDR_WIDTH)
                ) line_ram (
                    .clk(clk),
                    .wr_en((dma_state == DMA_DATA) && read_rvalid &&
                           load_slot == slot[1:0]),
                    .wr_addr(({4'd0, burst_index} << 4) + beat_index),
                    .wr_data(read_rdata[bank*32 +: 32]),
                    .rd_en(bank_read_enable[slot][bank]),
                    .rd_addr(bank_read_addr[slot][bank]),
                    .rd_data(bank_data[slot][bank])
                );
            end
        end
    endgenerate

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dma_state <= DMA_IDLE;
            active_frame_slot <= 2'd0;
            next_row <= 10'd0;
            load_row <= 10'd0;
            load_slot <= 2'd0;
            burst_index <= 4'd0;
            beat_index <= 4'd0;
            valid_rows <= 3'b000;
            row_tag[0] <= 10'd0;
            row_tag[1] <= 10'd0;
            row_tag[2] <= 10'd0;
            row_refs[0] <= 16'd0;
            row_refs[1] <= 16'd0;
            row_refs[2] <= 16'd0;
            required_y0 <= 10'd0;
            response_valid <= 1'b0;
            response_slot0 <= 2'd0;
            response_slot1 <= 2'd0;
            response_bank0 <= 3'd0;
            response_bank1 <= 3'd0;
            response_addr0 <= 8'd0;
            response_addr1 <= 8'd0;
            response_same_row <= 1'b0;
            response_same_x <= 1'b0;
            m_fx <= 16'd0;
            m_fy <= 16'd0;
            m_neighbor_valid <= 4'd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id <= 21'd0;
            m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0;
            m_eol <= 1'b0;
            m_eof <= 1'b0;
            fatal_fault <= 1'b0;
            read_error_count <= 16'd0;
            fetched_rows <= 32'd0;
        end else if (source_frame_start) begin
            if (dma_state != DMA_IDLE || !idle) begin
                fatal_fault <= 1'b1;
                if (read_error_count != 16'hffff)
                    read_error_count <= read_error_count + 1'b1;
            end else begin
                active_frame_slot <= source_frame_slot;
                next_row <= 10'd0;
                required_y0 <= 10'd0;
                valid_rows <= 3'b000;
                row_refs[0] <= 16'd0;
                row_refs[1] <= 16'd0;
                row_refs[2] <= 16'd0;
                response_valid <= 1'b0;
            end
        end else begin
            if (lookup_fire) begin
                response_valid <= 1'b1;
                response_slot0 <= query_slot0;
                response_slot1 <= query_slot1;
                response_bank0 <= query_bank0;
                response_bank1 <= query_bank1;
                response_addr0 <= query_addr0;
                response_addr1 <= query_addr1;
                response_same_row <= query_slot0 == query_slot1;
                response_same_x <= query_bank0 == query_bank1 &&
                                   query_addr0 == query_addr1;
                required_y0 <= s_y0;
                m_fx <= s_fx;
                m_fy <= s_fy;
                m_neighbor_valid <= s_neighbor_valid;
                m_geometry_valid <= s_geometry_valid;
                m_pixel_id <= s_pixel_id;
                m_frame_id <= s_frame_id;
                m_param_version <= s_param_version;
                m_sof <= s_sof;
                m_eol <= s_eol;
                m_eof <= s_eof;
            end else if (response_fire) begin
                response_valid <= 1'b0;
            end

            for (i = 0; i < 3; i = i + 1)
                if (ref_delta[i] != 0)
                    // Explicitly sign-extend the signed 3-bit net delta before
                    // adding it to the unsigned 16-bit reference count. Without
                    // this, a -1 response decrement can be zero-extended.
                    row_refs[i] <= row_refs[i] +
                        {{13{ref_delta[i][2]}}, ref_delta[i]};

            if (read_rvalid && dma_state != DMA_DATA) begin
                fatal_fault <= 1'b1;
                if (read_error_count != 16'hffff)
                    read_error_count <= read_error_count + 1'b1;
            end else begin
                case (dma_state)
                    DMA_IDLE: begin
                        if (next_row < IMAGE_HEIGHT && free_found) begin
                            load_row <= next_row;
                            load_slot <= free_slot;
                            valid_rows[free_slot] <= 1'b0;
                            burst_index <= 4'd0;
                            dma_state <= DMA_AR;
                        end
                    end
                    DMA_AR: if (read_valid && read_ready) begin
                        beat_index <= 4'd0;
                        dma_state <= DMA_DATA;
                    end
                    DMA_DATA: if (read_rvalid) begin
                        if (read_rlast != (beat_index == 4'd15)) begin
                            fatal_fault <= 1'b1;
                            if (read_error_count != 16'hffff)
                                read_error_count <= read_error_count + 1'b1;
                        end
                        if (beat_index == 4'd15) begin
                            if (burst_index == BURSTS_PER_ROW-1) begin
                                row_tag[load_slot] <= load_row;
                                valid_rows[load_slot] <= 1'b1;
                                next_row <= next_row + 1'b1;
                                fetched_rows <= fetched_rows + 1'b1;
                                dma_state <= DMA_IDLE;
                            end else begin
                                burst_index <= burst_index + 1'b1;
                                dma_state <= DMA_AR;
                            end
                        end else
                            beat_index <= beat_index + 1'b1;
                    end
                    default: dma_state <= DMA_IDLE;
                endcase
            end
        end
    end
endmodule
