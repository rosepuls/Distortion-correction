`timescale 1ns / 1ps

module display_read_adapter_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg frame_reset = 1'b0;
    reg line_valid = 1'b0;
    reg [27:0] line_addr = 28'd0;
    reg [9:0] line_beats = 10'd0;
    reg [9:0] consumed_gray = 10'd0;
    wire client_valid, client_reserve, client_ready;
    wire [27:0] client_addr;
    wire [3:0] client_len;
    wire client_rvalid, client_rlast;
    wire [255:0] client_rdata;
    wire line_ready, line_done, line_error, frame_blocked, busy;
    wire sink_rvalid;
    wire [255:0] sink_rdata;
    wire [9:0] received_beats;
    wire [15:0] protocol_error_count;
    wire [27:0] axi_araddr;
    wire [3:0] axi_arid;
    wire [3:0] axi_arlen;
    wire axi_arvalid;
    reg axi_arready = 1'b0;
    reg [255:0] axi_rdata = 256'd0;
    reg axi_rvalid = 1'b0;
    reg axi_rlast = 1'b0;
    wire arb_busy;
    wire [15:0] arb_errors;

    display_read_adapter dut (
        .clk(clk), .rstn(rstn), .frame_reset(frame_reset),
        .line_valid(line_valid), .line_addr(line_addr),
        .line_beats(line_beats), .line_ready(line_ready),
        .consumed_gray(consumed_gray),
        .client_valid(client_valid), .client_addr(client_addr),
        .client_len(client_len), .client_reserve(client_reserve),
        .client_ready(client_ready), .client_rvalid(client_rvalid),
        .client_rdata(client_rdata), .client_rlast(client_rlast),
        .sink_rvalid(sink_rvalid), .sink_rdata(sink_rdata), .sink_write_gray(),
        .line_done(line_done), .line_error(line_error),
        .frame_blocked(frame_blocked), .busy(busy),
        .received_beats(received_beats),
        .protocol_error_count(protocol_error_count)
    );

    ddr_read_burst_arbiter arb (
        .clk(clk), .rstn(rstn),
        .c0_valid(client_valid), .c0_addr(client_addr), .c0_len(client_len),
        .c0_reserve(client_reserve), .c0_ready(client_ready),
        .c0_rvalid(client_rvalid), .c0_rdata(client_rdata), .c0_rlast(client_rlast),
        .c1_valid(1'b0), .c1_addr(28'd0), .c1_len(4'd15), .c1_reserve(1'b0),
        .c1_ready(), .c1_rvalid(), .c1_rdata(), .c1_rlast(),
        .axi_araddr(axi_araddr), .axi_arid(axi_arid), .axi_arlen(axi_arlen),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast),
        .axi_rid(4'd0),
        .busy(arb_busy), .response_error_count(arb_errors)
    );

    integer request_count = 0;
    integer rx_count = 0;
    integer sink_count = 0;
    integer cycles = 0;
    reg response_active = 1'b0;
    reg [4:0] response_index = 0;
    reg [27:0] expected_addr = 28'h0012340;
    reg [9:0] consumed_binary;

    function [9:0] to_gray(input [9:0] value);
        to_gray = (value >> 1) ^ value;
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            axi_arready <= 1'b0;
            axi_rvalid <= 1'b0;
            axi_rlast <= 1'b0;
            response_active <= 1'b0;
            response_index <= 0;
        end else begin
            axi_arready <= axi_arvalid && !response_active;
            if (axi_arvalid && axi_arready) begin
                if (axi_araddr !== expected_addr || axi_arlen !== 4'd15) begin
                    $display("FAIL: unexpected burst addr=%h len=%0d expected=%h/15",
                             axi_araddr, axi_arlen, expected_addr);
                    $fatal(1);
                end
                expected_addr <= expected_addr + 28'd128;
                request_count <= request_count + 1;
                response_active <= 1'b1;
                response_index <= 0;
            end
            if (response_active) begin
                axi_rvalid <= 1'b1;
                axi_rdata <= {8{32'hA5000000 | rx_count[23:0]}};
                axi_rlast <= (response_index == 15);
                rx_count <= rx_count + 1;
                if (response_index == 15) begin
                    response_active <= 1'b0;
                    response_index <= 0;
                end else response_index <= response_index + 1'b1;
            end else begin
                axi_rvalid <= 1'b0;
                axi_rlast <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rstn && sink_rvalid) begin
            if (sink_rdata[31:0] !== (32'hA5000000 | sink_count)) begin
                $display("FAIL: sink data order at beat %0d", sink_count);
                $fatal(1);
            end
            sink_count <= sink_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rstn <= 1'b1;
        repeat (3) @(posedge clk);
        if (!line_ready) begin $display("FAIL: adapter not ready after reset"); $fatal(1); end
        line_addr <= 28'h0012340;
        line_beats <= 10'd528;
        line_valid <= 1'b1;
        @(posedge clk); line_valid <= 1'b0;

        // With no pixel consumption, 32 bursts fill all 512 entries. The
        // next burst must stay blocked until the synchronized read pointer
        // returns at least 16 entries of credit.
        wait (request_count == 32);
        repeat (30) @(posedge clk);
        if (request_count != 32) begin $display("FAIL: exceeded reserved FIFO capacity"); $fatal(1); end
        consumed_gray <= to_gray(10'd16);
        wait (request_count == 33);
        wait (line_done);
        @(posedge clk);
        if (received_beats != 10'd528) begin
            $display("FAIL: received beat count=%0d", received_beats); $fatal(1);
        end
        if (protocol_error_count != 0 || arb_errors != 0) begin
            $display("FAIL: adapter/arbiter error count %0d/%0d", protocol_error_count, arb_errors); $fatal(1);
        end
        if (sink_count != 528) begin
            $display("FAIL: sink beat count=%0d", sink_count); $fatal(1);
        end
        frame_reset <= 1'b1;
        @(posedge clk); frame_reset <= 1'b0;
        repeat (2) @(posedge clk);
        if (!line_ready || frame_blocked || line_error) begin
            $display("FAIL: clean frame reset did not restore line admission"); $fatal(1);
        end
        line_addr <= expected_addr;
        line_beats <= 10'd16;
        line_valid <= 1'b1;
        @(posedge clk); line_valid <= 1'b0;
        wait (line_done);
        @(posedge clk);
        if (request_count != 34 || received_beats != 10'd16 || sink_count != 544)
            begin $display("FAIL: first line after frame reset"); $fatal(1); end
        // Pixel consumption may outrun returned DDR data after the last AR.
        // This must be detected even when no new line request is pending.
        consumed_gray <= to_gray(10'd33);
        repeat (5) @(posedge clk);
        if (protocol_error_count != 16'd1 || !frame_blocked || line_ready) begin
            $display("FAIL: underrun not latched count=%0d blocked=%b ready=%b",
                     protocol_error_count, frame_blocked, line_ready);
            $fatal(1);
        end
        // A recoverable underrun is frame-local. The cumulative counter must
        // remain available for diagnosis without preventing the next frame.
        frame_reset <= 1'b1;
        @(posedge clk); frame_reset <= 1'b0;
        repeat (3) @(posedge clk);
        if (!line_ready || frame_blocked || protocol_error_count != 16'd1) begin
            $display("FAIL: adapter did not recover after underrun at VS");
            $fatal(1);
        end
        $display("PASS: display_read_adapter credit, burst split, line completion, underrun, and frame recovery test");
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $display("FAIL: timeout requests=%0d rx=%0d busy=%b", request_count, rx_count, busy);
        $fatal(1);
    end
endmodule
