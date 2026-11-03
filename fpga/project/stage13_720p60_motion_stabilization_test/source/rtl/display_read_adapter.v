`timescale 1ns / 1ps

// Convert a line request (DDR address in 32-bit words, length in 256-bit
// beats) into bursts of at most 16 beats. The destination is a 512 x 256-bit
// circular dual-clock RAM. The pixel side advances a 10-bit beat counter and
// sends its Gray encoding; the extra bit distinguishes empty from full.
// No DDR RREADY exists, so each accepted AR reserves every return beat.
module display_read_adapter (
    input  wire         clk,
    input  wire         rstn,
    input  wire         frame_reset,
    input  wire         line_valid,
    input  wire [27:0]  line_addr,
    input  wire [9:0]   line_beats,
    output wire         line_ready,
    input  wire [9:0]   consumed_gray,
    output wire         client_valid,
    output wire [27:0]  client_addr,
    output wire [3:0]   client_len,
    output wire         client_reserve,
    input  wire         client_ready,
    input  wire         client_rvalid,
    input  wire [255:0] client_rdata,
    input  wire         client_rlast,
    output wire         sink_rvalid,
    output wire [255:0] sink_rdata,
    output wire [9:0]   sink_write_gray,
    output reg          line_done,
    output reg          line_error,
    output reg          frame_blocked,
    output reg          busy,
    output reg  [9:0]   received_beats,
    output reg  [15:0]  protocol_error_count
);
    localparam [10:0] FIFO_DEPTH = 11'd512;
    reg [9:0] consumed_meta, consumed_sync;
    reg [9:0] write_count;
    reg [27:0] next_addr;
    reg [9:0] remaining_beats;
    reg [4:0] burst_left;
    reg [4:0] reserved_left;
    reg inflight;

    function [9:0] gray_to_binary(input [9:0] gray);
        integer bit_index;
        begin
            gray_to_binary[9] = gray[9];
            for (bit_index = 8; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^ gray[bit_index];
        end
    endfunction

    wire [9:0] consumed_binary = gray_to_binary(consumed_sync);
    wire [9:0] occupied = write_count - consumed_binary;
    wire [10:0] committed = {1'b0, occupied} + {6'd0, reserved_left};
    // A modular distance above the physical depth means the pixel side has
    // consumed data that DDR has not delivered. Detect this even while idle.
    wire buffer_fault = committed > FIFO_DEPTH;
    wire [4:0] chunk_beats = (remaining_beats >= 10'd16) ?
                             5'd16 : {1'b0, remaining_beats[3:0]};
    wire can_reserve = !buffer_fault &&
                       (committed <= (FIFO_DEPTH - {6'd0, chunk_beats}));
    wire response_expected = client_rvalid && inflight;
    wire last_expected = (burst_left == 5'd1);
    wire response_bad = client_rvalid &&
                        (!inflight || (client_rlast != last_expected));

    assign line_ready = rstn && !busy && !frame_blocked && !buffer_fault;
    assign client_valid = rstn && busy && !inflight && !frame_blocked &&
                          !buffer_fault &&
                          (remaining_beats != 10'd0);
    assign client_addr = next_addr;
    assign client_len = chunk_beats - 5'd1;
    assign client_reserve = can_reserve;
    assign sink_rvalid = response_expected && !response_bad && !buffer_fault;
    assign sink_rdata = client_rdata;
    assign sink_write_gray = (write_count >> 1) ^ write_count;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            consumed_meta <= 10'd0;
            consumed_sync <= 10'd0;
            write_count <= 10'd0;
            next_addr <= 28'd0;
            remaining_beats <= 10'd0;
            burst_left <= 5'd0;
            reserved_left <= 5'd0;
            inflight <= 1'b0;
            line_done <= 1'b0;
            line_error <= 1'b0;
            frame_blocked <= 1'b0;
            busy <= 1'b0;
            received_beats <= 10'd0;
            protocol_error_count <= 16'd0;
        end else begin
            consumed_meta <= consumed_gray;
            consumed_sync <= consumed_meta;
            line_done <= 1'b0;
            line_error <= 1'b0;

            // Physical dual-port RAM pointers restart at output VS. Discard
            // old occupancy only when no DDR response can still write it.
            // The pixel-side Gray counter itself remains monotonic.
            if (frame_reset) begin
                if (!busy && !inflight) begin
                    write_count <= consumed_binary;
                    frame_blocked <= 1'b0;
                end else begin
                    frame_blocked <= 1'b1;
                    remaining_beats <= 10'd0;
                    if (!inflight)
                        busy <= 1'b0;
                    line_error <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end
            end

            if (line_valid && line_ready) begin
                next_addr <= line_addr;
                remaining_beats <= line_beats;
                received_beats <= 10'd0;
                busy <= (line_beats != 10'd0);
                if (line_beats == 10'd0) begin
                    line_error <= 1'b1;
                    if (protocol_error_count != 16'hffff)
                        protocol_error_count <= protocol_error_count + 1'b1;
                end
            end

            if (client_valid && client_reserve && client_ready) begin
                inflight <= 1'b1;
                burst_left <= chunk_beats;
                reserved_left <= chunk_beats;
                remaining_beats <= remaining_beats - {5'd0, chunk_beats};
                next_addr <= next_addr + {20'd0, chunk_beats, 3'b000};
            end

            if (response_expected && !response_bad) begin
                write_count <= write_count + 1'b1;
                received_beats <= received_beats + 1'b1;
                reserved_left <= reserved_left - 1'b1;
                burst_left <= burst_left - 1'b1;
                if (last_expected) begin
                    inflight <= 1'b0;
                    if (remaining_beats == 10'd0) begin
                        busy <= 1'b0;
                        line_done <= !frame_blocked && !frame_reset;
                    end
                end
            end

            if (response_bad || (buffer_fault && !frame_blocked)) begin
                busy <= 1'b0;
                inflight <= 1'b0;
                reserved_left <= 5'd0;
                line_error <= 1'b1;
                frame_blocked <= 1'b1;
                if (protocol_error_count != 16'hffff)
                    protocol_error_count <= protocol_error_count + 1'b1;
            end
        end
    end
endmodule
