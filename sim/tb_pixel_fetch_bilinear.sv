`timescale 1ns/1ps

module tb_pixel_fetch_bilinear;
    localparam integer ADDR_WIDTH = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [ADDR_WIDTH-1:0] in_x0 = '0;
    reg [ADDR_WIDTH-1:0] in_y0 = '0;
    reg [15:0] in_dx_q16 = '0;
    reg [15:0] in_dy_q16 = '0;
    reg in_coord_valid = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire in_ready;
    wire req_valid;
    wire req_ready;
    wire [ADDR_WIDTH-1:0] req_addr;
    wire rsp_valid;
    wire rsp_ready;
    wire [23:0] rsp_data;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    integer errors = 0;
    integer request_count = 0;
    integer request_index = 0;
    integer expected_requests [0:3];
    integer memory_index;
    reg [7:0] memory_byte;

    always #5 clk = ~clk;

    pixel_fetch_engine #(
        .FRAME_STRIDE_PIXELS(4),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) engine (
        .clk(clk),
        .rst_n(rst_n),
        .in_x0(in_x0),
        .in_y0(in_y0),
        .in_dx_q16(in_dx_q16),
        .in_dy_q16(in_dy_q16),
        .in_coord_valid(in_coord_valid),
        .in_valid(in_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .in_ready(in_ready),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    ddr_behavior_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PIXEL_WIDTH(24),
        .MEMORY_WORDS(16),
        .FIXED_LATENCY(2),
        .MAX_LATENCY(2)
    ) ddr (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data)
    );

    always @(posedge clk) begin
        if (rst_n && req_valid && req_ready) begin
            request_count = request_count + 1;
            if (request_index > 3 || req_addr !== expected_requests[request_index]) begin
                $display("FAIL: request[%0d] got=%0d expected=%0d", request_index, req_addr, expected_requests[request_index]);
                errors = errors + 1;
            end
            request_index = request_index + 1;
        end
    end

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_engine;
        begin
            rst_n = 1'b0;
            repeat (3) tick;
            rst_n = 1'b1;
        end
    endtask

    task automatic send_coordinate(
        input integer x,
        input integer y,
        input bit coordinate_valid,
        input bit sof_value,
        input bit eol_value
    );
        begin
            while (!in_ready) tick;
            @(negedge clk);
            in_x0 = x;
            in_y0 = y;
            in_dx_q16 = 16'd32768;
            in_dy_q16 = 16'd32768;
            in_coord_valid = coordinate_valid;
            in_sof = sof_value;
            in_eol = eol_value;
            in_valid = 1'b1;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
        end
    endtask

    task automatic wait_for_output(
        input [23:0] expected_pixel,
        input bit expected_sof,
        input bit expected_eol
    );
        integer timeout;
        begin
            timeout = 0;
            while (!out_valid && timeout < 100) begin
                tick;
                timeout = timeout + 1;
            end
            if (!out_valid) begin
                $display("FAIL: output timeout");
                errors = errors + 1;
            end else begin
                if (out_pixel !== expected_pixel) begin
                    $display("FAIL: output pixel got=%h expected=%h", out_pixel, expected_pixel);
                    errors = errors + 1;
                end
                if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                    $display("FAIL: output control got sof=%b eol=%b expected sof=%b eol=%b", out_sof, out_eol, expected_sof, expected_eol);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        // RGB888 test pattern: R=addr, G=addr+0x10, B=addr+0x20.
        #1;
        for (memory_index = 0; memory_index < 16; memory_index = memory_index + 1) begin
            memory_byte = memory_index[7:0];
            ddr.memory[memory_index] = {
                memory_byte,
                memory_byte + 8'h10,
                memory_byte + 8'h20
            };
        end

        expected_requests[0] = 5;
        expected_requests[1] = 6;
        expected_requests[2] = 9;
        expected_requests[3] = 10;
        reset_engine;

        send_coordinate(1, 1, 1'b1, 1'b1, 1'b0);
        wait_for_output(24'h071727, 1'b1, 1'b0);
        if (request_count != 4) begin
            $display("FAIL: expected four memory requests, got=%0d", request_count);
            errors = errors + 1;
        end

        // A second frame uses different RGB data and must not reuse stale pixels.
        for (memory_index = 0; memory_index < 16; memory_index = memory_index + 1) begin
            memory_byte = memory_index[7:0] + 8'd1;
            ddr.memory[memory_index] = {
                memory_byte,
                memory_byte + 8'h10,
                memory_byte + 8'h20
            };
        end
        request_count = 0;
        request_index = 0;
        send_coordinate(1, 1, 1'b1, 1'b1, 1'b0);
        wait_for_output(24'h081828, 1'b1, 1'b0);
        if (request_count != 4) begin
            $display("FAIL: second frame expected four memory requests, got=%0d", request_count);
            errors = errors + 1;
        end

        // Right edge and final row are invalid under the four-neighbor policy.
        send_coordinate(3, 1, 1'b0, 1'b0, 1'b1);
        wait_for_output(24'h000000, 1'b0, 1'b1);
        send_coordinate(1, 3, 1'b0, 1'b0, 1'b1);
        wait_for_output(24'h000000, 1'b0, 1'b1);
        if (request_count != 4) begin
            $display("FAIL: invalid coordinate issued a memory request");
            errors = errors + 1;
        end

        // Reset after the fourth request but before its response is returned.
        request_count = 0;
        request_index = 0;
        send_coordinate(1, 1, 1'b1, 1'b0, 1'b0);
        while (request_count < 4) tick;
        rst_n = 1'b0;
        tick;
        if (out_valid) begin
            $display("FAIL: reset produced an output from a discarded transaction");
            errors = errors + 1;
        end
        rst_n = 1'b1;

        if (errors == 0)
            $display("TEST_PASS: pixel_fetch_bilinear");
        else
            $display("TEST_FAIL: pixel_fetch_bilinear errors=%0d", errors);
        $finish;
    end
endmodule
