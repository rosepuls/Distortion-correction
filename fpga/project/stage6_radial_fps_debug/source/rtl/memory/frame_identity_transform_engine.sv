`timescale 1ns / 1ps

// Process one completed input-frame lease into an output-frame lease. Both
// addresses count 32-bit RGBX8888 words. This module uses the same frame-pool
// and two-client DDR arbitration contract as frame_copy_engine. A fault is
// fail-stop: the partial output frame is never published and reset is required.
module frame_identity_transform_engine #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer FIFO_DEPTH = 16,
    parameter integer CACHE_SET_COUNT = 16,
    parameter integer CACHE_WAYS = 4,
    parameter integer RADIAL_MAPPING = 0,
    parameter integer RADIAL_DENOM_SHIFT = 23,
    parameter integer STALL_LIMIT = 24'hffffff
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         start,
    output wire         start_ready,
    input  wire [1:0]   input_slot,
    input  wire [1:0]   output_slot,
    input  wire [31:0]  input_sequence,
    output reg          copy_done,
    output reg          copy_error,
    output wire         active,
    output reg          fatal_fault,
    output reg  [31:0]  completed_sequence,
    output wire         read_valid,
    output wire [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         write_awvalid,
    output wire [27:0]  write_awaddr,
    output wire [3:0]   write_awlen,
    input  wire         write_awready,
    output wire         write_wvalid,
    output wire [255:0] write_wdata,
    output wire [31:0]  write_wstrb,
    input  wire         write_wready,
    input  wire         write_wlast,
    output wire         write_source_busy,
    input  wire         copy_write_idle,
    input  wire         read_fault,
    input  wire         write_fault,
    output wire [31:0]  fetched_rows,
    output wire [15:0]  tile_read_errors,
    output reg  [23:0]  perf_frame_cycles,
    output reg  [23:0]  perf_coord_stall_cycles,
    output reg  [23:0]  perf_cache_miss_count,
    output reg  [23:0]  perf_cache_fill_cycles,
    output reg  [23:0]  perf_read_ar_wait_cycles,
    output reg  [23:0]  perf_read_response_wait_cycles,
    output reg  [23:0]  perf_write_wait_cycles
);
    localparam integer PIXELS_PER_FRAME = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer PIXELS_PER_BURST = 128;
    localparam integer BURSTS_PER_FRAME = PIXELS_PER_FRAME / PIXELS_PER_BURST;
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] START_FRAME = 3'd1;
    localparam [2:0] COLLECT = 3'd2;
    localparam [2:0] WRITE_AW = 3'd3;
    localparam [2:0] WRITE_DATA = 3'd4;
    localparam [2:0] WAIT_DRAIN = 3'd5;
    localparam [2:0] FAULT = 3'd6;

    reg [2:0] state;
    reg [1:0] source_slot, destination_slot;
    reg [12:0] burst_index;
    reg [4:0] write_index;
    reg [3:0] beat_index;
    reg [2:0] lane_index;
    reg [255:0] packed_beat;
    reg [255:0] burst_data [0:15];
    reg [19:0] requested_pixels, returned_pixels;
    reg [10:0] request_u, response_u;
    reg [9:0] request_v;
    reg [31:0] stall_count;
    reg [23:0] frame_cycle_count;
    reg [23:0] coord_stall_count;
    reg [23:0] read_ar_wait_count;
    reg [23:0] read_response_wait_count;
    reg [23:0] write_wait_count;
    wire [23:0] pipeline_diag_miss_count;
    wire [23:0] pipeline_diag_fill_cycles;
    wire pipeline_read_response_wait;

    wire pipeline_s_valid, pipeline_s_ready, pipeline_m_valid, pipeline_m_ready;
    wire [31:0] pipeline_pixel, pipeline_frame_id;
    wire [19:0] pipeline_pixel_id;
    wire [15:0] pipeline_version;
    wire pipeline_geometry_valid, pipeline_sof, pipeline_eol, pipeline_eof;
    wire reader_idle, reader_fault;
    wire [4:0] fifo_level;
    wire request_fire = pipeline_s_ready && pipeline_s_valid;
    wire result_fire = pipeline_m_valid && pipeline_m_ready;
    wire [2:0] physical_output_slot = {1'b0, destination_slot} + 3'd3;
    wire [21:0] word_offset = {2'b00, burst_index, 7'b0000000};
    wire progress = request_fire || result_fire ||
                    (read_valid && read_ready) || read_rvalid ||
                    (write_awvalid && write_awready) ||
                    (write_wvalid && write_wready) ||
                    (state == WAIT_DRAIN && copy_write_idle);
    wire timeout = stall_count >= STALL_LIMIT;
    wire external_fault = read_fault || write_fault || reader_fault ||
                          (state != IDLE && timeout);
    wire result_mismatch = result_fire &&
        (pipeline_pixel_id != returned_pixels ||
         pipeline_frame_id != completed_sequence ||
         pipeline_version != 16'd0 || !pipeline_geometry_valid ||
         pipeline_sof != (returned_pixels == 0) ||
         pipeline_eol != (response_u == IMAGE_WIDTH-1) ||
         pipeline_eof != (returned_pixels == PIXELS_PER_FRAME-1));

    assign pipeline_s_valid = state == COLLECT &&
                              requested_pixels < PIXELS_PER_FRAME && !fatal_fault;
    assign pipeline_m_ready = state == COLLECT && !fatal_fault;
    assign start_ready = rstn && state == IDLE && !fatal_fault &&
                         !read_fault && !write_fault;
    assign active = state != IDLE;
    assign write_awvalid = rstn && state == WRITE_AW;
    assign write_awaddr = {3'b000, physical_output_slot, word_offset};
    assign write_awlen = 4'd15;
    assign write_wvalid = rstn && state == WRITE_DATA;
    assign write_wdata = burst_data[write_index[3:0]];
    assign write_wstrb = 32'hffffffff;
    assign write_source_busy = state == WRITE_AW || state == WRITE_DATA;

    stage5_identity_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .FIFO_DEPTH(FIFO_DEPTH),
        .CACHE_SET_COUNT(CACHE_SET_COUNT), .CACHE_WAYS(CACHE_WAYS),
        .RADIAL_MAPPING(RADIAL_MAPPING),
        .RADIAL_DENOM_SHIFT(RADIAL_DENOM_SHIFT)
    ) pipeline (
        .clk(clk), .rstn(rstn),
        .source_frame_start(state == START_FRAME),
        .source_frame_slot(source_slot),
        .s_valid(pipeline_s_valid), .s_ready(pipeline_s_ready),
        .s_u(request_u), .s_v(request_v),
        .s_pixel_id(requested_pixels),
        .s_frame_id(completed_sequence), .s_param_version(16'd0),
        .s_sof(requested_pixels == 0),
        .s_eol(request_u == IMAGE_WIDTH-1),
        .s_eof(requested_pixels == PIXELS_PER_FRAME-1),
        .m_valid(pipeline_m_valid), .m_ready(pipeline_m_ready),
        .m_pixel(pipeline_pixel),
        .m_geometry_valid(pipeline_geometry_valid),
        .m_pixel_id(pipeline_pixel_id),
        .m_frame_id(pipeline_frame_id),
        .m_param_version(pipeline_version),
        .m_sof(pipeline_sof), .m_eol(pipeline_eol), .m_eof(pipeline_eof),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(read_ready), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .reader_idle(reader_idle), .reader_fault(reader_fault),
        .read_error_count(tile_read_errors),
         .fetched_rows(fetched_rows), .fifo_level(fifo_level),
         .diagnostic_miss_count(pipeline_diag_miss_count),
         .diagnostic_fill_cycles(pipeline_diag_fill_cycles),
         .read_response_wait(pipeline_read_response_wait)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            source_slot <= 2'd0;
            destination_slot <= 2'd0;
            burst_index <= 13'd0;
            write_index <= 5'd0;
            beat_index <= 4'd0;
            lane_index <= 3'd0;
            packed_beat <= 256'd0;
            requested_pixels <= 20'd0;
            returned_pixels <= 20'd0;
            request_u <= 11'd0;
            request_v <= 10'd0;
            response_u <= 11'd0;
            stall_count <= 32'd0;
            frame_cycle_count <= 24'd0;
            coord_stall_count <= 24'd0;
            read_ar_wait_count <= 24'd0;
            read_response_wait_count <= 24'd0;
            write_wait_count <= 24'd0;
            perf_frame_cycles <= 24'd0;
            perf_coord_stall_cycles <= 24'd0;
            perf_cache_miss_count <= 24'd0;
            perf_cache_fill_cycles <= 24'd0;
            perf_read_ar_wait_cycles <= 24'd0;
            perf_read_response_wait_cycles <= 24'd0;
            perf_write_wait_cycles <= 24'd0;
            copy_done <= 1'b0;
            copy_error <= 1'b0;
            fatal_fault <= 1'b0;
            completed_sequence <= 32'd0;
        end else begin
            copy_done <= 1'b0;
            copy_error <= 1'b0;
            if (state != IDLE && frame_cycle_count != 24'hffffff)
                frame_cycle_count <= frame_cycle_count + 1'b1;
            if (state == COLLECT && pipeline_s_valid && !pipeline_s_ready &&
                coord_stall_count != 24'hffffff)
                coord_stall_count <= coord_stall_count + 1'b1;
            if (read_valid && !read_ready && read_ar_wait_count != 24'hffffff)
                read_ar_wait_count <= read_ar_wait_count + 1'b1;
            if (pipeline_read_response_wait &&
                read_response_wait_count != 24'hffffff)
                read_response_wait_count <= read_response_wait_count + 1'b1;
            if (((write_awvalid && !write_awready) ||
                 (write_wvalid && !write_wready)) &&
                write_wait_count != 24'hffffff)
                write_wait_count <= write_wait_count + 1'b1;
            if (state == IDLE || progress)
                stall_count <= 32'd0;
            else if (stall_count != 32'hffffffff)
                stall_count <= stall_count + 1'b1;

            if (external_fault || result_mismatch)
                fatal_fault <= 1'b1;

            case (state)
                IDLE: if (start && start_ready) begin
                    if (input_slot < 2'd3 && output_slot < 2'd3 && reader_idle) begin
                        source_slot <= input_slot;
                        destination_slot <= output_slot;
                        completed_sequence <= input_sequence;
                        burst_index <= 13'd0;
                        beat_index <= 4'd0;
                        lane_index <= 3'd0;
                        requested_pixels <= 20'd0;
                        returned_pixels <= 20'd0;
                        request_u <= 11'd0;
                        request_v <= 10'd0;
                        response_u <= 11'd0;
                        frame_cycle_count <= 24'd0;
                        coord_stall_count <= 24'd0;
                        read_ar_wait_count <= 24'd0;
                        read_response_wait_count <= 24'd0;
                        write_wait_count <= 24'd0;
                        state <= START_FRAME;
                    end else begin
                        fatal_fault <= 1'b1;
                        state <= FAULT;
                    end
                end
                START_FRAME: state <= (external_fault || fatal_fault) ?
                    FAULT : COLLECT;
                COLLECT: begin
                    if (external_fault || fatal_fault || result_mismatch)
                        state <= FAULT;
                    else begin
                        if (request_fire) begin
                            requested_pixels <= requested_pixels + 1'b1;
                            if (request_u == IMAGE_WIDTH-1) begin
                                request_u <= 11'd0;
                                request_v <= request_v + 1'b1;
                            end else
                                request_u <= request_u + 1'b1;
                        end
                        if (result_fire) begin
                            returned_pixels <= returned_pixels + 1'b1;
                            if (response_u == IMAGE_WIDTH-1)
                                response_u <= 11'd0;
                            else
                                response_u <= response_u + 1'b1;
                            if (lane_index == 3'd7) begin
                                burst_data[beat_index] <= {pipeline_pixel, packed_beat[223:0]};
                                lane_index <= 3'd0;
                                if (beat_index == 4'd15) begin
                                    beat_index <= 4'd0;
                                    state <= WRITE_AW;
                                end else
                                    beat_index <= beat_index + 1'b1;
                            end else begin
                                packed_beat[lane_index*32 +: 32] <= pipeline_pixel;
                                lane_index <= lane_index + 1'b1;
                            end
                        end
                    end
                end
                WRITE_AW: if (write_awvalid && write_awready) begin
                    write_index <= 5'd0;
                    state <= WRITE_DATA;
                end
                WRITE_DATA: if (write_wvalid && write_wready) begin
                    if (write_wlast != (write_index == 5'd15))
                        fatal_fault <= 1'b1;
                    if (write_index == 5'd15) begin
                        if (fatal_fault || external_fault ||
                            write_wlast != 1'b1)
                            state <= FAULT;
                        else if (burst_index == BURSTS_PER_FRAME-1)
                            state <= WAIT_DRAIN;
                        else begin
                            burst_index <= burst_index + 1'b1;
                            state <= COLLECT;
                        end
                    end else
                        write_index <= write_index + 1'b1;
                end
                WAIT_DRAIN: if (copy_write_idle) begin
                    if (!fatal_fault && !external_fault &&
                        returned_pixels == PIXELS_PER_FRAME && reader_idle &&
                        fifo_level == 0) begin
                        copy_done <= 1'b1;
                        perf_frame_cycles <= (frame_cycle_count == 24'hffffff)
                            ? frame_cycle_count : frame_cycle_count + 1'b1;
                        perf_coord_stall_cycles <= coord_stall_count;
                        perf_cache_miss_count <= pipeline_diag_miss_count;
                        perf_cache_fill_cycles <= pipeline_diag_fill_cycles;
                        perf_read_ar_wait_cycles <= read_ar_wait_count;
                        perf_read_response_wait_cycles <= read_response_wait_count;
                        perf_write_wait_cycles <= write_wait_count;
                        state <= IDLE;
                    end else begin
                        fatal_fault <= 1'b1;
                        state <= FAULT;
                    end
                end
                FAULT: state <= FAULT;
                default: state <= FAULT;
            endcase
        end
    end
endmodule
