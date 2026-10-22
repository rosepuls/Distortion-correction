`timescale 1ns / 1ps

module frame_pool_address_tb;
    reg pool_output;
    reg [1:0] slot;
    reg [21:0] word_offset;
    wire valid;
    wire [27:0] word_address;
    integer pool_index;
    integer slot_index;
    reg [27:0] expected;

    frame_pool_address dut (
        .pool_output(pool_output),
        .slot(slot),
        .word_offset(word_offset),
        .valid(valid),
        .word_address(word_address)
    );

    initial begin
        for (pool_index = 0; pool_index < 2; pool_index = pool_index + 1) begin
            for (slot_index = 0; slot_index < 3; slot_index = slot_index + 1) begin
                pool_output = pool_index[0];
                slot = slot_index[1:0];
                word_offset = 22'd0;
                expected = (pool_index*3 + slot_index) << 22;
                #1;
                if (valid !== 1'b1 || word_address !== expected)
                    $fatal(1, "bad slot base for pool %0d slot %0d", pool_index, slot_index);
                word_offset = 22'd921599;
                #1;
                if (valid !== 1'b1 || word_address !== expected + 28'd921599)
                    $fatal(1, "bad last word for pool %0d slot %0d", pool_index, slot_index);
                word_offset = 22'd921600;
                #1;
                if (valid !== 1'b0)
                    $fatal(1, "padding word accepted for pool %0d slot %0d", pool_index, slot_index);
            end
        end
        pool_output = 1'b0;
        slot = 2'd3;
        word_offset = 22'd0;
        #1;
        if (valid !== 1'b0)
            $fatal(1, "invalid slot accepted");
        $display("PASS: frame_pool_address six-slot mapping test");
        $finish;
    end
endmodule
