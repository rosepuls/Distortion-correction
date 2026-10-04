`timescale 1ns/1ps

// A Tile-cache row request must become a DDR command in the same cycle.
// This avoids inserting a command-only bubble between every four-beat read.
module tb_ddr_burst_reader_zero_bubble;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg fill_req_valid = 1'b0;
    wire fill_req_ready;
    reg [11:0] fill_tile_x = 12'd3;
    reg [11:0] fill_tile_y = 12'd1;
    reg [1:0] fill_row_index = 2'd2;
    wire rd_cmd_en;
    reg rd_cmd_ready = 1'b1;
    wire [31:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_last = 1'b0;
    wire fill_data_valid;
    wire [255:0] fill_data;
    wire [11:0] fill_out_tile_x;
    wire [11:0] fill_out_tile_y;
    wire [1:0] fill_out_row_index;
    wire [1:0] fill_beat_index;
    integer errors = 0;
    integer request_cycle = -1;
    integer command_cycle = -1;
    integer cycle_count = 0;

    always #5 clk = ~clk;

    ddr_burst_reader #(
        .IMAGE_WIDTH(1920), .IMAGE_HEIGHT(1080), .ADDR_WIDTH(32),
        .FRAME_BASE_BYTE_ADDR(32'h0000_2000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .fill_req_valid(fill_req_valid), .fill_req_ready(fill_req_ready),
        .fill_tile_x(fill_tile_x), .fill_tile_y(fill_tile_y),
        .fill_row_index(fill_row_index),
        .rd_cmd_en(rd_cmd_en), .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr), .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last),
        .fill_data_valid(fill_data_valid), .fill_data_ready(1'b1),
        .fill_data(fill_data), .fill_out_tile_x(fill_out_tile_x),
        .fill_out_tile_y(fill_out_tile_y), .fill_out_row_index(fill_out_row_index),
        .fill_beat_index(fill_beat_index)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (fill_req_valid && fill_req_ready)
                request_cycle = cycle_count;
            if (rd_cmd_en && rd_cmd_ready) begin
                command_cycle = cycle_count;
                if (rd_cmd_addr != 32'h0000_2000 + (((1 * 4 + 2) * 1920 + 3 * 32) * 4)) begin
                    $display("FAIL: wrong zero-bubble command address %h", rd_cmd_addr);
                    errors = errors + 1;
                end
                if (rd_cmd_len != 32'd4) begin
                    $display("FAIL: wrong zero-bubble command length %0d", rd_cmd_len);
                    errors = errors + 1;
                end
            end
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(negedge clk);
        fill_req_valid <= 1'b1;
        @(negedge clk);
        fill_req_valid <= 1'b0;
        repeat (3) @(posedge clk);
        if (request_cycle < 0 || command_cycle < 0) begin
            $display("FAIL: request_cycle=%0d command_cycle=%0d", request_cycle, command_cycle);
            errors = errors + 1;
        end else if (command_cycle != request_cycle) begin
            $display("FAIL: command was delayed: request=%0d command=%0d", request_cycle, command_cycle);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr_burst_reader_zero_bubble errors=%0d", errors);
        $display("TEST_PASS: ddr_burst_reader_zero_bubble");
        $finish;
    end
endmodule
