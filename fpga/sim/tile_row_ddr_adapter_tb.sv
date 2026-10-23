`timescale 1ns / 1ps

module tile_row_ddr_adapter_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0;
    reg fill_req_valid = 0;
    wire fill_req_ready;
    reg [1:0] frame_slot = 0;
    reg [11:0] fill_tile_x = 0, fill_tile_y = 0;
    reg [1:0] fill_row_index = 0;
    wire read_valid, read_reserve;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_ready = 0, read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire fill_data_valid;
    reg fill_data_ready = 0;
    wire [255:0] fill_data;
    wire [11:0] fill_out_tile_x, fill_out_tile_y;
    wire [1:0] fill_out_row_index, fill_beat_index;
    wire idle, fatal_fault;
    wire [15:0] protocol_error_count;
    wire [31:0] completed_rows;
    integer i;

    tile_row_ddr_adapter dut (
        .clk(clk), .rstn(rstn),
        .fill_req_valid(fill_req_valid), .fill_req_ready(fill_req_ready),
        .frame_slot(frame_slot), .fill_tile_x(fill_tile_x),
        .fill_tile_y(fill_tile_y), .fill_row_index(fill_row_index),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(read_ready), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .fill_data_valid(fill_data_valid), .fill_data_ready(fill_data_ready),
        .fill_data(fill_data), .fill_out_tile_x(fill_out_tile_x),
        .fill_out_tile_y(fill_out_tile_y),
        .fill_out_row_index(fill_out_row_index),
        .fill_beat_index(fill_beat_index), .idle(idle),
        .fatal_fault(fatal_fault), .protocol_error_count(protocol_error_count),
        .completed_rows(completed_rows)
    );

    task automatic request_row(
        input [1:0] slot,
        input [11:0] tile_x,
        input [11:0] tile_y,
        input [1:0] row
    );
        begin
            @(negedge clk);
            frame_slot = slot;
            fill_tile_x = tile_x;
            fill_tile_y = tile_y;
            fill_row_index = row;
            fill_req_valid = 1;
            if (!fill_req_ready) $fatal(1, "FAIL: reader not ready for row");
            @(posedge clk);
            @(negedge clk);
            fill_req_valid = 0;
        end
    endtask

    task automatic transfer_row(
        input [27:0] expected_address,
        input [11:0] expected_tile_x,
        input [11:0] expected_tile_y,
        input [1:0] expected_row
    );
        begin
            read_ready = 0;
            repeat (3) begin
                if (!read_valid || !read_reserve || read_len !== 4'd3 ||
                    read_addr !== expected_address)
                    $fatal(1, "FAIL: stalled AR changed or lacks four-beat reservation");
                @(negedge clk);
            end
            read_ready = 1;
            @(posedge clk);
            @(negedge clk);
            read_ready = 0;
            fill_data_ready = 0;
            for (i = 0; i < 4; i = i + 1) begin
                read_rvalid = 1;
                read_rdata = {8{32'hA5000000 + i}};
                read_rlast = (i == 3);
                @(posedge clk);
                @(negedge clk);
            end
            read_rvalid = 0;
            read_rlast = 0;
            repeat (3) begin
                if (!fill_data_valid || fill_beat_index !== 2'd0 ||
                    fill_data !== {8{32'hA5000000}} || !(!fill_req_ready))
                    $fatal(1, "FAIL: buffered burst was lost under consumer stall");
                @(negedge clk);
            end
            fill_data_ready = 1;
            for (i = 0; i < 4; i = i + 1) begin
                if (!fill_data_valid || fill_beat_index !== i[1:0] ||
                    fill_data !== {8{32'hA5000000 + i}} ||
                    fill_out_tile_x !== expected_tile_x ||
                    fill_out_tile_y !== expected_tile_y ||
                    fill_out_row_index !== expected_row)
                    $fatal(1, "FAIL: buffered row data/metadata mismatch at beat %0d", i);
                @(posedge clk);
                @(negedge clk);
            end
            fill_data_ready = 0;
            if (!idle || !fill_req_ready || fatal_fault)
                $fatal(1, "FAIL: reader did not return to idle");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1;
        request_row(2'd0, 12'd0, 12'd0, 2'd0);
        transfer_row(28'd0, 12'd0, 12'd0, 2'd0);
        request_row(2'd2, 12'd39, 12'd179, 2'd3);
        transfer_row(28'd9310176, 12'd39, 12'd179, 2'd3);
        if (completed_rows !== 32'd2 || protocol_error_count !== 16'd0)
            $fatal(1, "FAIL: completed-row counters");

        request_row(2'd1, 12'd1, 12'd0, 2'd1);
        if (read_addr !== 28'd4195616) $fatal(1, "FAIL: middle row address");
        read_ready = 1;
        @(posedge clk);
        @(negedge clk);
        read_ready = 0;
        read_rvalid = 1;
        read_rlast = 1;  // Early RLAST must not publish a partial cache row.
        @(posedge clk);
        @(negedge clk);
        read_rvalid = 0;
        read_rlast = 0;
        if (!fatal_fault || protocol_error_count !== 16'd1 || fill_data_valid)
            $fatal(1, "FAIL: early RLAST did not latch a protocol fault");
        $display("PASS: tile row DDR address, reservation, buffering and fault test");
        $finish;
    end
endmodule
