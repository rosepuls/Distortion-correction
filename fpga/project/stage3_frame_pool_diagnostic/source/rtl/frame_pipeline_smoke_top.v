`timescale 1ns / 1ps

// PDS synthesis entry for the ownership scheduler and six-slot address map.
// This top is not connected to the HDMI pixel or DDR AXI datapaths.
module frame_pipeline_smoke_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire        frame_end,
    input  wire        frame_complete,
    input  wire        capture_source_busy,
    input  wire        copy_source_busy,
    input  wire        ddr_awvalid,
    input  wire        ddr_awready,
    input  wire [3:0]  ddr_awid,
    input  wire        ddr_wusero_last,
    input  wire [3:0]  ddr_wusero_id,
    input  wire        pix_clk,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire        display_take,
    input  wire        display_release,
    input  wire        copy_start_ready,
    input  wire        copy_done,
    input  wire        copy_error,
    input  wire        address_pool_output,
    input  wire [1:0]  address_slot,
    input  wire [21:0] address_offset,
    input  wire [1:0]  read_valid,
    input  wire [1:0]  read_reserve,
    input  wire [27:0] read0_addr,
    input  wire [27:0] read1_addr,
    input  wire [3:0]  read0_len,
    input  wire [3:0]  read1_len,
    input  wire        ddr_arready,
    input  wire        ddr_rvalid,
    input  wire        ddr_rlast,
    input  wire [7:0]  ddr_data_byte,
    output wire        capture_begin_ready,
    output wire [1:0]  capture_begin_slot,
    output wire        capture_active,
    output wire [1:0]  capture_slot,
    output wire        allow_capture,
    output wire        gated_wr_en,
    output wire        frame_admitted,
    output wire [15:0] drain_wait_cycles,
    output wire        capture_write_idle,
    output wire        copy_write_idle,
    output wire        write_protocol_fault,
    output wire        display_take_ready,
    output wire        display_active,
    output wire [1:0]  display_slot,
    output wire [31:0] display_sequence,
    output wire        copy_start,
    output wire [1:0]  copy_input_slot,
    output wire [1:0]  copy_output_slot,
    output wire [31:0] copy_input_sequence,
    output wire        copy_active,
    output wire [31:0] copied_count,
    output wire [31:0] copy_error_count,
    output wire        address_valid,
    output wire [27:0] address_word,
    output wire [1:0]  read_ready,
    output wire [1:0]  read_rvalid,
    output wire [1:0]  read_rlast,
    output wire [7:0]  read0_data_byte,
    output wire [7:0]  read1_data_byte,
    output wire [27:0] ddr_araddr,
    output wire [3:0]  ddr_arlen,
    output wire        ddr_arvalid,
    output wire        read_busy,
    output wire [15:0] read_error_count
);
    wire [255:0] read0_data;
    wire [255:0] read1_data;
    wire capture_begin;
    wire capture_publish;
    wire capture_abort;
    wire [15:0] capture_outstanding_unused;
    wire [15:0] copy_outstanding_unused;
    wire [15:0] write_error_count_unused;
    assign read0_data_byte = read0_data[7:0];
    assign read1_data_byte = read1_data[7:0];

    ddr_write_drain_tracker write_tracker (
        .clk(clk), .rstn(rstn),
        .awvalid(ddr_awvalid), .awready(ddr_awready),
        .awid(ddr_awid),
        .wusero_last(ddr_wusero_last),
        .wusero_id(ddr_wusero_id),
        .capture_source_busy(capture_source_busy),
        .copy_source_busy(copy_source_busy),
        .capture_write_idle(capture_write_idle),
        .copy_write_idle(copy_write_idle),
        .capture_outstanding(capture_outstanding_unused),
        .copy_outstanding(copy_outstanding_unused),
        .protocol_error_count(write_error_count_unused),
        .protocol_fault(write_protocol_fault)
    );

    capture_frame_admission admission (
        .clk(clk), .rstn(rstn),
        .frame_end(frame_end), .frame_complete(frame_complete),
        .write_idle(capture_write_idle),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin(capture_begin),
        .capture_publish(capture_publish),
        .capture_abort(capture_abort),
        .allow_capture(allow_capture),
        .drain_wait_cycles(drain_wait_cycles)
    );

    capture_pixel_gate pixel_gate (
        .pix_clk(pix_clk), .rstn(rstn),
        .vs_in(vs_in), .de_in(de_in),
        .allow_capture_ddr(allow_capture),
        .wr_en(gated_wr_en),
        .frame_admitted(frame_admitted)
    );

    ddr_read_burst_arbiter read_arbiter (
        .clk(clk), .rstn(rstn),
        .c0_valid(read_valid[0]), .c0_addr(read0_addr),
        .c0_len(read0_len), .c0_reserve(read_reserve[0]),
        .c0_ready(read_ready[0]), .c0_rvalid(read_rvalid[0]),
        .c0_rdata(read0_data), .c0_rlast(read_rlast[0]),
        .c1_valid(read_valid[1]), .c1_addr(read1_addr),
        .c1_len(read1_len), .c1_reserve(read_reserve[1]),
        .c1_ready(read_ready[1]), .c1_rvalid(read_rvalid[1]),
        .c1_rdata(read1_data), .c1_rlast(read_rlast[1]),
        .axi_araddr(ddr_araddr), .axi_arlen(ddr_arlen),
        .axi_arvalid(ddr_arvalid), .axi_arready(ddr_arready),
        .axi_rdata({248'd0, ddr_data_byte}),
        .axi_rvalid(ddr_rvalid), .axi_rlast(ddr_rlast),
        .busy(read_busy), .response_error_count(read_error_count)
    );

    frame_pipeline_ownership ownership (
        .clk(clk), .rstn(rstn),
        .capture_begin(capture_begin),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin_slot(capture_begin_slot),
        .capture_active(capture_active),
        .capture_slot(capture_slot),
        .capture_publish(capture_publish),
        .capture_abort(capture_abort),
        .display_take(display_take),
        .display_take_ready(display_take_ready),
        .display_active(display_active),
        .display_slot(display_slot),
        .display_sequence(display_sequence),
        .display_release(display_release),
        .copy_start(copy_start),
        .copy_start_ready(copy_start_ready),
        .copy_input_slot(copy_input_slot),
        .copy_output_slot(copy_output_slot),
        .copy_input_sequence(copy_input_sequence),
        .copy_done(copy_done),
        .copy_error(copy_error),
        .copy_active(copy_active),
        .copied_count(copied_count),
        .copy_error_count(copy_error_count)
    );

    frame_pool_address address_map (
        .pool_output(address_pool_output),
        .slot(address_slot),
        .word_offset(address_offset),
        .valid(address_valid),
        .word_address(address_word)
    );
endmodule
