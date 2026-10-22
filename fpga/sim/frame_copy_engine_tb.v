`timescale 1ns / 1ps

module frame_copy_engine_tb;
`ifdef FULL_FRAME
    localparam integer FRAME_BURSTS = 7200;
`else
    localparam integer FRAME_BURSTS = 2;
`endif
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, start = 0;
    wire start_ready, copy_done, copy_error, active, write_source_busy;
    wire fatal_fault;
    wire [31:0] completed_sequence;
    wire read_valid, read_reserve;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_ready = 1;
    reg read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire write_awvalid, write_wvalid;
    wire [27:0] write_awaddr;
    wire [3:0] write_awlen;
    wire [255:0] write_wdata;
    wire [31:0] write_wstrb;
    reg write_awready = 1;
    wire write_wready, write_wlast;
    reg copy_write_idle = 1;
    integer ar_count = 0, aw_count = 0, written = 0;
    integer returned = 0, drain_delay = 0;
    reg returning = 0, writing = 0;
    reg [4:0] r_index = 0, w_index = 0;

    frame_copy_engine #(.BURSTS_PER_FRAME(FRAME_BURSTS), .STALL_LIMIT(100)) dut (
        .clk(clk), .rstn(rstn), .start(start), .start_ready(start_ready),
        .input_slot(2'd2), .output_slot(2'd1), .input_sequence(32'd99),
        .copy_done(copy_done), .copy_error(copy_error), .active(active),
        .fatal_fault(fatal_fault), .completed_sequence(completed_sequence),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata),
        .read_rlast(read_rlast),
        .write_awvalid(write_awvalid), .write_awaddr(write_awaddr),
        .write_awlen(write_awlen), .write_awready(write_awready),
        .write_wvalid(write_wvalid), .write_wdata(write_wdata),
        .write_wstrb(write_wstrb), .write_wready(write_wready),
        .write_wlast(write_wlast), .write_source_busy(write_source_busy),
        .copy_write_idle(copy_write_idle), .read_fault(1'b0),
        .write_fault(1'b0)
    );

    assign write_wready = writing;
    assign write_wlast = writing && (w_index == 15);

    function [255:0] make_beat(input integer beat_index);
        integer lane;
        begin
            for (lane = 0; lane < 8; lane = lane + 1)
                make_beat[lane*32 +: 32] = 32'h5a000000 ^ (beat_index*8 + lane);
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            returning <= 0; writing <= 0;
            read_rvalid <= 0; read_rlast <= 0;
            r_index <= 0; w_index <= 0;
            copy_write_idle <= 1;
            drain_delay <= 0;
        end else begin
            read_rvalid <= 0;
            read_rlast <= 0;
            if (read_valid && read_ready) begin
                if (!read_reserve || read_len != 15 ||
                    read_addr !== (28'h00800000 + ar_count * 128)) begin
                    $display("FAIL: source burst address or reservation"); $fatal(1);
                end
                ar_count <= ar_count + 1;
                returning <= 1;
                r_index <= 0;
            end
            if (returning) begin
                read_rvalid <= 1;
                read_rlast <= (r_index == 15);
                read_rdata <= make_beat(returned);
                returned <= returned + 1;
                if (r_index == 15) returning <= 0;
                else r_index <= r_index + 1'b1;
            end
            if (write_awvalid && write_awready) begin
                if (write_awlen != 15 ||
                    write_awaddr !== (28'h01000000 + aw_count * 128)) begin
                    $display("FAIL: destination burst address"); $fatal(1);
                end
                aw_count <= aw_count + 1;
                writing <= 1;
                w_index <= 0;
                copy_write_idle <= 0;
            end
            if (write_wvalid && write_wready) begin
                if (write_wdata !== make_beat(written) ||
                    write_wstrb !== 32'hffffffff || !write_source_busy) begin
                    $display("FAIL: copied data beat %0d", written); $fatal(1);
                end
                written <= written + 1;
                if (w_index == 15) begin
                    writing <= 0;
                    drain_delay <= 4;
                end else w_index <= w_index + 1'b1;
            end
            if (drain_delay > 0) begin
                drain_delay <= drain_delay - 1;
                if (drain_delay == 1) copy_write_idle <= 1;
            end
            if (copy_done && !copy_write_idle) begin
                $display("FAIL: output published before write drain"); $fatal(1);
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rstn = 1;
        @(negedge clk);
        if (!start_ready) begin $display("FAIL: copy engine not ready"); $fatal(1); end
        start = 1;
        @(posedge clk); #1; start = 0;
        wait (copy_done);
        #1;
        if (copy_error || fatal_fault ||
            ar_count != FRAME_BURSTS || aw_count != FRAME_BURSTS ||
            returned != FRAME_BURSTS*16 || written != FRAME_BURSTS*16 ||
            completed_sequence != 99) begin
            $display("FAIL: copy totals AR=%0d AW=%0d R=%0d W=%0d",
                     ar_count, aw_count, returned, written);
            $fatal(1);
        end
        $display("PASS: frame_copy_engine %0d bursts / %0d words equal and drained",
                 FRAME_BURSTS, FRAME_BURSTS*128);
        $finish;
    end
    initial begin
        repeat (FRAME_BURSTS*80 + 200) @(posedge clk);
        $display("FAIL: frame copy timeout"); $fatal(1);
    end
endmodule
