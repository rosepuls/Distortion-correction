`timescale 1ns / 1ps

// DDR-clock-domain ownership scheduler for capture -> copy -> display.
// External capture_publish/abort may pulse only after capture DDR writes
// drain. copy_done/error may pulse only after the copy engine's DDR writes
// drain. display_take is a completed display-frame boundary event.
// Slot numbers are local to their pool; use frame_pool_address to convert
// them to disjoint physical DDR word addresses.
module frame_pipeline_ownership (
    input  wire        clk,
    input  wire        rstn,

    input  wire        capture_begin,
    output wire        capture_begin_ready,
    output wire [1:0]  capture_begin_slot,
    output wire        capture_active,
    output wire [1:0]  capture_slot,
    input  wire        capture_publish,
    input  wire        capture_abort,

    input  wire        display_take,
    output wire        display_take_ready,
    output wire        display_active,
    output wire [1:0]  display_slot,
    output wire [31:0] display_sequence,
    input  wire        display_release,

    output wire        copy_start,
    input  wire        copy_start_ready,
    output wire [1:0]  copy_input_slot,
    output wire [1:0]  copy_output_slot,
    output wire [31:0] copy_input_sequence,
    input  wire        copy_done,
    input  wire        copy_error,
    output wire        copy_active,

    output reg  [31:0] copied_count,
    output reg  [31:0] copy_error_count,
    output wire [15:0] capture_dropped_ready_count,
    output wire [15:0] output_dropped_ready_count
);
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] BUSY = 2'd2;
    reg [1:0] state;

    wire capture_ready_valid;
    wire output_begin_ready;
    wire [1:0] capture_read_slot;
    wire [31:0] capture_read_sequence;
    wire [1:0] output_write_slot;
    wire capture_take_ready_unused;
    wire [1:0] capture_take_slot_unused;
    wire [1:0] output_begin_slot_unused;
    wire [1:0] display_take_slot_unused;

    // Both leases are acquired on the same DDR clock edge. The copy engine
    // receives their registered slot numbers on the following edge.
    wire schedule = rstn && (state == IDLE) &&
                    capture_ready_valid && output_begin_ready;
    wire finish_copy = (state == BUSY) && (copy_done || copy_error);

    frame_pool_manager capture_pool (
        .clk(clk), .rstn(rstn),
        .producer_begin(capture_begin),
        .producer_begin_ready(capture_begin_ready),
        .producer_begin_slot(capture_begin_slot),
        .producer_active(capture_active),
        .producer_slot(capture_slot),
        .producer_publish(capture_publish),
        .producer_abort(capture_abort),
        .consumer_take(schedule),
        .consumer_take_ready(capture_take_ready_unused),
        .consumer_take_slot(capture_take_slot_unused),
        .consumer_active(),
        .consumer_slot(capture_read_slot),
        .consumer_sequence(capture_read_sequence),
        .consumer_release(finish_copy),
        .ready_valid(capture_ready_valid),
        .dropped_ready_count(capture_dropped_ready_count)
    );

    frame_pool_manager output_pool (
        .clk(clk), .rstn(rstn),
        .producer_begin(schedule),
        .producer_begin_ready(output_begin_ready),
        .producer_begin_slot(output_begin_slot_unused),
        .producer_active(),
        .producer_slot(output_write_slot),
        .producer_publish(finish_copy && !copy_error),
        .producer_abort(finish_copy && copy_error),
        .consumer_take(display_take),
        .consumer_take_ready(display_take_ready),
        .consumer_take_slot(display_take_slot_unused),
        .consumer_active(display_active),
        .consumer_slot(display_slot),
        .consumer_sequence(display_sequence),
        .consumer_release(display_release),
        .dropped_ready_count(output_dropped_ready_count)
    );

    assign copy_start = (state == START);
    assign copy_active = (state != IDLE);
    assign copy_input_slot = capture_read_slot;
    assign copy_output_slot = output_write_slot;
    assign copy_input_sequence = capture_read_sequence;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            copied_count <= 32'd0;
            copy_error_count <= 32'd0;
        end else begin
            case (state)
                IDLE: if (schedule) state <= START;
                START: if (copy_start_ready) state <= BUSY;
                BUSY: if (finish_copy) state <= IDLE;
                default: state <= IDLE;
            endcase

            if (finish_copy && copy_error) begin
                if (copy_error_count != 32'hffff_ffff)
                    copy_error_count <= copy_error_count + 32'd1;
            end else if (finish_copy && copy_done) begin
                if (copied_count != 32'hffff_ffff)
                    copied_count <= copied_count + 32'd1;
            end
        end
    end
endmodule
