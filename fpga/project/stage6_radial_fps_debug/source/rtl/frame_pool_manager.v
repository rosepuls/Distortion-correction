`timescale 1ns / 1ps

// Three-slot latest-frame pool for one producer and one consumer.
// Instantiate once for captured input frames and once for processed output
// frames. All ports and slot state belong to one management clock domain.
//
// The producer must assert publish only after a complete frame has been
// written and all associated DDR write transactions have drained. It must
// assert abort only after an incomplete frame's outstanding writes have
// drained. The consumer holds a taken slot until release, or requests another
// slot with take; take switches atomically to the newest READY frame when one
// exists, and otherwise keeps the current lease.
module frame_pool_manager (
    input  wire        clk,
    input  wire        rstn,

    input  wire        producer_begin,
    output wire        producer_begin_ready,
    output wire [1:0]  producer_begin_slot,
    output reg         producer_active,
    output reg  [1:0]  producer_slot,
    input  wire        producer_publish,
    input  wire        producer_abort,

    input  wire        consumer_take,
    output wire        consumer_take_ready,
    output wire [1:0]  consumer_take_slot,
    output wire [31:0] consumer_take_sequence,
    output reg         consumer_active,
    output reg  [1:0]  consumer_slot,
    output reg  [31:0] consumer_sequence,
    input  wire        consumer_release,

    output wire        ready_valid,
    output wire [1:0]  ready_slot,
    output wire [31:0] ready_sequence,
    output reg  [31:0] publish_sequence,

    output reg  [15:0] producer_busy_count,
    output reg  [15:0] producer_no_slot_count,
    output reg  [15:0] producer_protocol_error_count,
    output reg  [15:0] producer_abort_count,
    output reg  [15:0] dropped_ready_count,
    output reg  [15:0] consumer_empty_count,
    output reg  [15:0] consumer_protocol_error_count
);
    localparam [1:0] SLOT_FREE    = 2'd0;
    localparam [1:0] SLOT_WRITING = 2'd1;
    localparam [1:0] SLOT_READY   = 2'd2;
    localparam [1:0] SLOT_READING = 2'd3;

    reg [1:0] slot_state [0:2];
    reg [31:0] slot_sequence [0:2];

    reg        free_found;
    reg [1:0]  free_index;
    reg        ready_found;
    reg [1:0]  newest_ready_index;
    reg [31:0] newest_ready_sequence;
    reg [2:0]  evict_count;
    integer scan_i;
    integer update_i;

    function seq_after;
        input [31:0] candidate;
        input [31:0] reference_sequence;
        reg signed [31:0] delta;
        begin
            delta = candidate - reference_sequence;
            seq_after = (delta > 0);
        end
    endfunction

    always @* begin
        free_found = 1'b0;
        free_index = 2'd0;
        ready_found = 1'b0;
        newest_ready_index = 2'd0;
        newest_ready_sequence = 32'd0;
        evict_count = 3'd0;

        for (scan_i = 0; scan_i < 3; scan_i = scan_i + 1) begin
            if (!free_found && slot_state[scan_i] == SLOT_FREE) begin
                free_found = 1'b1;
                free_index = scan_i[1:0];
            end

            if (slot_state[scan_i] == SLOT_READY &&
                (!ready_found || seq_after(slot_sequence[scan_i], newest_ready_sequence))) begin
                ready_found = 1'b1;
                newest_ready_index = scan_i[1:0];
                newest_ready_sequence = slot_sequence[scan_i];
            end

        end

        // Count READY slots that the consumer will not take this cycle.
        // This second pass uses the final newest_ready_index from the scan.
        for (scan_i = 0; scan_i < 3; scan_i = scan_i + 1) begin
            if (producer_active && producer_publish && !producer_abort &&
                slot_state[scan_i] == SLOT_READY &&
                !(consumer_take && ready_found && newest_ready_index == scan_i[1:0]))
                evict_count = evict_count + 1'b1;
        end
    end

    assign producer_begin_ready = !producer_active && free_found;
    assign producer_begin_slot = free_index;
    assign consumer_take_ready = ready_found;
    assign consumer_take_slot = newest_ready_index;
    assign consumer_take_sequence = newest_ready_sequence;
    assign ready_valid = ready_found;
    assign ready_slot = newest_ready_index;
    assign ready_sequence = newest_ready_sequence;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            slot_state[0] <= SLOT_FREE;
            slot_state[1] <= SLOT_FREE;
            slot_state[2] <= SLOT_FREE;
            slot_sequence[0] <= 32'd0;
            slot_sequence[1] <= 32'd0;
            slot_sequence[2] <= 32'd0;
            producer_active <= 1'b0;
            producer_slot <= 2'd0;
            consumer_active <= 1'b0;
            consumer_slot <= 2'd0;
            consumer_sequence <= 32'd0;
            publish_sequence <= 32'd0;
            producer_busy_count <= 16'd0;
            producer_no_slot_count <= 16'd0;
            producer_protocol_error_count <= 16'd0;
            producer_abort_count <= 16'd0;
            dropped_ready_count <= 16'd0;
            consumer_empty_count <= 16'd0;
            consumer_protocol_error_count <= 16'd0;
        end else begin
            if (producer_begin) begin
                if (producer_active) begin
                    if (producer_busy_count != 16'hffff)
                        producer_busy_count <= producer_busy_count + 16'd1;
                end else if (!free_found) begin
                    if (producer_no_slot_count != 16'hffff)
                        producer_no_slot_count <= producer_no_slot_count + 16'd1;
                end else begin
                    producer_active <= 1'b1;
                    producer_slot <= free_index;
                    slot_state[free_index] <= SLOT_WRITING;
                end
            end

            if (producer_publish && producer_abort) begin
                if (producer_protocol_error_count != 16'hffff)
                    producer_protocol_error_count <= producer_protocol_error_count + 16'd1;
            end else if (producer_publish) begin
                if (!producer_active) begin
                    if (producer_protocol_error_count != 16'hffff)
                        producer_protocol_error_count <= producer_protocol_error_count + 16'd1;
                end else begin
                    producer_active <= 1'b0;
                    publish_sequence <= publish_sequence + 32'd1;
                    slot_state[producer_slot] <= SLOT_READY;
                    slot_sequence[producer_slot] <= publish_sequence + 32'd1;

                    for (update_i = 0; update_i < 3; update_i = update_i + 1) begin
                        if (slot_state[update_i] == SLOT_READY &&
                            !(consumer_take && ready_found && newest_ready_index == update_i[1:0]))
                            slot_state[update_i] <= SLOT_FREE;
                    end

                    if (dropped_ready_count > (16'hffff - evict_count))
                        dropped_ready_count <= 16'hffff;
                    else
                        dropped_ready_count <= dropped_ready_count + evict_count;
                end
            end else if (producer_abort) begin
                if (!producer_active) begin
                    if (producer_protocol_error_count != 16'hffff)
                        producer_protocol_error_count <= producer_protocol_error_count + 16'd1;
                end else begin
                    producer_active <= 1'b0;
                    slot_state[producer_slot] <= SLOT_FREE;
                    if (producer_abort_count != 16'hffff)
                        producer_abort_count <= producer_abort_count + 16'd1;
                end
            end

            if (consumer_release) begin
                if (consumer_active) begin
                    consumer_active <= 1'b0;
                    slot_state[consumer_slot] <= SLOT_FREE;
                end else if (consumer_protocol_error_count != 16'hffff) begin
                    consumer_protocol_error_count <= consumer_protocol_error_count + 16'd1;
                end
                if (consumer_take && consumer_protocol_error_count != 16'hffff)
                    consumer_protocol_error_count <= consumer_protocol_error_count + 16'd1;
            end else if (consumer_take) begin
                if (!ready_found) begin
                    if (consumer_empty_count != 16'hffff)
                        consumer_empty_count <= consumer_empty_count + 16'd1;
                end else begin
                    if (consumer_active)
                        slot_state[consumer_slot] <= SLOT_FREE;
                    consumer_active <= 1'b1;
                    consumer_slot <= newest_ready_index;
                    consumer_sequence <= newest_ready_sequence;
                    slot_state[newest_ready_index] <= SLOT_READING;
                end
            end
        end
    end
endmodule
