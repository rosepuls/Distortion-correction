`timescale 1ns / 1ps

// Runs in the DDR clock domain. A slot remains owned until every write for
// that frame has left the write path. frame_end is the synchronized input VS
// boundary, and frame_complete describes the frame that just ended.
module capture_frame_admission (
    input  wire        clk,
    input  wire        rstn,
    input  wire        frame_end,
    input  wire        frame_complete,
    input  wire        write_idle,
    input  wire        capture_begin_ready,
    output wire        capture_begin,
    output wire        capture_publish,
    output wire        capture_abort,
    output wire        allow_capture,
    output reg  [15:0] drain_wait_cycles
);
    localparam [1:0] NEED_SLOT = 2'd0;
    localparam [1:0] CAPTURING = 2'd1;
    localparam [1:0] DRAIN_ABORT = 2'd2;
    localparam [1:0] DRAIN_PUBLISH = 2'd3;
    // Covers the legacy wr_buf line-trigger synchronizer and command launch.
    localparam [3:0] SETTLE_CYCLES = 4'd8;
    reg [1:0] state;
    reg [3:0] settle_count;

    assign capture_begin = rstn && (state == NEED_SLOT) &&
                           capture_begin_ready;
    assign capture_publish = rstn && (state == DRAIN_PUBLISH) &&
                             (settle_count == 4'd0) && write_idle;
    assign capture_abort = rstn && (state == DRAIN_ABORT) &&
                           (settle_count == 4'd0) && write_idle;
    assign allow_capture = rstn && (state == CAPTURING) && !frame_end;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= NEED_SLOT;
            settle_count <= 4'd0;
            drain_wait_cycles <= 16'd0;
        end else begin
            case (state)
                NEED_SLOT: begin
                    if (capture_begin)
                        state <= CAPTURING;
                end
                CAPTURING: begin
                    if (frame_end) begin
                        settle_count <= SETTLE_CYCLES;
                        if (frame_complete)
                            state <= DRAIN_PUBLISH;
                        else
                            state <= DRAIN_ABORT;
                    end
                end
                DRAIN_PUBLISH: begin
                    if (settle_count != 4'd0)
                        settle_count <= settle_count - 1'b1;
                    else if (write_idle)
                        state <= NEED_SLOT;
                    if (drain_wait_cycles != 16'hffff)
                        drain_wait_cycles <= drain_wait_cycles + 1'b1;
                end
                DRAIN_ABORT: begin
                    if (settle_count != 4'd0)
                        settle_count <= settle_count - 1'b1;
                    else if (write_idle)
                        state <= NEED_SLOT;
                    if (drain_wait_cycles != 16'hffff)
                        drain_wait_cycles <= drain_wait_cycles + 1'b1;
                end
                default: state <= NEED_SLOT;
            endcase
        end
    end
endmodule
