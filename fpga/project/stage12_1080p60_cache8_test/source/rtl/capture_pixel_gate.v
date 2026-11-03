`timescale 1ns / 1ps

// Pixel-clock side of frame admission. The DDR-side permission is sampled
// only at the first active pixel after VS and then held for the full frame.
// The video blanking interval must exceed the two-flop CDC latency plus the
// DDR-side VS synchronization and slot handoff latency.
module capture_pixel_gate (
    input  wire pix_clk,
    input  wire rstn,
    input  wire vs_in,
    input  wire de_in,
    input  wire allow_capture_ddr,
    output wire wr_en,
    output reg  frame_admitted
);
    reg allow_meta;
    reg allow_sync;
    reg vs_prev;
    reg seen_vs;
    reg frame_decided;
    wire vs_rise = vs_in && !vs_prev;
    wire first_pixel = de_in && seen_vs && !frame_decided;

    assign wr_en = de_in && seen_vs &&
                   (frame_decided ? frame_admitted : allow_sync);

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            allow_meta <= 1'b0;
            allow_sync <= 1'b0;
            vs_prev <= 1'b0;
            seen_vs <= 1'b0;
            frame_decided <= 1'b0;
            frame_admitted <= 1'b0;
        end else begin
            allow_meta <= allow_capture_ddr;
            allow_sync <= allow_meta;
            vs_prev <= vs_in;
            if (vs_rise) begin
                seen_vs <= 1'b1;
                frame_decided <= 1'b0;
                frame_admitted <= 1'b0;
            end else if (first_pixel) begin
                frame_decided <= 1'b1;
                frame_admitted <= allow_sync;
            end
        end
    end
endmodule
