`timescale 1ns/1ps

module tb_ddr_behavior_model;
    localparam integer ADDR_WIDTH = 8;
    localparam integer PIXEL_WIDTH = 24;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg                  req_valid = 1'b0;
    wire                 req_ready;
    reg  [ADDR_WIDTH-1:0] req_addr = '0;
    wire                 rsp_valid;
    reg                  rsp_ready = 1'b0;
    wire [PIXEL_WIDTH-1:0] rsp_data;

    reg                  req_valid_var = 1'b0;
    wire                 req_ready_var;
    reg  [ADDR_WIDTH-1:0] req_addr_var = '0;
    wire                 rsp_valid_var;
    reg                  rsp_ready_var = 1'b0;
    wire [PIXEL_WIDTH-1:0] rsp_data_var;

    integer errors = 0;
    integer queue_head = 0;
    integer queue_tail = 0;
    integer expected_addr [0:31];
    reg stalled_seen = 1'b0;
    reg [PIXEL_WIDTH-1:0] stalled_data = '0;

    always #5 clk = ~clk;

    ddr_behavior_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .MEMORY_WORDS(64),
        .FIXED_LATENCY(2),
        .MAX_LATENCY(2)
    ) fixed_dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data)
    );

    ddr_behavior_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .MEMORY_WORDS(64),
        .FIXED_LATENCY(1),
        .MAX_LATENCY(3)
    ) variable_dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid_var),
        .req_ready(req_ready_var),
        .req_addr(req_addr_var),
        .rsp_valid(rsp_valid_var),
        .rsp_ready(rsp_ready_var),
        .rsp_data(rsp_data_var)
    );

    always @(posedge clk) begin
        if (rst_n && rsp_valid && !rsp_ready) begin
            if (stalled_seen && rsp_data !== stalled_data) begin
                $display("FAIL: response changed while stalled");
                errors = errors + 1;
            end
            stalled_seen = 1'b1;
            stalled_data = rsp_data;
        end
        if (!rsp_valid || rsp_ready) begin
            stalled_seen = 1'b0;
        end
    end

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_duts;
        begin
            rst_n = 1'b0;
            req_valid = 1'b0;
            req_valid_var = 1'b0;
            rsp_ready = 1'b0;
            rsp_ready_var = 1'b0;
            repeat (3) tick;
            rst_n = 1'b1;
        end
    endtask

    task automatic send_fixed_request(input integer address);
        begin
            while (!req_ready) tick;
            @(negedge clk);
            req_addr = address[ADDR_WIDTH-1:0];
            req_valid = 1'b1;
            if (!req_ready) begin
                $display("FAIL: fixed request was not accepted on handshake");
                errors = errors + 1;
            end else begin
                expected_addr[queue_tail] = address;
                queue_tail = queue_tail + 1;
            end
            @(posedge clk);
            #1;
            req_valid = 1'b0;
        end
    endtask

    task automatic consume_fixed_response;
        integer timeout;
        begin
            timeout = 0;
            while (!rsp_valid && timeout < 20) begin
                tick;
                timeout = timeout + 1;
            end
            if (!rsp_valid) begin
                $display("FAIL: fixed response timeout");
                errors = errors + 1;
            end else if (rsp_data !== expected_addr[queue_head]) begin
                $display("FAIL: response order/data mismatch got=%h expected=%h", rsp_data, expected_addr[queue_head]);
                errors = errors + 1;
            end
            rsp_ready = 1'b1;
            tick;
            queue_head = queue_head + 1;
            rsp_ready = 1'b0;
        end
    endtask

    task automatic send_variable_request(input integer address);
        begin
            while (!req_ready_var) tick;
            @(negedge clk);
            req_addr_var = address[ADDR_WIDTH-1:0];
            req_valid_var = 1'b1;
            if (!req_ready_var) begin
                $display("FAIL: variable request was not accepted on handshake");
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
            req_valid_var = 1'b0;
        end
    endtask

    integer variable_responses;
    integer variable_timeout;
    initial begin
        reset_duts;

        // Fixed latency and request/response order.
        rsp_ready = 1'b1;
        send_fixed_request(3);
        consume_fixed_response;

        // Response backpressure: data must remain stable until ready.
        send_fixed_request(11);
        variable_timeout = 0;
        while (!rsp_valid && variable_timeout < 20) begin
            tick;
            variable_timeout = variable_timeout + 1;
        end
        if (!rsp_valid) begin
            $display("FAIL: backpressure response timeout");
            errors = errors + 1;
        end
        repeat (3) tick;
        if (!rsp_valid || rsp_data !== 11) begin
            $display("FAIL: stalled response was not held");
            errors = errors + 1;
        end
        rsp_ready = 1'b1;
        tick;
        rsp_ready = 1'b0;
        queue_head = queue_head + 1;

        // Reset while a response is pending must discard that response.
        rsp_ready = 1'b0;
        send_fixed_request(17);
        while (!rsp_valid) tick;
        rst_n = 1'b0;
        tick;
        if (rsp_valid) begin
            $display("FAIL: reset did not clear pending response");
            errors = errors + 1;
        end
        queue_head = queue_head + 1;
        rst_n = 1'b1;
        rsp_ready = 1'b1;
        send_fixed_request(19);
        consume_fixed_response;

        // Variable latency sequence 1, 2, 3 with one request at a time.
        rsp_ready_var = 1'b1;
        variable_responses = 0;
        repeat (3) begin
            send_variable_request(21 + variable_responses);
            variable_timeout = 0;
            while (!rsp_valid_var && variable_timeout < 20) begin
                tick;
                variable_timeout = variable_timeout + 1;
            end
            if (!rsp_valid_var) begin
                $display("FAIL: variable response timeout index=%0d", variable_responses);
                errors = errors + 1;
            end else if (rsp_data_var !== (21 + variable_responses)) begin
                $display("FAIL: variable response data mismatch got=%h expected=%h", rsp_data_var, 21 + variable_responses);
                errors = errors + 1;
            end
            rsp_ready_var = 1'b1;
            tick;
            variable_responses = variable_responses + 1;
        end

        if (errors == 0) begin
            $display("TEST_PASS: ddr_behavior_model");
        end else begin
            $display("TEST_FAIL: ddr_behavior_model errors=%0d", errors);
        end
        $finish;
    end
endmodule
