`timescale 1ns/1ps

module tb_ddr_burst_reader;
    localparam integer IMAGE_WIDTH = 64;
    localparam integer IMAGE_HEIGHT = 8;
    localparam integer ADDR_WIDTH = 32;
    localparam [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = 32'h00001000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg fill_req_valid = 1'b0;
    wire fill_req_ready;
    reg [11:0] fill_tile_x = 12'd0;
    reg [11:0] fill_tile_y = 12'd0;
    reg [1:0] fill_row_index = 2'd0;

    wire rd_cmd_en;
    reg rd_cmd_ready = 1'b0;
    wire [ADDR_WIDTH-1:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_last = 1'b0;

    wire fill_data_valid;
    reg fill_data_ready = 1'b0;
    wire [255:0] fill_data;
    wire [11:0] fill_out_tile_x;
    wire [11:0] fill_out_tile_y;
    wire [1:0] fill_out_row_index;
    wire [1:0] fill_beat_index;

    integer errors = 0;
    integer command_count = 0;
    integer output_count = 0;
    integer backend_beat = 0;
    integer backend_wait = 0;
    reg backend_active = 1'b0;

    always #5 clk = ~clk;

    ddr_burst_reader #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .fill_req_valid(fill_req_valid),
        .fill_req_ready(fill_req_ready),
        .fill_tile_x(fill_tile_x),
        .fill_tile_y(fill_tile_y),
        .fill_row_index(fill_row_index),
        .rd_cmd_en(rd_cmd_en),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready),
        .rd_data(rd_data),
        .rd_data_last(rd_data_last),
        .fill_data_valid(fill_data_valid),
        .fill_data_ready(fill_data_ready),
        .fill_data(fill_data),
        .fill_out_tile_x(fill_out_tile_x),
        .fill_out_tile_y(fill_out_tile_y),
        .fill_out_row_index(fill_out_row_index),
        .fill_beat_index(fill_beat_index)
    );

    function automatic [255:0] expected_beat(input integer beat);
        begin
            expected_beat = {8{32'hA5000000 + beat}};
        end
    endfunction

    always @(posedge clk) begin
        if (rd_cmd_en && rd_cmd_ready) begin
            command_count = command_count + 1;
            if (rd_cmd_len !== 32'd4) begin
                $display("FAIL: expected four-beat command, got %0d", rd_cmd_len);
                errors = errors + 1;
            end
            if (command_count == 1 && rd_cmd_addr !== FRAME_BASE_BYTE_ADDR + 32'd640) begin
                $display("FAIL: first command address %h", rd_cmd_addr);
                errors = errors + 1;
            end
            if (command_count == 2 && rd_cmd_addr !== FRAME_BASE_BYTE_ADDR + 32'd896) begin
                $display("FAIL: second command address %h", rd_cmd_addr);
                errors = errors + 1;
            end
            backend_active <= 1'b1;
            backend_beat <= 0;
            backend_wait <= 2;
        end

        if (fill_data_valid && fill_data_ready) begin
            if (fill_data !== expected_beat(fill_beat_index)) begin
                $display("FAIL: beat %0d data mismatch", fill_beat_index);
                errors = errors + 1;
            end
            if (fill_out_tile_x !== 12'd1 || fill_out_tile_y !== 12'd0
                || fill_out_row_index !== ((command_count == 1) ? 2'd2 : 2'd3)) begin
                $display("FAIL: fill tag mismatch on output %0d", output_count);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    // Simple DDR response model: variable first-beat latency, then hold each
    // valid beat until the reader accepts it.
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_data_valid <= 1'b0;
            rd_data <= 256'd0;
            rd_data_last <= 1'b0;
            backend_active <= 1'b0;
        end else begin
            if (rd_data_valid && rd_data_ready) begin
                rd_data_valid <= 1'b0;
                if (backend_beat == 3) begin
                    rd_data_last <= 1'b0;
                    backend_active <= 1'b0;
                end else begin
                    backend_beat <= backend_beat + 1;
                end
            end else if (backend_active && !rd_data_valid) begin
                if (backend_wait != 0) begin
                    backend_wait <= backend_wait - 1;
                end else begin
                    rd_data <= expected_beat(backend_beat);
                    rd_data_valid <= 1'b1;
                    rd_data_last <= (backend_beat == 3);
                end
            end
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        rd_cmd_ready <= 1'b1;

        @(negedge clk);
        fill_tile_x <= 12'd1;
        fill_tile_y <= 12'd0;
        fill_row_index <= 2'd2;
        fill_req_valid <= 1'b1;
        @(posedge clk);
        if (!fill_req_ready) begin
            $display("FAIL: first fill request was not accepted");
            errors = errors + 1;
        end
        @(negedge clk);
        fill_req_valid <= 1'b0;

        // Hold the cache-side stream for five cycles after the command.
        repeat (5) @(posedge clk);
        fill_data_ready <= 1'b1;
        repeat (20) @(posedge clk);

        @(negedge clk);
        fill_row_index <= 2'd3;
        fill_req_valid <= 1'b1;
        @(posedge clk);
        if (!fill_req_ready) begin
            $display("FAIL: second fill request was not accepted");
            errors = errors + 1;
        end
        @(negedge clk);
        fill_req_valid <= 1'b0;
        repeat (20) @(posedge clk);

        if (command_count != 2) begin
            $display("FAIL: expected two DDR commands, got %0d", command_count);
            errors = errors + 1;
        end
        if (output_count != 8) begin
            $display("FAIL: expected eight output beats, got %0d", output_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr_burst_reader errors=%0d", errors);

        $display("TEST_PASS: ddr_burst_reader");
        $finish;
    end
endmodule
