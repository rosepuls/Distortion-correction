`timescale 1ns/1ps

// Contract test for the board-side cache/DDR address-unit boundary.
// The cache owns byte addressing; the MES50HP command controller owns
// 32-bit-word addressing.  One 32-byte Tile Cache request must therefore
// become an eight-word controller address without changing its beat count.
module tb_ddr3_rgbx_cache_adapter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cache_cmd_en = 1'b0;
    wire cache_cmd_ready;
    reg [31:0] cache_cmd_byte_addr = 32'd0;
    reg [31:0] cache_cmd_len = 32'd0;
    wire ctrl_cmd_en;
    reg ctrl_cmd_ready = 1'b0;
    wire [27:0] ctrl_cmd_word_addr;
    wire [31:0] ctrl_cmd_len;
    reg ctrl_data_valid = 1'b0;
    wire ctrl_data_ready;
    reg [255:0] ctrl_data = 256'd0;
    wire cache_data_valid;
    reg cache_data_ready = 1'b0;
    wire [255:0] cache_data;
    wire cache_data_last;
    integer errors = 0;
    integer returned_beats = 0;

    always #5 clk = ~clk;

    ddr3_rgbx_cache_adapter #(
        .CACHE_ADDR_WIDTH(32),
        .CTRL_ADDR_WIDTH(28)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_base_word_addr(28'h0200000),
        .cache_cmd_en(cache_cmd_en),
        .cache_cmd_ready(cache_cmd_ready),
        .cache_cmd_byte_addr(cache_cmd_byte_addr),
        .cache_cmd_len(cache_cmd_len),
        .ctrl_cmd_en(ctrl_cmd_en),
        .ctrl_cmd_ready(ctrl_cmd_ready),
        .ctrl_cmd_word_addr(ctrl_cmd_word_addr),
        .ctrl_cmd_len(ctrl_cmd_len),
        .ctrl_data_valid(ctrl_data_valid),
        .ctrl_data_ready(ctrl_data_ready),
        .ctrl_data(ctrl_data),
        .cache_data_valid(cache_data_valid),
        .cache_data_ready(cache_data_ready),
        .cache_data(cache_data),
        .cache_data_last(cache_data_last)
    );

    always @(posedge clk) begin
        if (cache_data_valid && cache_data_ready) begin
            if (cache_data !== {224'd0, returned_beats[31:0]}) begin
                $display("FAIL: beat %0d data did not propagate", returned_beats);
                errors = errors + 1;
            end
            if (cache_data_last !== (returned_beats == 3)) begin
                $display("FAIL: beat %0d last=%b", returned_beats, cache_data_last);
                errors = errors + 1;
            end
            returned_beats = returned_beats + 1;
        end
    end

    task automatic send_controller_beat(input [31:0] value);
        begin
            @(negedge clk);
            ctrl_data <= {224'd0, value};
            ctrl_data_valid <= 1'b1;
            do @(posedge clk); while (!ctrl_data_ready);
            @(negedge clk);
            ctrl_data_valid <= 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // A Tile Cache row begins at byte 0x80.  With a completed input frame
        // at controller word base 0x0200000, the controller must see 0x0200020.
        @(negedge clk);
        cache_cmd_byte_addr <= 32'h0000_0080;
        cache_cmd_len <= 32'd4;
        cache_cmd_en <= 1'b1;
        ctrl_cmd_ready <= 1'b0;
        repeat (2) @(posedge clk);
        if (ctrl_cmd_en !== 1'b1 || cache_cmd_ready !== 1'b0) begin
            $display("FAIL: command was not held during controller backpressure");
            errors = errors + 1;
        end

        @(negedge clk);
        ctrl_cmd_ready <= 1'b1;
        @(posedge clk);
        if (ctrl_cmd_word_addr !== 28'h0200020 || ctrl_cmd_len !== 32'd4) begin
            $display("FAIL: word address=%h len=%0d", ctrl_cmd_word_addr, ctrl_cmd_len);
            errors = errors + 1;
        end
        @(negedge clk);
        cache_cmd_en <= 1'b0;
        ctrl_cmd_ready <= 1'b0;
        cache_data_ready <= 1'b1;

        send_controller_beat(32'd0);
        send_controller_beat(32'd1);

        // The consumer may stall; a pending data beat must remain valid and
        // must not consume the burst-last count until it is accepted.
        @(negedge clk);
        cache_data_ready <= 1'b0;
        ctrl_data <= {224'd0, 32'd2};
        ctrl_data_valid <= 1'b1;
        repeat (2) @(posedge clk);
        if (!cache_data_valid || cache_data_last) begin
            $display("FAIL: stalled third beat valid=%b last=%b", cache_data_valid, cache_data_last);
            errors = errors + 1;
        end
        @(negedge clk);
        cache_data_ready <= 1'b1;
        @(posedge clk);
        @(negedge clk);
        ctrl_data_valid <= 1'b0;

        send_controller_beat(32'd3);
        repeat (2) @(posedge clk);

        if (returned_beats != 4) begin
            $display("FAIL: expected 4 returned beats, got %0d", returned_beats);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr3_rgbx_cache_adapter errors=%0d", errors);
        $display("TEST_PASS: ddr3_rgbx_cache_adapter");
        $finish;
    end
endmodule
