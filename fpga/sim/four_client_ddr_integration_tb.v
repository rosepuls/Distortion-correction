`timescale 1ns / 1ps

module four_client_ddr_integration_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg capture_begin = 0, capture_publish = 0, display_take = 0;
    wire capture_begin_ready, capture_active, display_take_ready;
    wire display_active;
    wire [1:0] display_slot, copy_input_slot, copy_output_slot;
    wire [31:0] display_sequence, copy_input_sequence, copied_count;
    wire copy_start, copy_start_ready, copy_done, copy_error;
    wire copy_active, copy_engine_active, copy_fatal_fault;
    reg display_pending = 0, capture_awvalid = 0;
    wire display_arready, display_rvalid, display_rlast;
    wire [255:0] display_rdata;
    wire capture_awready, capture_wready, capture_wlast;
    wire copy_rvalid, copy_rlast, copy_arready;
    wire [255:0] copy_rdata;
    wire copy_arvalid, copy_arreserve;
    wire [27:0] copy_araddr, copy_awaddr;
    wire [3:0] copy_arlen, copy_awlen;
    wire copy_awvalid, copy_awready, copy_wvalid, copy_wready, copy_wlast;
    wire [255:0] copy_wdata;
    wire [31:0] copy_wstrb;
    wire copy_source_busy;
    wire [27:0] ddr_araddr, ddr_awaddr;
    wire [3:0] ddr_arid, ddr_arlen, ddr_awid, ddr_awlen;
    wire ddr_arvalid, ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata;
    wire [31:0] ddr_wstrb;
    wire ddr_wlast;
    wire [3:0] ddr_wusero_id;
    reg [255:0] ddr_rdata = 0;
    reg ddr_rvalid = 0, ddr_rlast = 0;
    reg [3:0] ddr_rid = 0;
    wire ddr_arready;
    wire [15:0] read_errors, write_errors, drain_errors;
    wire write_fault, drain_fault;
    wire [15:0] copy_outstanding;
    wire copy_physical_drained;
    integer display_rx = 0, copy_rx = 0, copy_tx = 0, capture_tx = 0;
    integer display_ar = 0, copy_ar = 0, copy_aw = 0, capture_aw = 0;
    reg read_active = 0, write_active = 0;
    reg [3:0] read_owner = 0, write_owner = 0;
    reg [27:0] read_base = 0;
    reg [4:0] rbeat = 0, wbeat = 0;
    reg [3:0] write_len = 0;

    function [255:0] make_beat(input integer beat_index);
        integer lane;
        begin
            for (lane = 0; lane < 8; lane = lane + 1)
                make_beat[lane*32 +: 32] = 32'h3c000000 ^ (beat_index*8 + lane);
        end
    endfunction

    frame_pipeline_ownership ownership (
        .clk(clk), .rstn(rstn),
        .capture_begin(capture_begin), .capture_begin_ready(capture_begin_ready),
        .capture_begin_slot(), .capture_active(capture_active), .capture_slot(),
        .capture_publish(capture_publish), .capture_abort(1'b0),
        .display_take(display_take), .display_take_ready(display_take_ready),
        .display_active(display_active), .display_slot(display_slot),
        .display_sequence(display_sequence), .display_release(1'b0),
        .copy_start(copy_start), .copy_start_ready(copy_start_ready),
        .copy_input_slot(copy_input_slot), .copy_output_slot(copy_output_slot),
        .copy_input_sequence(copy_input_sequence), .copy_done(copy_done),
        .copy_error(copy_error), .copy_active(copy_active),
        .copied_count(copied_count), .copy_error_count(),
        .capture_dropped_ready_count(), .output_dropped_ready_count()
    );
    frame_copy_engine #(.BURSTS_PER_FRAME(2), .STALL_LIMIT(200)) engine (
        .clk(clk), .rstn(rstn), .start(copy_start), .start_ready(copy_start_ready),
        .input_slot(copy_input_slot), .output_slot(copy_output_slot),
        .input_sequence(copy_input_sequence), .copy_done(copy_done),
        .copy_error(copy_error), .active(copy_engine_active),
        .fatal_fault(copy_fatal_fault), .completed_sequence(),
        .read_valid(copy_arvalid), .read_addr(copy_araddr),
        .read_len(copy_arlen), .read_reserve(copy_arreserve),
        .read_ready(copy_arready), .read_rvalid(copy_rvalid),
        .read_rdata(copy_rdata), .read_rlast(copy_rlast),
        .write_awvalid(copy_awvalid), .write_awaddr(copy_awaddr),
        .write_awlen(copy_awlen), .write_awready(copy_awready),
        .write_wvalid(copy_wvalid), .write_wdata(copy_wdata),
        .write_wstrb(copy_wstrb), .write_wready(copy_wready),
        .write_wlast(copy_wlast), .write_source_busy(copy_source_busy),
        .copy_write_idle(copy_physical_drained),
        .read_fault(read_errors != 0),
        .write_fault(write_fault || drain_fault)
    );
    ddr_read_burst_arbiter read_arbiter (
        .clk(clk), .rstn(rstn),
        .c0_valid(display_pending), .c0_addr(28'h00c00000),
        .c0_len(4'd15), .c0_reserve(1'b1), .c0_ready(display_arready),
        .c0_rvalid(display_rvalid), .c0_rdata(display_rdata),
        .c0_rlast(display_rlast),
        .c1_valid(copy_arvalid), .c1_addr(copy_araddr),
        .c1_len(copy_arlen), .c1_reserve(copy_arreserve),
        .c1_ready(copy_arready), .c1_rvalid(copy_rvalid),
        .c1_rdata(copy_rdata), .c1_rlast(copy_rlast),
        .axi_araddr(ddr_araddr), .axi_arid(ddr_arid),
        .axi_arlen(ddr_arlen), .axi_arvalid(ddr_arvalid),
        .axi_arready(ddr_arready), .axi_rdata(ddr_rdata),
        .axi_rvalid(ddr_rvalid), .axi_rlast(ddr_rlast),
        .axi_rid(ddr_rid), .busy(), .response_error_count(read_errors)
    );
    ddr_write_burst_arbiter write_arbiter (
        .clk(clk), .rstn(rstn),
        .c0_awvalid(capture_awvalid), .c0_awaddr(28'h00002000),
        .c0_awlen(4'd0), .c0_awready(capture_awready),
        .c0_wvalid(capture_wready), .c0_wdata({8{32'hcafef00d}}),
        .c0_wstrb(32'hffffffff), .c0_wready(capture_wready),
        .c0_wlast(capture_wlast),
        .c1_awvalid(copy_awvalid), .c1_awaddr(copy_awaddr),
        .c1_awlen(copy_awlen), .c1_awready(copy_awready),
        .c1_wvalid(copy_wvalid), .c1_wdata(copy_wdata),
        .c1_wstrb(copy_wstrb), .c1_wready(copy_wready),
        .c1_wlast(copy_wlast),
        .axi_awaddr(ddr_awaddr), .axi_awid(ddr_awid),
        .axi_awlen(ddr_awlen), .axi_awvalid(ddr_awvalid),
        .axi_awready(ddr_awready), .axi_wdata(ddr_wdata),
        .axi_wstrb(ddr_wstrb), .axi_wvalid(ddr_wvalid),
        .axi_wready(ddr_wready), .axi_wlast(ddr_wlast),
        .axi_wusero_id(ddr_wusero_id), .busy(),
        .protocol_error_count(write_errors), .protocol_fault(write_fault)
    );
    ddr_write_drain_tracker drain (
        .clk(clk), .rstn(rstn),
        .awvalid(ddr_awvalid), .awready(ddr_awready), .awid(ddr_awid),
        .wready(ddr_wready), .wusero_last(ddr_wlast),
        .wusero_id(ddr_wusero_id),
        .capture_source_busy(capture_awvalid),
        .copy_source_busy(copy_source_busy),
        .capture_write_idle(), .copy_write_idle(),
        .capture_outstanding(), .copy_outstanding(copy_outstanding),
        .protocol_error_count(drain_errors), .protocol_fault(drain_fault)
    );
    assign copy_physical_drained = !copy_source_busy &&
        copy_outstanding == 0 && !(ddr_awvalid && ddr_awid == 1) &&
        !(ddr_wready && ddr_wlast && ddr_wusero_id == 1);
    assign ddr_arready = !read_active;
    assign ddr_awready = !write_active;
    assign ddr_wready = write_active;
    assign ddr_wlast = write_active && (wbeat == write_len);
    assign ddr_wusero_id = write_owner;

    always @(posedge clk) begin
        if (!rstn) begin
            read_active <= 0; write_active <= 0;
            ddr_rvalid <= 0; ddr_rlast <= 0;
            rbeat <= 0; wbeat <= 0;
        end else begin
            ddr_rvalid <= 0;
            ddr_rlast <= 0;
            if (display_arready) display_pending <= 0;
            if (capture_awready) capture_awvalid <= 0;
            if (ddr_arvalid && ddr_arready) begin
                read_active <= 1;
                read_owner <= ddr_arid;
                read_base <= ddr_araddr;
                rbeat <= 0;
                if (ddr_arid == 0) display_ar <= display_ar + 1;
                else begin
                    if (ddr_araddr !== (copy_ar * 128)) begin
                        $display("FAIL: copy read address"); $fatal(1);
                    end
                    copy_ar <= copy_ar + 1;
                end
            end
            if (read_active) begin
                ddr_rvalid <= 1;
                ddr_rlast <= (rbeat == 15);
                ddr_rid <= read_owner;
                ddr_rdata <= (read_owner == 1) ?
                    make_beat((read_base & 28'h003fffff)/8 + rbeat) :
                    {8{32'h0badc0de}};
                if (rbeat == 15) read_active <= 0;
                else rbeat <= rbeat + 1'b1;
            end
            if (display_rvalid) begin
                if (display_rdata[31:0] !== 32'h0badc0de ||
                    display_rlast !== (display_rx == 15)) begin
                    $display("FAIL: display return route"); $fatal(1);
                end
                display_rx <= display_rx + 1;
            end
            if (copy_rvalid) copy_rx <= copy_rx + 1;
            if (ddr_awvalid && ddr_awready) begin
                write_active <= 1;
                write_owner <= ddr_awid;
                write_len <= ddr_awlen;
                wbeat <= 0;
                if (ddr_awid == 0) capture_aw <= capture_aw + 1;
                else begin
                    if (ddr_awaddr !== (28'h00c00000 + copy_aw*128)) begin
                        $display("FAIL: copy write address"); $fatal(1);
                    end
                    copy_aw <= copy_aw + 1;
                end
            end
            if (ddr_wready) begin
                if (!ddr_wvalid || ddr_wstrb !== 32'hffffffff) begin
                    $display("FAIL: write data valid or strobe"); $fatal(1);
                end
                if (write_owner == 0) begin
                    if (ddr_wdata[31:0] !== 32'hcafef00d || copy_wready) begin
                        $display("FAIL: capture write owner"); $fatal(1);
                    end
                    capture_tx <= capture_tx + 1;
                end else begin
                    if (ddr_wdata !== make_beat(copy_tx) || capture_wready) begin
                        $display("FAIL: copy write owner/data at %0d", copy_tx); $fatal(1);
                    end
                    copy_tx <= copy_tx + 1;
                end
                if (wbeat == write_len) write_active <= 0;
                else wbeat <= wbeat + 1'b1;
            end
            if (copy_done && !copy_physical_drained) begin
                $display("FAIL: output published before ID-1 drain"); $fatal(1);
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rstn = 1;
        if (!capture_begin_ready) begin
            $display("FAIL: no input slot available"); $fatal(1);
        end
        capture_begin = 1;
        @(posedge clk); #1; capture_begin = 0;
        @(negedge clk); capture_publish = 1;
        @(posedge clk); #1; capture_publish = 0;
        wait (copy_start);
        @(negedge clk);
        display_pending = 1;
        capture_awvalid = 1;
        wait (copied_count == 1);
        if (copy_error || copy_fatal_fault || read_errors || write_errors ||
            drain_errors || drain_fault || display_ar != 1 ||
            display_rx != 16 || copy_ar != 2 || copy_rx != 32 ||
            capture_aw != 1 || capture_tx != 1 || copy_aw != 2 ||
            copy_tx != 32) begin
            $display("FAIL: integrated counts D=%0d/%0d C=%0d/%0d W=%0d/%0d",
                     display_ar,display_rx,copy_ar,copy_rx,copy_aw,copy_tx);
            $fatal(1);
        end
        if (!display_take_ready) begin
            $display("FAIL: copied output is not READY"); $fatal(1);
        end
        @(negedge clk); display_take = 1;
        @(posedge clk); #1; display_take = 0;
        if (!display_active || display_slot != 0 || display_sequence != 1) begin
            $display("FAIL: output pool handoff"); $fatal(1);
        end
        $display("PASS: four-client DDR arbitration, raw copy, drain, and output handoff");
        $finish;
    end
    initial begin
        repeat (5000) @(posedge clk);
        $display("FAIL: four-client integration timeout"); $fatal(1);
    end
endmodule
