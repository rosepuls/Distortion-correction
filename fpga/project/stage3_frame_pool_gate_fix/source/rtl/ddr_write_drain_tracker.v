`timescale 1ns / 1ps

// Tracks Pango DDR3 write bursts by AW user ID. The IP has no AXI B channel;
// axi_wusero_last is the completion indication available to this interface.
// IDs 0 and 1 are reserved for capture and copy writes respectively.
module ddr_write_drain_tracker (
    input  wire        clk,
    input  wire        rstn,
    input  wire        awvalid,
    input  wire        awready,
    input  wire [3:0]  awid,
    input  wire        wusero_last,
    input  wire [3:0]  wusero_id,
    input  wire        capture_source_busy,
    input  wire        copy_source_busy,
    output wire        capture_write_idle,
    output wire        copy_write_idle,
    output reg  [15:0] capture_outstanding,
    output reg  [15:0] copy_outstanding,
    output reg  [15:0] protocol_error_count,
    output reg         protocol_fault
);
    reg wusero_last_prev;
    wire complete_event = wusero_last && !wusero_last_prev;
    wire accept = awvalid && awready;
    wire accept_capture = accept && (awid == 4'd0);
    wire accept_copy = accept && (awid == 4'd1);
    wire complete_capture = complete_event && (wusero_id == 4'd0);
    wire complete_copy = complete_event && (wusero_id == 4'd1);
    wire bad_id = (accept && (awid != 4'd0) && (awid != 4'd1)) ||
                  (complete_event && (wusero_id != 4'd0) && (wusero_id != 4'd1));
    wire capture_underflow = complete_capture && !accept_capture &&
                             (capture_outstanding == 16'd0);
    wire copy_underflow = complete_copy && !accept_copy &&
                          (copy_outstanding == 16'd0);
    wire capture_overflow = accept_capture && !complete_capture &&
                            (capture_outstanding == 16'hffff);
    wire copy_overflow = accept_copy && !complete_copy &&
                         (copy_outstanding == 16'hffff);
    wire protocol_error = bad_id || capture_underflow || copy_underflow ||
                          capture_overflow || copy_overflow;

    // Check AWVALID as well as the counter: an address still waiting for
    // AWREADY is not yet counted. Keep idle low on the completion edge too.
    assign capture_write_idle = rstn && !protocol_fault &&
                                !capture_source_busy &&
                                (capture_outstanding == 16'd0) &&
                                !(awvalid && awid == 4'd0) &&
                                !complete_capture;
    assign copy_write_idle = rstn && !protocol_fault &&
                             !copy_source_busy &&
                             (copy_outstanding == 16'd0) &&
                             !(awvalid && awid == 4'd1) &&
                             !complete_copy;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wusero_last_prev <= 1'b0;
            capture_outstanding <= 16'd0;
            copy_outstanding <= 16'd0;
            protocol_error_count <= 16'd0;
            protocol_fault <= 1'b0;
        end else begin
            wusero_last_prev <= wusero_last;
            if (accept_capture && !complete_capture && !capture_overflow)
                capture_outstanding <= capture_outstanding + 1'b1;
            else if (complete_capture && !accept_capture && !capture_underflow)
                capture_outstanding <= capture_outstanding - 1'b1;

            if (accept_copy && !complete_copy && !copy_overflow)
                copy_outstanding <= copy_outstanding + 1'b1;
            else if (complete_copy && !accept_copy && !copy_underflow)
                copy_outstanding <= copy_outstanding - 1'b1;

            if (protocol_error) begin
                protocol_fault <= 1'b1;
                if (protocol_error_count != 16'hffff)
                    protocol_error_count <= protocol_error_count + 1'b1;
            end
        end
    end
endmodule
