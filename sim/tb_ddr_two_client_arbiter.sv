`timescale 1ns/1ps

module tb_ddr_two_client_arbiter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg c0_cmd_valid = 1'b0;
    reg [27:0] c0_cmd_addr = 28'h0010000;
    reg [31:0] c0_cmd_len = 32'd3;
    reg [255:0] c0_data = 256'hC0;
    wire c0_cmd_ready, c0_done, c0_bac, c0_data_re;

    reg c1_cmd_valid = 1'b0;
    reg [27:0] c1_cmd_addr = 28'h0020000;
    reg [31:0] c1_cmd_len = 32'd5;
    reg [255:0] c1_data = 256'hC1;
    wire c1_cmd_ready, c1_done, c1_bac, c1_data_re;

    wire ctrl_cmd_valid;
    wire [27:0] ctrl_cmd_addr;
    wire [31:0] ctrl_cmd_len;
    wire [255:0] ctrl_data;
    reg ctrl_cmd_ready = 1'b0;
    reg ctrl_done = 1'b0;
    reg ctrl_bac = 1'b0;
    reg ctrl_data_re = 1'b0;

    integer errors = 0;

    ddr_two_client_arbiter #(.ADDR_WIDTH(28)) dut (
        .clk(clk), .rst_n(rst_n),
        .c0_cmd_valid(c0_cmd_valid), .c0_cmd_addr(c0_cmd_addr),
        .c0_cmd_len(c0_cmd_len), .c0_data(c0_data),
        .c0_cmd_ready(c0_cmd_ready), .c0_done(c0_done),
        .c0_bac(c0_bac), .c0_data_re(c0_data_re),
        .c1_cmd_valid(c1_cmd_valid), .c1_cmd_addr(c1_cmd_addr),
        .c1_cmd_len(c1_cmd_len), .c1_data(c1_data),
        .c1_cmd_ready(c1_cmd_ready), .c1_done(c1_done),
        .c1_bac(c1_bac), .c1_data_re(c1_data_re),
        .ctrl_cmd_valid(ctrl_cmd_valid), .ctrl_cmd_addr(ctrl_cmd_addr),
        .ctrl_cmd_len(ctrl_cmd_len), .ctrl_cmd_ready(ctrl_cmd_ready),
        .ctrl_done(ctrl_done), .ctrl_bac(ctrl_bac),
        .ctrl_data_re(ctrl_data_re), .ctrl_data(ctrl_data)
    );

    task automatic check_cond(input condition, input [8*96-1:0] message);
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // Both clients wait.  Client 0 has the first rotating grant, but no
        // transaction is owned until the controller actually accepts it.
        c0_cmd_valid <= 1'b1;
        c1_cmd_valid <= 1'b1;
        repeat (2) @(posedge clk);
        check_cond(ctrl_cmd_valid && ctrl_cmd_addr == c0_cmd_addr,
               "client 0 must own the first offered command");
        check_cond(!c0_cmd_ready && !c1_cmd_ready,
               "no client may see ready while controller is stalled");

        ctrl_cmd_ready <= 1'b1;
        #1;
        check_cond(c0_cmd_ready && !c1_cmd_ready,
               "only client 0 may observe command acceptance");
        @(posedge clk);
        c0_cmd_valid <= 1'b0;
        ctrl_cmd_ready <= 1'b0;

        // Return-side handshakes must be locked to client 0 even though
        // client 1 still has a pending request.
        ctrl_bac <= 1'b1;
        ctrl_data_re <= 1'b1;
        @(posedge clk);
        #1;
        check_cond(c0_bac && c0_data_re && !c1_bac && !c1_data_re,
               "write data handshakes crossed client ownership");
        check_cond(ctrl_data == c0_data, "controller data came from wrong client");
        ctrl_bac <= 1'b0;
        ctrl_data_re <= 1'b0;
        ctrl_done <= 1'b1;
        #1;
        check_cond(c0_done && !c1_done, "completion crossed client ownership");
        @(posedge clk);
        ctrl_done <= 1'b0;

        // Round-robin now gives the waiting client 1 the next command.
        ctrl_cmd_ready <= 1'b1;
        #1;
        check_cond(c1_cmd_ready && !c0_cmd_ready,
               "client 1 did not receive the rotating next grant");
        @(posedge clk);
        check_cond(ctrl_cmd_addr == c1_cmd_addr && ctrl_cmd_len == c1_cmd_len,
               "client 1 command fields were not selected");
        c1_cmd_valid <= 1'b0;
        ctrl_cmd_ready <= 1'b0;
        ctrl_done <= 1'b1;
        #1;
        check_cond(c1_done && !c0_done, "client 1 completion was misrouted");
        @(posedge clk);
        ctrl_done <= 1'b0;

        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr_two_client_arbiter errors=%0d", errors);
        $display("TEST_PASS: ddr_two_client_arbiter");
        $finish;
    end
endmodule
