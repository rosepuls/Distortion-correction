`timescale 1ns / 1ps

// PG2L200H RGBX8888 frame allocation, in DDR controller 32-bit-word units.
// Each slot reserves 2^22 words; output slots hold 1920*1080 RGBX words.
// Slots 0..2 belong to capture, and slots 3..5 belong to processed output.
module frame_pool_address (
    input  wire        pool_output,
    input  wire [1:0]  slot,
    input  wire [21:0] word_offset,
    output wire        valid,
    output wire [27:0] word_address
);
    wire [2:0] physical_slot = {1'b0, slot} + (pool_output ? 3'd3 : 3'd0);

    assign valid = (slot < 2'd3) &&
                   (word_offset < (pool_output ? 22'd2073600 : 22'd921600));
    assign word_address = {3'b000, physical_slot, word_offset};
endmodule
