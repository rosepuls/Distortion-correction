`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Meyesemi
// Engineer: Nill
// 
// Create Date: 15/03/23 14:17:29
// Design Name: 
// Module Name: fram_buf
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1
module fram_buf #(
    parameter                     MEM_ROW_WIDTH        = 15    ,
    parameter                     MEM_COLUMN_WIDTH     = 10    ,
    parameter                     MEM_BANK_WIDTH       = 3     ,
    parameter                     CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter                     MEM_DQ_WIDTH         = 32    ,
    parameter                     H_NUM                = 12'd1280,//12'd1920,
    parameter                     V_NUM                = 12'd720,//12'd1080,//12'd106,//
    parameter                     PIX_WIDTH            = 32//24 
)(
    input                         vin_clk,
    input                         wr_fsync,
    input                         wr_en,
    input  [PIX_WIDTH- 1'b1 : 0]  wr_data,
    output reg                    init_done=0,
    output [3:0]                  frame_error_led,
    
    input                         ddr_clk,
    input                         ddr_rstn,
    // Complete validated packet in the DDR clock domain.
    input                         angle_cfg_valid,
    input                         angle_cfg_pose_valid,
    input  [287:0]                angle_cfg_words,
    input  [15:0]                 angle_cfg_version,
    
    input                         vout_clk,
    input                         rd_fsync,
    input                         rd_en,
    output                        vout_de,
    output [PIX_WIDTH- 1'b1 : 0]  vout_data,
    
    output [CTRL_ADDR_WIDTH-1:0]  axi_awaddr     ,
    output [3:0]                  axi_awid       ,
    output [3:0]                  axi_awlen      ,
    output [2:0]                  axi_awsize     ,
    output [1:0]                  axi_awburst    ,
    input                         axi_awready    ,
    output                        axi_awvalid    ,
                                                  
    output [MEM_DQ_WIDTH*8-1:0]   axi_wdata      ,
    output [MEM_DQ_WIDTH -1 :0]   axi_wstrb      ,
    input                         axi_wlast      ,
    input  [3:0]                  axi_wusero_id  ,
    output                        axi_wvalid     ,
    input                         axi_wready     ,
    input  [3 : 0]                axi_bid        ,                                      
                                                  
    output [CTRL_ADDR_WIDTH-1:0]  axi_araddr     ,
    output [3:0]                  axi_arid       ,
    output [3:0]                  axi_arlen      ,
    output [2:0]                  axi_arsize     ,
    output [1:0]                  axi_arburst    ,
    output                        axi_arvalid    ,
    input                         axi_arready    ,
                                                  
    output                        axi_rready     ,
    input  [MEM_DQ_WIDTH*8-1:0]   axi_rdata      ,
    input                         axi_rvalid     ,
    input                         axi_rlast      ,
    input  [3:0]                  axi_rid            
);
    parameter LEN_WIDTH       = 32;
    parameter LINE_ADDR_WIDTH = 22;//19;//1440 * 1080 = 1 555 200 = 21'h17BB00
    parameter FRAME_CNT_WIDTH = CTRL_ADDR_WIDTH - LINE_ADDR_WIDTH;
    
    wire [27:0] capture_axi_awaddr;
    wire [3:0] capture_axi_awid, capture_axi_awlen;
    wire [255:0] capture_axi_wdata;
    wire [31:0] capture_axi_wstrb;
    wire capture_axi_awvalid, capture_axi_awready;
    wire capture_axi_wvalid, capture_axi_wready, capture_axi_wlast;
    wire tracked_capture_write_idle, write_arbiter_fault;
    wire [15:0] write_arbiter_error_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire copy_start, copy_start_ready, copy_done, copy_error;
    wire [1:0] copy_input_slot, copy_output_slot;
    wire copy_source_busy, copy_engine_active, copy_fatal_fault;
    wire [31:0] copy_completed_sequence;
    wire [23:0] perf_frame_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_coord_stall_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_cache_miss_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_cache_fill_cycles;
    wire [23:0] perf_read_ar_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_response_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_write_wait_cycles;
    wire [23:0] perf_write_phase_cycles;
    wire [23:0] perf_read_arbiter_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_arready_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_first_beat_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_interbeat_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire copy_read_wait_arbiter, copy_read_wait_arready;
    wire copy_read_valid, copy_read_reserve, copy_read_ready;
    wire [27:0] copy_read_addr;
    wire [3:0] copy_read_len;
    wire copy_read_rvalid, copy_read_rlast;
    wire [255:0] copy_read_rdata;
    wire copy_write_awvalid, copy_write_awready;
    wire [27:0] copy_write_awaddr;
    wire [3:0] copy_write_awlen;
    wire copy_write_wvalid, copy_write_wready, copy_write_wlast;
    wire [255:0] copy_write_wdata;
    wire [31:0] copy_write_wstrb;
    wire [15:0] copy_outstanding /* synthesis PAP_MARK_DEBUG="true" */;
    wire copy_physical_drained, display_pipe_ok;
    wire [15:0] pipeline_status /* synthesis PAP_MARK_DEBUG="true" */;
    assign pipeline_status = {5'd0, copy_physical_drained,
        capture_write_idle, output_frame_complete, display_frame_blocked,
        read_arbiter_error_count != 16'd0, display_read_error_count != 16'd0,
        write_protocol_fault, write_arbiter_fault, copy_fatal_fault,
        copy_active, display_valid};
    wire                        ddr_wreq;     
    wire [CTRL_ADDR_WIDTH- 1'b1 : 0] ddr_waddr;    
    wire [LEN_WIDTH- 1'b1 : 0]  ddr_wr_len;   
    wire                        ddr_wrdy;     
    wire                        ddr_wdone;    
    wire [8*MEM_DQ_WIDTH-1 : 0] ddr_wdata;    
    wire                        ddr_wdata_req;
    
    wire                        rd_cmd_en   ;
    wire [CTRL_ADDR_WIDTH-1:0]  rd_cmd_addr ;
    wire [LEN_WIDTH- 1'b1: 0]   rd_cmd_len  ;
    wire                        rd_cmd_ready;
    wire                        rd_cmd_done;
                                
    wire [9:0] display_consumed_gray;
    wire display_client_valid, display_client_reserve, display_client_ready;
    wire display_client_rvalid, display_client_rlast;
    wire [27:0] display_client_addr;
    wire [3:0] display_client_len;
    wire [255:0] display_client_rdata;
    wire display_line_error, display_frame_blocked;
    wire [15:0] display_read_error_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] read_arbiter_error_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [9:0] display_received_beats;
    wire [MEM_DQ_WIDTH*8-1:0]   read_rdata  ;
    wire                        read_en     ;
    wire                        ddr_wr_bac;
    wire [1:0] write_slot, display_slot;
    wire display_valid;
    wire capture_begin_ready, capture_begin, capture_publish, capture_abort;
    wire allow_capture, capture_write_idle, display_take_ready;
    wire gated_wr_en, frame_admitted, frame_reject_toggle;
    reg reject_meta, reject_sync, reject_prev;
    wire frame_rejected_ddr = reject_sync ^ reject_prev;
    wire write_source_busy, write_protocol_fault;
    wire [15:0] capture_outstanding /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] write_protocol_error_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] capture_dropped_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] output_dropped_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] drain_wait_cycles;
    wire input_frame_end, input_frame_complete;
    wire output_frame_start, output_frame_complete;
    wire write_busy_line, read_busy_line;
    wire [31:0] displayed_sequence /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] copy_input_sequence;
    wire [31:0] copied_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] copy_error_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [15:0] perf_error_flags;
    wire copy_active, copy_wait_input, copy_wait_output;
    reg [31:0] input_published_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [31:0] display_take_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [15:0] raw_input_vsync_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [15:0] capture_rejected_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [15:0] capture_abort_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [23:0] copy_frame_cycles_max;
    reg [23:0] copy_gap_max_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    reg [23:0] gap_input_at_max /* synthesis PAP_MARK_DEBUG="true" */;
    reg [23:0] gap_output_at_max /* synthesis PAP_MARK_DEBUG="true" */;
    reg gap_tracking;
    reg [23:0] gap_elapsed;
    reg [23:0] gap_input_elapsed, gap_output_elapsed;
    reg [15:0] incomplete_output_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [15:0] write_busy_count, read_busy_count;
    reg seen_output_vsync;
    // Sticky milestones exposed on LED4..LED7, from least to most advanced.
    reg raw_de_seen, gated_pixel_seen;
    reg publish_seen, display_seen;

    // The engine owns both leases until every ID-1 write has drained.
    frame_identity_transform_engine #(.RADIAL_MAPPING(2), .RADIAL_DENOM_SHIFT(21), .CACHE_SET_COUNT(16), .CACHE_WAYS(8)) copy_engine (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .start(copy_start), .start_ready(copy_start_ready),
        .input_slot(copy_input_slot), .output_slot(copy_output_slot),
        .input_sequence(copy_input_sequence),
        .angle_cfg_valid(angle_cfg_valid),
        .angle_cfg_pose_valid(angle_cfg_pose_valid),
        .angle_cfg_words(angle_cfg_words),
        .angle_cfg_version(angle_cfg_version),
        .copy_done(copy_done), .copy_error(copy_error),
        .active(copy_engine_active), .fatal_fault(copy_fatal_fault),
        .completed_sequence(copy_completed_sequence),
        .read_valid(copy_read_valid), .read_addr(copy_read_addr),
        .read_len(copy_read_len), .read_reserve(copy_read_reserve),
        .read_ready(copy_read_ready), .read_rvalid(copy_read_rvalid),
        .read_arbiter_wait(copy_read_wait_arbiter),
        .read_arready_wait(copy_read_wait_arready),
        .read_rdata(copy_read_rdata), .read_rlast(copy_read_rlast),
        .write_awvalid(copy_write_awvalid), .write_awaddr(copy_write_awaddr),
        .write_awlen(copy_write_awlen), .write_awready(copy_write_awready),
        .write_wvalid(copy_write_wvalid), .write_wdata(copy_write_wdata),
        .write_wstrb(copy_write_wstrb), .write_wready(copy_write_wready),
        .write_wlast(copy_write_wlast), .write_source_busy(copy_source_busy),
        .copy_write_idle(copy_physical_drained),
        .read_fault(read_arbiter_error_count != 16'd0),
        .write_fault(write_arbiter_fault || write_protocol_fault),
        .fetched_rows(), .tile_read_errors(),
        .perf_frame_cycles(perf_frame_cycles),
        .perf_coord_stall_cycles(perf_coord_stall_cycles),
        .perf_cache_miss_count(perf_cache_miss_count),
        .perf_cache_fill_cycles(perf_cache_fill_cycles),
        .perf_read_ar_wait_cycles(perf_read_ar_wait_cycles),
        .perf_read_response_wait_cycles(perf_read_response_wait_cycles),
        .perf_write_wait_cycles(perf_write_wait_cycles),
        .perf_write_phase_cycles(perf_write_phase_cycles),
        .perf_read_arbiter_wait_cycles(perf_read_arbiter_wait_cycles),
        .perf_read_arready_wait_cycles(perf_read_arready_wait_cycles),
        .perf_read_first_beat_wait_cycles(perf_read_first_beat_wait_cycles),
        .perf_read_interbeat_wait_cycles(perf_read_interbeat_wait_cycles)
    );
    assign perf_error_flags = {
        8'd0,
        copy_fatal_fault,
        display_frame_blocked,
        (incomplete_output_count != 16'd0),
        (copy_error_count != 32'd0),
        (write_protocol_error_count != 16'd0),
        (write_arbiter_error_count != 16'd0),
        (read_arbiter_error_count != 16'd0),
        (display_read_error_count != 16'd0)
    };
    assign copy_physical_drained = !copy_source_busy &&
        (copy_outstanding == 16'd0) &&
        !(axi_awvalid && axi_awid == 4'd1) &&
        !(axi_wready && axi_wlast && axi_wusero_id == 4'd1);
    // The adapter clears its frame-local block at the next VS when drained.
    // Its cumulative error counter remains sticky for diagnosis and must not
    // disable every later frame after a single recoverable underrun.
    assign display_pipe_ok = display_valid && !display_frame_blocked &&
        (read_arbiter_error_count == 16'd0);
    // AW and all W beats stay with one source until the Pango completion beat.
    // The capture controller must not see a copy burst's WLAST.
    ddr_write_burst_arbiter write_arbiter (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .c0_awvalid(capture_axi_awvalid), .c0_awaddr(capture_axi_awaddr),
        .c0_awlen(capture_axi_awlen), .c0_awready(capture_axi_awready),
        .c0_wvalid(capture_axi_wvalid), .c0_wdata(capture_axi_wdata),
        .c0_wstrb(capture_axi_wstrb), .c0_wready(capture_axi_wready),
        .c0_wlast(capture_axi_wlast),
        .c1_awvalid(copy_write_awvalid), .c1_awaddr(copy_write_awaddr),
        .c1_awlen(copy_write_awlen), .c1_awready(copy_write_awready),
        .c1_wvalid(copy_write_wvalid), .c1_wdata(copy_write_wdata),
        .c1_wstrb(copy_write_wstrb), .c1_wready(copy_write_wready),
        .c1_wlast(copy_write_wlast),
        .axi_awaddr(axi_awaddr), .axi_awid(axi_awid),
        .axi_awlen(axi_awlen), .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready), .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb), .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready), .axi_wlast(axi_wlast),
        .axi_wusero_id(axi_wusero_id), .busy(),
        .protocol_error_count(write_arbiter_error_count),
        .protocol_fault(write_arbiter_fault)
    );
    assign axi_awsize = 3'b110;
    assign axi_awburst = 2'b01;
    assign capture_write_idle = tracked_capture_write_idle && !write_arbiter_fault;
    ddr_write_drain_tracker write_tracker (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .awvalid(axi_awvalid), .awready(axi_awready), .awid(axi_awid),
        .wready(axi_wready),
        .wusero_last(axi_wlast), .wusero_id(axi_wusero_id),
        .capture_source_busy(write_source_busy), .copy_source_busy(copy_source_busy),
        .capture_write_idle(tracked_capture_write_idle), .copy_write_idle(),
        .capture_outstanding(capture_outstanding), .copy_outstanding(copy_outstanding),
        .protocol_error_count(write_protocol_error_count),
        .protocol_fault(write_protocol_fault)
    );

    capture_frame_admission admission (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .frame_end(input_frame_end), .frame_complete(input_frame_complete),
        .write_idle(capture_write_idle),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin(capture_begin),
        .capture_publish(capture_publish), .capture_abort(capture_abort),
        .allow_capture(allow_capture),
        .drain_wait_cycles(drain_wait_cycles)
    );

    capture_pixel_gate pixel_gate (
        .pix_clk(vin_clk), .rstn(ddr_rstn),
        .vs_in(wr_fsync), .de_in(wr_en),
        .allow_capture_ddr(allow_capture),
        .wr_en(gated_wr_en), .frame_admitted(frame_admitted),
        .frame_reject_toggle(frame_reject_toggle)
    );

    wire output_take_event = output_frame_start && display_take_ready &&
        (!display_valid || output_frame_complete);
    frame_pipeline_ownership ownership (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .capture_begin(capture_begin),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin_slot(),
        .capture_active(), .capture_slot(write_slot),
        .capture_publish(capture_publish), .capture_abort(capture_abort),
        .display_take(output_take_event),
        .display_take_ready(display_take_ready),
        .display_active(display_valid), .display_slot(display_slot),
        .display_sequence(displayed_sequence),
        .display_release(1'b0),
        .copy_start(copy_start), .copy_start_ready(copy_start_ready),
        .copy_input_slot(copy_input_slot), .copy_output_slot(copy_output_slot),
        .copy_input_sequence(copy_input_sequence),
        .copy_done(copy_done), .copy_error(copy_error), .copy_active(copy_active),
        .copy_wait_input(copy_wait_input), .copy_wait_output(copy_wait_output),
        .copied_count(copied_count), .copy_error_count(copy_error_count),
        .capture_dropped_ready_count(capture_dropped_count),
        .output_dropped_ready_count(output_dropped_count)
    );
    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            seen_output_vsync <= 1'b0;
            input_published_count <= 32'd0;
            display_take_count <= 32'd0;
            reject_meta <= 1'b0;
            reject_sync <= 1'b0;
            reject_prev <= 1'b0;
            raw_input_vsync_count <= 16'd0;
            capture_rejected_count <= 16'd0;
            capture_abort_count <= 16'd0;
            copy_frame_cycles_max <= 24'd0;
            copy_gap_max_cycles <= 24'd0;
            gap_input_at_max <= 24'd0;
            gap_output_at_max <= 24'd0;
            gap_tracking <= 1'b0;
            gap_elapsed <= 24'd0;
            gap_input_elapsed <= 24'd0;
            gap_output_elapsed <= 24'd0;
            incomplete_output_count <= 16'd0;
            write_busy_count <= 16'd0;
            read_busy_count <= 16'd0;
        end else begin
            reject_meta <= frame_reject_toggle;
            reject_sync <= reject_meta;
            reject_prev <= reject_sync;
            if (input_frame_end)
                raw_input_vsync_count <= raw_input_vsync_count + 1'b1;
            if (frame_rejected_ddr)
                capture_rejected_count <= capture_rejected_count + 1'b1;
            if (capture_abort)
                capture_abort_count <= capture_abort_count + 1'b1;
            if (capture_publish && input_published_count != 32'hffff_ffff)
                input_published_count <= input_published_count + 1'b1;
            if (output_take_event && display_take_count != 32'hffff_ffff)
                display_take_count <= display_take_count + 1'b1;
            if (copy_done && perf_frame_cycles > copy_frame_cycles_max)
                copy_frame_cycles_max <= perf_frame_cycles;
            if (copy_done || copy_error) begin
                gap_tracking <= 1'b1;
                gap_elapsed <= 24'd0;
                gap_input_elapsed <= 24'd0;
                gap_output_elapsed <= 24'd0;
            end else if (gap_tracking) begin
                if (copy_start && copy_start_ready) begin
                    if (gap_elapsed > copy_gap_max_cycles) begin
                        copy_gap_max_cycles <= gap_elapsed;
                        gap_input_at_max <= gap_input_elapsed;
                        gap_output_at_max <= gap_output_elapsed;
                    end
                    gap_tracking <= 1'b0;
                end else begin
                    if (gap_elapsed != 24'hffffff)
                        gap_elapsed <= gap_elapsed + 1'b1;
                    if (copy_wait_input && gap_input_elapsed != 24'hffffff)
                        gap_input_elapsed <= gap_input_elapsed + 1'b1;
                    if (copy_wait_output && gap_output_elapsed != 24'hffffff)
                        gap_output_elapsed <= gap_output_elapsed + 1'b1;
                end
            end
            if (output_frame_start)
                seen_output_vsync <= 1'b1;
            if (output_frame_start && seen_output_vsync && display_valid &&
                !output_frame_complete && incomplete_output_count != 16'hffff)
                incomplete_output_count <= incomplete_output_count + 1'b1;
            if (write_busy_line && write_busy_count != 16'hffff)
                write_busy_count <= write_busy_count + 1'b1;
            if (read_busy_line && read_busy_count != 16'hffff)
                read_busy_count <= read_busy_count + 1'b1;
        end
    end
    always @(posedge vin_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            raw_de_seen <= 1'b0;
            gated_pixel_seen <= 1'b0;
        end else begin
            if (wr_en)
                raw_de_seen <= 1'b1;
            if (gated_wr_en)
                gated_pixel_seen <= 1'b1;
        end
    end

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            publish_seen <= 1'b0;
            display_seen <= 1'b0;
        end else begin
            if (capture_publish)
                publish_seen <= 1'b1;
            if (display_valid)
                display_seen <= 1'b1;
        end
    end

    // Physical LED4..LED7 map to frame_error_led[0..3] at A17, A18, C17, B17.
    reg nonzero_output_seen;
    always @(posedge vout_clk or negedge ddr_rstn) begin
        if (!ddr_rstn)
            nonzero_output_seen <= 1'b0;
        else if (vout_de && (vout_data[31:8] != 24'd0))
            nonzero_output_seen <= 1'b1;
    end
    // LED4: adapter error, LED5: read-arbiter error,
    // LED6: current display gate, LED7: nonzero RGB ever seen.
    assign frame_error_led = {nonzero_output_seen, display_pipe_ok,
                              (read_arbiter_error_count != 16'd0),
                              (display_read_error_count != 16'd0) || copy_fatal_fault};

    wr_buf #(
        .ADDR_WIDTH       (  CTRL_ADDR_WIDTH  ),//parameter                     ADDR_WIDTH      = 6'd27,
        .ADDR_OFFSET      (  32'd0            ),//parameter                     ADDR_OFFSET     = 32'h0000_0000,
        .H_NUM            (  H_NUM            ),//parameter                     H_NUM           = 12'd1920,
        .V_NUM            (  V_NUM            ),//parameter                     V_NUM           = 12'd1080,
        .DQ_WIDTH         (  MEM_DQ_WIDTH     ),//parameter                     DQ_WIDTH        = 7'd32,
        .LEN_WIDTH        (  LEN_WIDTH        ),//parameter                     LEN_WIDTH       = 6'd16,
        .PIX_WIDTH        (  PIX_WIDTH        ),//parameter                     PIX_WIDTH       = 6'd24,
        .LINE_ADDR_WIDTH  (  LINE_ADDR_WIDTH  ),//parameter                     LINE_ADDR_WIDTH = 4'd19,
        .FRAME_CNT_WIDTH  (  FRAME_CNT_WIDTH  ) //parameter                     FRAME_CNT_WIDTH = 4'd8
    ) wr_buf (                                       
        .ddr_clk          (  ddr_clk          ),//input                         ddr_clk,
        .ddr_rstn         (  ddr_rstn         ),//input                         ddr_rstn,
                                              
        .wr_clk           (  vin_clk          ),//input                         wr_clk,
        .wr_fsync         (  wr_fsync         ),//input                         wr_fsync,
        .wr_en            (  gated_wr_en     ),//input                         wr_en,
        .wr_data          (  wr_data          ),//input  [PIX_WIDTH- 1'b1 : 0]  wr_data,
        
        .rd_bac           (  ddr_wr_bac       ),//input                         rd_bac,                                      
        .ddr_wreq         (  ddr_wreq         ),//output                        ddr_wreq,
        .ddr_waddr        (  ddr_waddr        ),//output [ADDR_WIDTH- 1'b1 : 0] ddr_waddr,
        .ddr_wr_len       (  ddr_wr_len       ),//output [LEN_WIDTH- 1'b1 : 0]  ddr_wr_len,
        .ddr_wrdy         (  ddr_wrdy         ),//input                         ddr_wrdy,
        .ddr_wdone        (  ddr_wdone        ),//input                         ddr_wdone,
        .ddr_wdata        (  ddr_wdata        ),//output [8*DQ_WIDTH- 1'b1 : 0] ddr_wdata,
        .ddr_wdata_req    (  ddr_wdata_req    ),//input                         ddr_wdata_req,
                                              
        .frame_wcnt       (                   ),//output [FRAME_CNT_WIDTH-1 :0] frame_wcnt,
        .frame_wirq       (  frame_wirq       ),
        .frame_slot       (  write_slot      ),
        .frame_end        (  input_frame_end ),
        .frame_complete   (  input_frame_complete ),
        .write_busy_line  (  write_busy_line ),
        .write_source_busy(  write_source_busy ) //output                        frame_wirq
    );
    
    always @(posedge ddr_clk)
    begin
        if(frame_wirq)
            init_done <= 1'b1;
        else
            init_done <= init_done;
    end 
    
    rd_buf #(
        .ADDR_WIDTH       (  CTRL_ADDR_WIDTH  ),//parameter                     ADDR_WIDTH      = 6'd27,
        .ADDR_OFFSET      (  32'h00c0_0000    ),//parameter                     ADDR_OFFSET     = 32'h0000_0000,
        .H_NUM            (  H_NUM            ),//parameter                     H_NUM           = 12'd1920,
        .V_NUM            (  V_NUM            ),//parameter                     V_NUM           = 12'd1080,
        .DQ_WIDTH         (  MEM_DQ_WIDTH     ),//parameter                     DQ_WIDTH        = 7'd32,
        .LEN_WIDTH        (  LEN_WIDTH        ),//parameter                     LEN_WIDTH       = 6'd16,
        .PIX_WIDTH        (  PIX_WIDTH        ),//parameter                     PIX_WIDTH       = 6'd24,
        .LINE_ADDR_WIDTH  (  LINE_ADDR_WIDTH  ),//parameter                     LINE_ADDR_WIDTH = 4'd19,
        .FRAME_CNT_WIDTH  (  FRAME_CNT_WIDTH  ) //parameter                     FRAME_CNT_WIDTH = 4'd8
    ) rd_buf (
        .ddr_clk         (  ddr_clk           ),//input                         ddr_clk,
        .ddr_rstn        (  ddr_rstn          ),//input                         ddr_rstn,

        .vout_clk        (  vout_clk          ),//input                         vout_clk,
        .rd_fsync        (  rd_fsync          ),//input                         rd_fsync,
        .rd_en           (  rd_en             ),//input                         rd_en,
        .vout_de         (  vout_de           ),//output                        vout_de,
        .vout_data       (  vout_data         ),//output [PIX_WIDTH- 1'b1 : 0]  vout_data,
        
        .init_done       (  init_done         ),//input init_done,
        .frame_slot      (  display_slot      ),
        .display_valid   (  display_pipe_ok   ),
        .frame_start     (  output_frame_start ),
        .frame_complete  (  output_frame_complete ),
        .read_busy_line  (  read_busy_line    ),
        .consumed_gray  (  display_consumed_gray ),
      
        .ddr_rreq        (  rd_cmd_en         ),//output                        ddr_rreq,
        .ddr_raddr       (  rd_cmd_addr       ),//output [ADDR_WIDTH- 1'b1 : 0] ddr_raddr,
        .ddr_rd_len      (  rd_cmd_len        ),//output [LEN_WIDTH- 1'b1 : 0]  ddr_rd_len,
        .ddr_rrdy        (  rd_cmd_ready      ),//input                         ddr_rrdy,
        .ddr_rdone       (  rd_cmd_done       ),//input                         ddr_rdone,
                                              
        .ddr_rdata       (  read_rdata        ),//input [8*DQ_WIDTH- 1'b1 : 0]  ddr_rdata,
        .ddr_rdata_en    (  read_en           ) //input                         ddr_rdata_en,
    );
    
    display_read_adapter display_adapter (
        .clk(ddr_clk), .rstn(ddr_rstn), .frame_reset(output_frame_start),
        .line_valid(rd_cmd_en), .line_addr(rd_cmd_addr),
        .line_beats(rd_cmd_len[9:0]), .line_ready(rd_cmd_ready),
        .consumed_gray(display_consumed_gray),
        .client_valid(display_client_valid), .client_addr(display_client_addr),
        .client_len(display_client_len), .client_reserve(display_client_reserve),
        .client_ready(display_client_ready),
        .client_rvalid(display_client_rvalid),
        .client_rdata(display_client_rdata), .client_rlast(display_client_rlast),
        .sink_rvalid(read_en), .sink_rdata(read_rdata), .sink_write_gray(),
        .line_done(rd_cmd_done), .line_error(display_line_error),
        .frame_blocked(display_frame_blocked), .busy(),
        .received_beats(display_received_beats),
        .protocol_error_count(display_read_error_count)
    );

    ddr_read_burst_arbiter read_arbiter (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .c0_valid(display_client_valid), .c0_addr(display_client_addr),
        .c0_len(display_client_len), .c0_reserve(display_client_reserve),
        .c0_ready(display_client_ready), .c0_rvalid(display_client_rvalid),
        .c0_rdata(display_client_rdata), .c0_rlast(display_client_rlast),
        .c1_valid(copy_read_valid), .c1_addr(copy_read_addr),
        .c1_len(copy_read_len), .c1_reserve(copy_read_reserve),
        .c1_ready(copy_read_ready), .c1_rvalid(copy_read_rvalid),
        .c1_rdata(copy_read_rdata), .c1_rlast(copy_read_rlast),
        .axi_araddr(axi_araddr), .axi_arid(axi_arid), .axi_arlen(axi_arlen),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast),
        .axi_rid(axi_rid),
        .busy(), .response_error_count(read_arbiter_error_count),
        .c1_wait_arbiter(copy_read_wait_arbiter),
        .c1_wait_arready(copy_read_wait_arready)
    );
    assign axi_arsize = 3'b110; // Preserve the accepted Pango read controller setting
    assign axi_arburst = 2'b01;
    assign axi_rready = 1'b1;
    wr_rd_ctrl_top#(
        .CTRL_ADDR_WIDTH  (  CTRL_ADDR_WIDTH  ),//parameter                    CTRL_ADDR_WIDTH      = 28,
        .MEM_DQ_WIDTH     (  MEM_DQ_WIDTH     ) //parameter                    MEM_DQ_WIDTH         = 16
    )wr_rd_ctrl_top (                         
        .clk              (  ddr_clk          ),//input                        clk            ,            
        .rstn             (  ddr_rstn         ),//input                        rstn           ,            
                                              
        .wr_cmd_en        (  ddr_wreq         ),//input                        wr_cmd_en   ,
        .wr_cmd_addr      (  ddr_waddr        ),//input  [CTRL_ADDR_WIDTH-1:0] wr_cmd_addr ,
        .wr_cmd_len       (  ddr_wr_len       ),//input  [31£º0]               wr_cmd_len  ,
        .wr_cmd_ready     (  ddr_wrdy         ),//output                       wr_cmd_ready,
        .wr_cmd_done      (  ddr_wdone        ),//output                       wr_cmd_done,
        .wr_bac           (  ddr_wr_bac       ),//output                       wr_bac,                                     
        .wr_ctrl_data     (  ddr_wdata        ),//input  [MEM_DQ_WIDTH*8-1:0]  wr_ctrl_data,
        .wr_data_re       (  ddr_wdata_req    ),//output                       wr_data_re  ,
                                              
        .rd_cmd_en        (  1'b0             ),//input                        rd_cmd_en   ,
        .rd_cmd_addr      (  {CTRL_ADDR_WIDTH{1'b0}} ),//input  [CTRL_ADDR_WIDTH-1:0] rd_cmd_addr ,
        .rd_cmd_len       (  32'd0            ),//input  [31£º0]               rd_cmd_len  ,
        .rd_cmd_ready     (                   ),//output                       rd_cmd_ready, 
        .rd_cmd_done      (                   ),//output                       rd_cmd_done,
                                              
        .read_ready       (  1'b0             ),//input                        read_ready  ,    
        .read_rdata       (                   ),//output [MEM_DQ_WIDTH*8-1:0]  read_rdata  ,    
        .read_en          (                   ),//output                       read_en     ,                                          
        // write channel                        
        .axi_awaddr       (  capture_axi_awaddr ),//output [CTRL_ADDR_WIDTH-1:0] axi_awaddr     ,  
        .axi_awid         (  capture_axi_awid   ),//output [3:0]                 axi_awid       ,
        .axi_awlen        (  capture_axi_awlen  ),//output [3:0]                 axi_awlen      ,
        .axi_awsize       (                   ),//output [2:0]                 axi_awsize     ,
        .axi_awburst      (                   ),//output [1:0]                 axi_awburst    , //only support 2'b01: INCR
        .axi_awready      (  capture_axi_awready ),//input                        axi_awready    ,
        .axi_awvalid      (  capture_axi_awvalid ),//output                       axi_awvalid    ,
                                              
        .axi_wdata        (  capture_axi_wdata  ),//output [MEM_DQ_WIDTH*8-1:0]  axi_wdata      ,
        .axi_wstrb        (  capture_axi_wstrb  ),//output [MEM_DQ_WIDTH -1 :0]  axi_wstrb      ,
        .axi_wlast        (  capture_axi_wlast ),//output                       axi_wlast      ,
        .axi_wvalid       (  capture_axi_wvalid ),//output                       axi_wvalid     ,
        .axi_wready       (  capture_axi_wready ),//input                        axi_wready     ,
        .axi_bid          (  4'd0             ),//input  [3 : 0]               axi_bid        , // Master Interface Write Response.
        .axi_bresp        (  2'd0             ),//input  [1 : 0]               axi_bresp      , // Write response. This signal indicates the status of the write transaction.
        .axi_bvalid       (  1'b0             ),//input                        axi_bvalid     , // Write response valid. This signal indicates that the channel is signaling a valid write response.
        .axi_bready       (                   ),//output                       axi_bready     ,
                                              
        // read channel                          
        .axi_araddr       (                   ),//output [CTRL_ADDR_WIDTH-1:0] axi_araddr     ,    
        .axi_arid         (                   ),//output [3:0]                 axi_arid       ,
        .axi_arlen        (                   ),//output [3:0]                 axi_arlen      ,
        .axi_arsize       (                   ),//output [2:0]                 axi_arsize     ,
        .axi_arburst      (                   ),//output [1:0]                 axi_arburst    ,
        .axi_arvalid      (                   ),//output                       axi_arvalid    , 
        .axi_arready      (  1'b0             ),//input                        axi_arready    , //only support 2'b01: INCR
                                              
        .axi_rready       (                   ),//output                       axi_rready     ,
        .axi_rdata        (  {MEM_DQ_WIDTH*8{1'b0}} ),//input  [MEM_DQ_WIDTH*8-1:0]  axi_rdata      ,
        .axi_rvalid       (  1'b0             ),//input                        axi_rvalid     ,
        .axi_rlast        (  1'b0             ),//input                        axi_rlast      ,
        .axi_rid          (  4'd0             ),//input  [3:0]                 axi_rid        ,
        .axi_rresp        (  2'd0             ) //input  [1:0]                 axi_rresp      
    );


endmodule
