`timescale 1ns / 1ps

// PDS synthesis entry for the two independent ownership pools. This is a
// hardware synthesis check, not the video or DDR integration top level.
module frame_pool_pair_smoke_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire [1:0]  producer_begin,
    input  wire [1:0]  producer_publish,
    input  wire [1:0]  producer_abort,
    input  wire [1:0]  consumer_take,
    input  wire [1:0]  consumer_release,
    input  wire        address_pool_output,
    input  wire [1:0]  address_slot,
    input  wire [21:0] address_offset,
    output wire        address_valid,
    output wire [27:0] address_word,
    output wire [1:0]  producer_begin_ready,
    output wire [3:0]  producer_begin_slot,
    output wire [1:0]  producer_active,
    output wire [3:0]  producer_slot,
    output wire [1:0]  consumer_take_ready,
    output wire [3:0]  consumer_take_slot,
    output wire [1:0]  consumer_active,
    output wire [3:0]  consumer_slot,
    output wire [63:0] consumer_sequence,
    output wire [63:0] publish_sequence,
    output wire [31:0] dropped_ready_count
);
    frame_pool_address address_map (
        .pool_output(address_pool_output),
        .slot(address_slot),
        .word_offset(address_offset),
        .valid(address_valid),
        .word_address(address_word)
    );

    frame_pool_manager capture_pool (
        .clk(clk), .rstn(rstn),
        .producer_begin(producer_begin[0]),
        .producer_begin_ready(producer_begin_ready[0]),
        .producer_begin_slot(producer_begin_slot[1:0]),
        .producer_active(producer_active[0]),
        .producer_slot(producer_slot[1:0]),
        .producer_publish(producer_publish[0]),
        .producer_abort(producer_abort[0]),
        .consumer_take(consumer_take[0]),
        .consumer_take_ready(consumer_take_ready[0]),
        .consumer_take_slot(consumer_take_slot[1:0]),
        .consumer_active(consumer_active[0]),
        .consumer_slot(consumer_slot[1:0]),
        .consumer_sequence(consumer_sequence[31:0]),
        .consumer_release(consumer_release[0]),
        .publish_sequence(publish_sequence[31:0]),
        .dropped_ready_count(dropped_ready_count[15:0])
    );

    frame_pool_manager output_pool (
        .clk(clk), .rstn(rstn),
        .producer_begin(producer_begin[1]),
        .producer_begin_ready(producer_begin_ready[1]),
        .producer_begin_slot(producer_begin_slot[3:2]),
        .producer_active(producer_active[1]),
        .producer_slot(producer_slot[3:2]),
        .producer_publish(producer_publish[1]),
        .producer_abort(producer_abort[1]),
        .consumer_take(consumer_take[1]),
        .consumer_take_ready(consumer_take_ready[1]),
        .consumer_take_slot(consumer_take_slot[3:2]),
        .consumer_active(consumer_active[1]),
        .consumer_slot(consumer_slot[3:2]),
        .consumer_sequence(consumer_sequence[63:32]),
        .consumer_release(consumer_release[1]),
        .publish_sequence(publish_sequence[63:32]),
        .dropped_ready_count(dropped_ready_count[31:16])
    );
endmodule
