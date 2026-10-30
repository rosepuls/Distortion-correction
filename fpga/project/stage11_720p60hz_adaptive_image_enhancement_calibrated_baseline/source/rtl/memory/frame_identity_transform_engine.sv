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
    input  wire         angle_cfg_valid,
    input  wire         angle_cfg_pose_valid,
    input  wire [287:0] angle_cfg_words,
    input  wire [15:0]  angle_cfg_version,
    input  wire [2:0]   angle_cfg_profile_id,
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
    input  wire         read_arbiter_wait,
    input  wire         read_arready_wait,
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
    output reg  [23:0]  perf_write_wait_cycles,
    output reg  [23:0]  perf_write_phase_cycles,
    output reg  [23:0]  perf_read_arbiter_wait_cycles,
    output reg  [23:0]  perf_read_arready_wait_cycles,
    output reg  [23:0]  perf_read_first_beat_wait_cycles,
    output reg  [23:0]  perf_read_interbeat_wait_cycles
);
    localparam integer PIXELS_PER_FRAME = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer PIXELS_PER_BURST = 128;
    localparam integer BURSTS_PER_FRAME = PIXELS_PER_FRAME / PIXELS_PER_BURST;
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] START_FRAME = 3'd1;
    localparam [2:0] COLLECT = 3'd2;
    localparam [2:0] WAIT_DRAIN = 3'd3;
    localparam [2:0] FAULT = 3'd4;
    localparam [1:0] WR_IDLE = 2'd0;
    localparam [1:0] WR_AW = 2'd1;
    localparam [1:0] WR_DATA = 2'd2;

    reg [2:0] state;
    reg [1:0] write_state;
    reg [1:0] source_slot, destination_slot;
    reg [12:0] collect_burst_index, write_burst_index;
    reg [1:0] burst_ready;
    reg [4:0] write_index;
    reg [3:0] beat_index;
    reg [2:0] lane_index;
    reg [255:0] packed_beat;
    reg [255:0] burst_data [0:31];
    reg [19:0] requested_pixels /* synthesis PAP_MARK_DEBUG="true" */;
    reg [19:0] returned_pixels;
    reg [10:0] request_u, response_u;
    reg [9:0] request_v /* synthesis PAP_MARK_DEBUG="true" */;
    reg [31:0] stall_count;
    reg [23:0] frame_cycle_count;
    reg [23:0] coord_stall_count;
    reg [23:0] read_ar_wait_count;
    reg [23:0] read_response_wait_count;
    reg [23:0] read_arbiter_wait_count;
    reg [23:0] read_arready_wait_count;
    reg [23:0] first_beat_wait_count;
    reg [23:0] interbeat_wait_count;
    reg [23:0] write_wait_count;
    reg [23:0] write_phase_count;
    wire [23:0] pipeline_diag_miss_count;
    wire [23:0] pipeline_diag_fill_cycles;
    wire pipeline_read_response_wait;
    wire pipeline_first_beat_wait, pipeline_interbeat_wait;

    wire pipeline_s_valid, pipeline_s_ready, pipeline_m_valid, pipeline_m_ready;
    wire [31:0] pipeline_pixel /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] pipeline_frame_id;
    wire [19:0] pipeline_pixel_id /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] pipeline_version;
    wire [287:0] active_homography_words;
    wire [15:0] active_homography_version;
    wire active_pose_valid, active_updated, pending_valid;
    wire [2:0] active_profile_id;
    reg [2:0] frame_profile_id;
    wire [31:0] enhanced_pixel;
    wire [15:0] pending_version;
    reg [15:0] frame_param_version;
    wire pipeline_geometry_valid /* synthesis PAP_MARK_DEBUG="true" */;
    wire pipeline_sof, pipeline_eol, pipeline_eof;
    wire reader_idle, reader_fault;
    wire [4:0] fifo_level;
    wire request_fire = pipeline_s_ready && pipeline_s_valid;
    wire result_fire = pipeline_m_valid && pipeline_m_ready;
    wire [2:0] physical_output_slot = {1'b0, destination_slot} + 3'd3;
    wire [21:0] word_offset = {2'b00, write_burst_index, 7'b0000000};
    wire progress = request_fire || result_fire ||
                    (read_valid && read_ready) || read_rvalid ||
                    (write_awvalid && write_awready) ||
                    (write_wvalid && write_wready) ||
                    (state == WAIT_DRAIN &&
                     write_burst_index == BURSTS_PER_FRAME && copy_write_idle);
    wire timeout = stall_count >= STALL_LIMIT;
    wire external_fault = read_fault || write_fault || reader_fault ||
                          (state != IDLE && timeout);
    wire result_mismatch = result_fire &&
        (pipeline_pixel_id != returned_pixels ||
         pipeline_frame_id != completed_sequence ||
         pipeline_version != frame_param_version ||
         pipeline_sof != (returned_pixels == 0) ||
         pipeline_eol != (response_u == IMAGE_WIDTH-1) ||
         pipeline_eof != (returned_pixels == PIXELS_PER_FRAME-1));

    assign pipeline_s_valid = state == COLLECT &&
                              requested_pixels < PIXELS_PER_FRAME && !fatal_fault;
    assign pipeline_m_ready = state == COLLECT && !fatal_fault &&
                              !burst_ready[collect_burst_index[0]];
    assign start_ready = rstn && state == IDLE && !fatal_fault &&
                         !read_fault && !write_fault;
    assign active = state != IDLE;
    assign write_awvalid = rstn && !fatal_fault && state != FAULT &&
                           write_state == WR_AW;
    assign write_awaddr = {3'b000, physical_output_slot, word_offset};
    assign write_awlen = 4'd15;
    assign write_wvalid = rstn && !fatal_fault && state != FAULT &&
                          write_state == WR_DATA;
    assign write_wdata = burst_data[{write_burst_index[0], write_index[3:0]}];
    assign write_wstrb = 32'hffffffff;
    assign write_source_busy = write_state != WR_IDLE || (|burst_ready);

    homography_parameter_bank parameters (
        .clk(clk), .rstn(rstn),
        .cfg_valid(angle_cfg_valid),
        .cfg_pose_valid(angle_cfg_pose_valid),
        .cfg_words(angle_cfg_words),
        .cfg_version(angle_cfg_version),
        .cfg_profile_id(angle_cfg_profile_id),
        .frame_start(start && start_ready &&
            input_slot < 2'd3 && output_slot < 2'd3 && reader_idle),
        .active_words(active_homography_words),
        .active_version(active_homography_version),
        .active_pose_valid(active_pose_valid),
        .active_profile_id(active_profile_id),
        .active_updated(active_updated),
        .pending_valid(pending_valid),
        .pending_version(pending_version)
    );

    lighting_lut_rom enhancement_lut (
        .profile_id(frame_profile_id),
        .red_in(pipeline_pixel[31:24]), .green_in(pipeline_pixel[23:16]),
        .blue_in(pipeline_pixel[15:8]),
        .red_out(enhanced_pixel[31:24]), .green_out(enhanced_pixel[23:16]),
        .blue_out(enhanced_pixel[15:8])
    );
    assign enhanced_pixel[7:0] = pipeline_pixel[7:0];

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
        .s_frame_id(completed_sequence), .s_param_version(frame_param_version),
        .homography_words(active_homography_words),
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
         .read_response_wait(pipeline_read_response_wait),
         .first_beat_wait(pipeline_first_beat_wait),
         .interbeat_wait(pipeline_interbeat_wait)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            write_state <= WR_IDLE;
            source_slot <= 2'd0;
            destination_slot <= 2'd0;
            collect_burst_index <= 13'd0;
            write_burst_index <= 13'd0;
            burst_ready <= 2'b00;
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
            read_arbiter_wait_count <= 24'd0;
            read_arready_wait_count <= 24'd0;
            first_beat_wait_count <= 24'd0;
            interbeat_wait_count <= 24'd0;
            write_wait_count <= 24'd0;
            write_phase_count <= 24'd0;
            perf_frame_cycles <= 24'd0;
            perf_coord_stall_cycles <= 24'd0;
            perf_cache_miss_count <= 24'd0;
            perf_cache_fill_cycles <= 24'd0;
            perf_read_ar_wait_cycles <= 24'd0;
            perf_read_response_wait_cycles <= 24'd0;
            perf_write_wait_cycles <= 24'd0;
            perf_write_phase_cycles <= 24'd0;
            perf_read_arbiter_wait_cycles <= 24'd0;
            perf_read_arready_wait_cycles <= 24'd0;
            perf_read_first_beat_wait_cycles <= 24'd0;
            perf_read_interbeat_wait_cycles <= 24'd0;
            copy_done <= 1'b0;
            copy_error <= 1'b0;
            fatal_fault <= 1'b0;
            completed_sequence <= 32'd0;
            frame_param_version <= 16'd0;
            frame_profile_id <= 3'd0;
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
            if (read_valid && read_arbiter_wait && read_arbiter_wait_count != 24'hffffff)
                read_arbiter_wait_count <= read_arbiter_wait_count + 1'b1;
            if (read_valid && read_arready_wait && read_arready_wait_count != 24'hffffff)
                read_arready_wait_count <= read_arready_wait_count + 1'b1;
            if (pipeline_first_beat_wait && first_beat_wait_count != 24'hffffff)
                first_beat_wait_count <= first_beat_wait_count + 1'b1;
            if (pipeline_interbeat_wait && interbeat_wait_count != 24'hffffff)
                interbeat_wait_count <= interbeat_wait_count + 1'b1;
            if (((write_awvalid && !write_awready) ||
                 (write_wvalid && !write_wready)) &&
                write_wait_count != 24'hffffff)
                write_wait_count <= write_wait_count + 1'b1;
            if ((write_state == WR_AW || write_state == WR_DATA) &&
                write_phase_count != 24'hffffff)
                write_phase_count <= write_phase_count + 1'b1;
            if (state == IDLE || progress)
                stall_count <= 32'd0;
            else if (stall_count != 32'hffffffff)
                stall_count <= stall_count + 1'b1;

            if (external_fault || result_mismatch)
                fatal_fault <= 1'b1;

            if (state == FAULT || external_fault || result_mismatch)
                write_state <= WR_IDLE;
            else case (write_state)
                WR_IDLE: if (burst_ready[write_burst_index[0]])
                    write_state <= WR_AW;
                WR_AW: if (write_awvalid && write_awready) begin
                    write_index <= 5'd0;
                    write_state <= WR_DATA;
                end
                WR_DATA: if (write_wvalid && write_wready) begin
                    if (write_wlast != (write_index == 5'd15)) begin
                        fatal_fault <= 1'b1;
                        write_state <= WR_IDLE;
                    end else if (write_index == 5'd15) begin
                        burst_ready[write_burst_index[0]] <= 1'b0;
                        write_burst_index <= write_burst_index + 1'b1;
                        write_state <= WR_IDLE;
                    end else
                        write_index <= write_index + 1'b1;
                end
                default: write_state <= WR_IDLE;
            endcase

            case (state)
                IDLE: if (start && start_ready) begin
                    if (input_slot < 2'd3 && output_slot < 2'd3 && reader_idle) begin
                        source_slot <= input_slot;
                        destination_slot <= output_slot;
                        completed_sequence <= input_sequence;
                        collect_burst_index <= 13'd0;
                        write_burst_index <= 13'd0;
                        burst_ready <= 2'b00;
                        write_state <= WR_IDLE;
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
                        read_arbiter_wait_count <= 24'd0;
                        read_arready_wait_count <= 24'd0;
                        first_beat_wait_count <= 24'd0;
                        interbeat_wait_count <= 24'd0;
                        write_wait_count <= 24'd0;
                        write_phase_count <= 24'd0;
                        state <= START_FRAME;
                    end else begin
                        fatal_fault <= 1'b1;
                        state <= FAULT;
                    end
                end
                START_FRAME: begin
                    frame_param_version <= active_homography_version;
                    frame_profile_id <= active_profile_id;
                    state <= (external_fault || fatal_fault) ? FAULT : COLLECT;
                end
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
                                burst_data[{collect_burst_index[0], beat_index}] <=
                                    {enhanced_pixel, packed_beat[223:0]};
                                lane_index <= 3'd0;
                                if (beat_index == 4'd15) begin
                                    beat_index <= 4'd0;
                                    burst_ready[collect_burst_index[0]] <= 1'b1;
                                    if (collect_burst_index == BURSTS_PER_FRAME-1)
                                        state <= WAIT_DRAIN;
                                    else
                                        collect_burst_index <= collect_burst_index + 1'b1;
                                end else
                                    beat_index <= beat_index + 1'b1;
                            end else begin
                                packed_beat[lane_index*32 +: 32] <= enhanced_pixel;
                                lane_index <= lane_index + 1'b1;
                            end
                        end
                    end
                end
                WAIT_DRAIN: if (write_burst_index == BURSTS_PER_FRAME &&
                               write_state == WR_IDLE && burst_ready == 2'b00 &&
                               copy_write_idle) begin
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
                        perf_write_phase_cycles <= write_phase_count;
                        perf_read_arbiter_wait_cycles <= read_arbiter_wait_count;
                        perf_read_arready_wait_cycles <= read_arready_wait_count;
                        perf_read_first_beat_wait_cycles <= first_beat_wait_count;
                        perf_read_interbeat_wait_cycles <= interbeat_wait_count;
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
