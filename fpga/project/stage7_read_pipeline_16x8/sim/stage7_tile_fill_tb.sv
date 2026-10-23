`timescale 1ns / 1ps

module stage7_tile_fill_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0;
    reg source_frame_start = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready, m_valid;
    wire [31:0] m_p00, m_p10, m_p01, m_p11;
    wire read_valid, read_reserve, reader_idle, reader_fault;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_rvalid = 1'b0, read_rlast = 1'b0;
    reg [255:0] read_rdata = 256'd0;
    wire [15:0] read_error_count;
    wire [31:0] fetched_rows;
    integer ar_count = 0;
    integer beat;

    cached_neighbor_reader #(.SET_COUNT(16), .WAYS(4)) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start), .source_frame_slot(2'd0),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_x0(11'd0), .s_x1(11'd1), .s_y0(10'd0), .s_y1(10'd1),
        .s_fx(16'd0), .s_fy(16'd0), .s_neighbor_valid(4'hf),
        .s_geometry_valid(1'b1), .s_pixel_id(20'd0),
        .s_frame_id(32'd0), .s_param_version(16'd0),
        .s_sof(1'b1), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(1'b1),
        .m_p00(m_p00), .m_p10(m_p10), .m_p01(m_p01), .m_p11(m_p11),
        .m_fx(), .m_fy(), .m_neighbor_valid(), .m_geometry_valid(),
        .m_pixel_id(), .m_frame_id(), .m_param_version(),
        .m_sof(), .m_eol(), .m_eof(),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(1'b1), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .idle(reader_idle), .fatal_fault(reader_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows),
        .diagnostic_miss_count(), .diagnostic_fill_cycles(),
        .read_response_wait(), .first_beat_wait(), .interbeat_wait()
    );

    always @(posedge clk)
        if (rstn && read_valid) begin
            if (!read_reserve || read_len !== 4'd3 ||
                read_addr !== ar_count * 1280)
                $fatal(1, "Bad row AR %0d addr=%0d", ar_count, read_addr);
            ar_count <= ar_count + 1;
        end

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        source_frame_start = 1'b1;
        @(negedge clk);
        source_frame_start = 1'b0;
        repeat (24) @(negedge clk);
        s_valid = 1'b1;
        while (!s_ready) @(negedge clk);
        @(negedge clk);
        s_valid = 1'b0;
        wait (ar_count == 4);
        for (beat = 0; beat < 16; beat = beat + 1) begin
            @(negedge clk);
            read_rvalid = 1'b1;
            read_rlast = ((beat % 4) == 3);
            read_rdata = {8{32'h12340000 + beat}};
        end
        @(negedge clk);
        read_rvalid = 1'b0;
        read_rlast = 1'b0;
        repeat (100) begin
            if (m_valid) begin
                if (fetched_rows !== 32'd4 || reader_fault || read_error_count)
                    $fatal(1, "Bad completed tile: rows=%0d fault=%b", fetched_rows, reader_fault);
                if (m_p00 !== 32'h12340000 || m_p10 !== 32'h12340000 ||
                    m_p01 !== 32'h12340004 || m_p11 !== 32'h12340004)
                    $fatal(1, "Wrong row data after tile refill");
                $display("PASS: one tile refill produced four rows and lookup response");
                $finish;
            end
            @(negedge clk);
        end
        $fatal(1, "Tile refill deadlocked: rows=%0d cache_state=%0d adapter_state=%0d",
               fetched_rows, dut.cache.fill_state, dut.row_adapter.state);
    end
endmodule
