`timescale 1ns/1ps

// Local reset leaves for the single 100 MHz algorithm clock domain.
//
// reset_n asserts all leaves asynchronously.  Each leaf is released only
// on staggered local clock edges, so a wide data-plane block is driven by a
// local reset register instead of the top-level algorithm reset net.  The
// staggered taps are deliberately non-equivalent, preventing their collapse
// into one high-fanout net during synthesis.
module algorithm_reset_tree (
    input  wire clk,
    input  wire reset_n,
    output wire geometry_rst_n,
    output wire fifo_rst_n,
    output wire fetch_control_rst_n,
    output wire fetch_storage_rst_n,
    output wire all_ready
);
    reg [4:0] reset_release;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_release <= 5'b00000;
        end else begin
            reset_release <= {reset_release[3:0], 1'b1};
        end
    end

    // Release after 2 / 3 / 4 / 5 local core-clock edges respectively.
    assign geometry_rst_n      = reset_release[1];
    assign fifo_rst_n          = reset_release[2];
    assign fetch_control_rst_n = reset_release[3];
    assign fetch_storage_rst_n = reset_release[4];
    assign all_ready           = reset_release[4];
endmodule
