`timescale 1ns / 1ps

// The board has 1280 active pixels and 370 blank pixels per line. The
// existing rd_buf requests the next line at the current line's DE rising
// edge. This DDR model usually completes a 160-beat line in about 16 us,
// below the 22-us line period. One later line has an extra 24-us stall,
// representing temporary contention. The 512-beat buffer can absorb that
// stall only if future lines have been prefetched. Two frames also exercise
// Gray-pointer wraps and frame rebasing at a nonzero count. FRAME_LINES can
// be set to 720 to exercise full frames and every burst address.
module rd_fram_buf (
    input [255:0] wr_data, input [8:0] wr_addr, input wr_en,
    input wr_clk, input wr_rst, input [11:0] rd_addr,
    output [31:0] rd_data, input rd_clk, input rd_rst
);
    assign rd_data = 32'h12345600;
endmodule

module display_read_timing_tb;
    parameter FRAME_LINES = 12;
    reg ddr_clk = 1'b0, pix_clk = 1'b0;
    always #4 ddr_clk = ~ddr_clk;
    always #6.734 pix_clk = ~pix_clk;

    reg rstn = 1'b0, vs = 1'b0, de = 1'b0;
    wire frame_start, frame_complete, line_valid, line_ready, line_done;
    wire [27:0] line_addr;
    wire [31:0] line_len;
    wire [9:0] consumed_gray;
    wire client_valid, client_reserve, client_ready;
    wire [27:0] client_addr;
    wire [3:0] client_len;
    reg client_rvalid = 1'b0, client_rlast = 1'b0;
    reg [255:0] client_rdata = {8{32'h12345600}};
    wire sink_rvalid, line_error, frame_blocked, busy;
    wire [255:0] sink_rdata;
    wire [9:0] received_beats;
    wire [15:0] errors;
    reg [4:0] pending_beats = 5'd0;
    reg [12:0] response_wait = 13'd0;
    reg [3:0] burst_index = 4'd0;
    integer requested_line = 0;
    integer active_lines = 0;
    integer returned_beats = 0;
    integer line_index;

    rd_buf #(.ADDR_WIDTH(28), .ADDR_OFFSET(28'h00c00000),
             .H_NUM(1280), .V_NUM(FRAME_LINES), .DQ_WIDTH(32),
             .LEN_WIDTH(32), .PIX_WIDTH(32), .LINE_ADDR_WIDTH(22)) reader (
        .ddr_clk(ddr_clk), .ddr_rstn(rstn),
        .vout_clk(pix_clk), .rd_fsync(vs), .rd_en(de),
        .vout_de(), .vout_data(), .init_done(1'b1),
        .frame_slot(2'd0), .display_valid(1'b1),
        .frame_start(frame_start), .frame_complete(frame_complete),
        .read_busy_line(), .consumed_gray(consumed_gray),
        .ddr_rreq(line_valid), .ddr_raddr(line_addr),
        .ddr_rd_len(line_len), .ddr_rrdy(line_ready),
        .ddr_rdone(line_done), .ddr_rdata(sink_rdata),
        .ddr_rdata_en(sink_rvalid)
    );

    display_read_adapter adapter (
        .clk(ddr_clk), .rstn(rstn), .frame_reset(frame_start),
        .line_valid(line_valid), .line_addr(line_addr),
        .line_beats(line_len[9:0]), .line_ready(line_ready),
        .consumed_gray(consumed_gray),
        .client_valid(client_valid), .client_addr(client_addr),
        .client_len(client_len), .client_reserve(client_reserve),
        .client_ready(client_ready), .client_rvalid(client_rvalid),
        .client_rdata(client_rdata), .client_rlast(client_rlast),
        .sink_rvalid(sink_rvalid), .sink_rdata(sink_rdata),
        .sink_write_gray(), .line_done(line_done),
        .line_error(line_error), .frame_blocked(frame_blocked),
        .busy(busy), .received_beats(received_beats),
        .protocol_error_count(errors)
    );

    assign client_ready = client_valid && client_reserve &&
                          (pending_beats == 0) && !client_rvalid;
    always @(posedge ddr_clk) begin
        if (rstn && adapter.buffer_fault && !frame_blocked)
            $display("TRACE: credit fault input at %0t actual_consumed=%0d synchronized=%0d produced=%0d occupied=%0d reserved=%0d",
                     $time, reader.consumed_beats, adapter.consumed_binary,
                     adapter.write_count, adapter.occupied, adapter.reserved_left);
    end
    // Stop at the first fault, including when xsim continues after $fatal.
    // These counters distinguish actual DDR shortage from a bad CDC sample.
    always @(negedge ddr_clk) begin
        if (rstn && errors != 0) begin
            $display("FAIL: display credit fault at %0t actual_consumed=%0d synchronized=%0d produced=%0d occupied=%0d reserved=%0d",
                     $time, reader.consumed_beats, adapter.consumed_binary,
                     adapter.write_count, adapter.occupied, adapter.reserved_left);
            $finish;
        end
    end
    always @(posedge ddr_clk) begin
        if (!rstn) begin
            pending_beats <= 0;
            response_wait <= 0;
            burst_index <= 0;
            requested_line <= 0;
            client_rvalid <= 0;
            client_rlast <= 0;
            returned_beats <= 0;
        end else begin
            client_rvalid <= 0;
            client_rlast <= 0;
            if (client_valid && client_ready) begin
                if (client_addr !== (28'h00c00000 +
                     (requested_line % FRAME_LINES) * 1280 + burst_index * 128) ||
                    client_len !== 4'd15) begin
                    $display("FAIL: burst address/order line=%0d burst=%0d addr=%h len=%0d",
                             requested_line, burst_index, client_addr, client_len);
                    $finish;
                end
                pending_beats <= {1'b0, client_len} + 5'd1;
                response_wait <= (burst_index == 0) ?
                    ((requested_line == 8) ? 13'd3750 : 13'd750) : 13'd7;
                burst_index <= (burst_index == 9) ? 0 : burst_index + 1'b1;
                if (burst_index == 9)
                    requested_line <= requested_line + 1'b1;
            end else if (pending_beats != 0) begin
                if (response_wait == 0) begin
                    client_rvalid <= 1;
                    client_rlast <= pending_beats == 1;
                    pending_beats <= pending_beats - 1'b1;
                    response_wait <= 13'd7;
                    returned_beats <= returned_beats + 1;
                end else response_wait <= response_wait - 1'b1;
            end
        end
    end

    task video_line;
        integer pixel;
        begin
            @(negedge pix_clk); de = 1;
            for (pixel = 0; pixel < 1280; pixel = pixel + 1)
                @(negedge pix_clk);
            de = 0;
            for (pixel = 0; pixel < 370; pixel = pixel + 1)
                @(negedge pix_clk);
            active_lines = active_lines + 1;
        end
    endtask

    initial begin
        repeat (8) @(posedge ddr_clk);
        @(negedge pix_clk); rstn = 1;
        repeat (5) @(negedge pix_clk);
        vs = 1;
        repeat (20) @(negedge pix_clk);
        vs = 0;
        #70000;
        if (returned_beats < 160) begin
            $display("FAIL: initial line was not prefetched"); $finish;
        end
        for (line_index = 0; line_index < FRAME_LINES; line_index = line_index + 1)
            video_line();
        repeat (200) @(posedge ddr_clk);
        if (errors != 0 || frame_blocked || !frame_complete ||
            returned_beats != FRAME_LINES*160) begin
            $display("FAIL: display underrun lines=%0d returned=%0d errors=%0d blocked=%b complete=%b",
                     active_lines, returned_beats, errors, frame_blocked, frame_complete);
            $finish;
        end
        @(negedge pix_clk); vs = 1;
        repeat (20) @(negedge pix_clk);
        vs = 0;
        #70000;
        for (line_index = 0; line_index < FRAME_LINES; line_index = line_index + 1)
            video_line();
        repeat (200) @(posedge ddr_clk);
        if (errors != 0 || frame_blocked || !frame_complete ||
            returned_beats != FRAME_LINES*320) begin
            $display("FAIL: display frame rebase lines=%0d returned=%0d errors=%0d blocked=%b complete=%b",
                     active_lines, returned_beats, errors, frame_blocked, frame_complete);
            $finish;
        end
        $display("CHECKED: frames=2 lines_per_frame=%0d returned_beats=%0d burst_addresses=%0d",
                 FRAME_LINES, returned_beats, requested_line*10);
        $display("PASS: two display frames cross Gray pointer wrap and frame rebase without underrun");
        $finish;
    end

    initial begin
        #(FRAME_LINES*50000 + 2000000);
        $display("FAIL: display read timing test timeout lines=%0d returned=%0d",
                 active_lines, returned_beats);
        $finish;
    end
endmodule
