`timescale 1ns / 1ps

module cached_neighbor_reader_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0, source_frame_start = 0;
    reg [1:0] source_frame_slot = 0;
    reg s_valid = 0, m_ready = 0;
    wire s_ready, m_valid;
    reg [10:0] s_x0 = 0, s_x1 = 0;
    reg [9:0] s_y0 = 0, s_y1 = 0;
    reg [3:0] s_neighbor_valid = 4'hf;
    reg [19:0] s_pixel_id = 0;
    wire [31:0] m_p00, m_p10, m_p01, m_p11;
    wire [15:0] m_fx, m_fy, m_param_version;
    wire [3:0] m_neighbor_valid;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire read_valid, read_reserve, idle, fatal_fault;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire [15:0] read_error_count;
    wire [31:0] fetched_rows;
    reg pending = 0;
    reg [27:0] pending_addr = 0;
    integer pending_beat = 0;
    integer pending_delay = 0;
    integer issued_reads = 0;
    integer cycles;

    cached_neighbor_reader #(
        .IMAGE_WIDTH(64), .IMAGE_HEIGHT(8),
        .SET_COUNT(2), .WAYS(2)
    ) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_x0(s_x0), .s_x1(s_x1), .s_y0(s_y0), .s_y1(s_y1),
        .s_fx(16'h1234), .s_fy(16'h5678),
        .s_neighbor_valid(s_neighbor_valid), .s_geometry_valid(1'b1),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'hfedcba98),
        .s_param_version(16'h0037),
        .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_p00(m_p00), .m_p10(m_p10), .m_p01(m_p01), .m_p11(m_p11),
        .m_fx(m_fx), .m_fy(m_fy), .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(1'b1), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .idle(idle), .fatal_fault(fatal_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows)
    );

    function automatic [31:0] pixel_value(input integer slot, x, y);
        reg [7:0] r, g, b;
        begin
            r = 8'h40 + slot;
            g = x;
            b = y;
            pixel_value = {r, g, b, 8'h00};
        end
    endfunction

    function automatic [255:0] beat_data(input integer address, beat);
        integer lane, word_index, slot, x, y;
        reg [255:0] result;
        begin
            result = 0;
            slot = address >> 22;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                word_index = (address & 28'h3fffff) + beat*8 + lane;
                x = word_index % 64;
                y = word_index / 64;
                result[lane*32 +: 32] = pixel_value(slot,x,y);
            end
            beat_data = result;
        end
    endfunction

    // A Pango-like read return: four beats cannot be stalled by the client.
    always @(negedge clk) begin
        if (!rstn) begin
            pending = 0;
            read_rvalid = 0;
            read_rlast = 0;
        end else if (!pending && read_valid) begin
            if (!read_reserve || read_len !== 4'd3 || read_addr[2:0] !== 3'd0)
                $fatal(1, "FAIL: unreserved or unaligned DDR command");
            pending = 1;
            pending_addr = read_addr;
            pending_beat = 0;
            pending_delay = 1;
            issued_reads = issued_reads + 1;
            read_rvalid = 0;
        end else if (pending && pending_delay != 0) begin
            pending_delay = pending_delay - 1;
            read_rvalid = 0;
        end else if (pending) begin
            read_rvalid = 1;
            read_rdata = beat_data(pending_addr,pending_beat);
            read_rlast = (pending_beat == 3);
            pending_beat = pending_beat + 1;
            if (pending_beat == 4) pending = 0;
        end else begin
            read_rvalid = 0;
            read_rlast = 0;
        end
    end

    task automatic start_frame(input [1:0] slot);
        begin
            @(negedge clk);
            if (!idle) $fatal(1, "FAIL: frame switched with data in flight");
            source_frame_slot = slot;
            source_frame_start = 1;
            @(posedge clk);
            @(negedge clk);
            source_frame_start = 0;
        end
    endtask

    task automatic check_neighbors(
        input [10:0] x0, x1,
        input [9:0] y0, y1,
        input [3:0] mask,
        input [19:0] id,
        input integer slot
    );
        begin
            @(negedge clk);
            s_x0 = x0; s_x1 = x1; s_y0 = y0; s_y1 = y1;
            s_neighbor_valid = mask;
            s_pixel_id = id;
            s_valid = 1;
            cycles = 0;
            while (!s_ready && cycles < 2000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!s_ready) $fatal(1, "FAIL: lookup was never accepted");
            @(posedge clk);
            @(negedge clk);
            s_valid = 0;
            cycles = 0;
            while (!m_valid && cycles < 4000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!m_valid) $fatal(1, "FAIL: cache lookup never returned");
            if (m_p00 !== (mask[0] ? pixel_value(slot,x0,y0) : 32'd0) ||
                m_p10 !== (mask[1] ? pixel_value(slot,x1,y0) : 32'd0) ||
                m_p01 !== (mask[2] ? pixel_value(slot,x0,y1) : 32'd0) ||
                m_p11 !== (mask[3] ? pixel_value(slot,x1,y1) : 32'd0))
                $fatal(1, "FAIL: neighbors mismatch at id=%0d: %h %h %h %h", id,
                    m_p00,m_p10,m_p01,m_p11);
            if (m_fx !== 16'h1234 || m_fy !== 16'h5678 ||
                m_neighbor_valid !== mask || !m_geometry_valid ||
                m_pixel_id !== id || m_frame_id !== 32'hfedcba98 ||
                m_param_version !== 16'h0037)
                $fatal(1, "FAIL: metadata mismatch at id=%0d", id);
            repeat (2) @(negedge clk);
            if (!m_valid || m_pixel_id !== id)
                $fatal(1, "FAIL: response did not survive backpressure");
            m_ready = 1;
            @(posedge clk);
            @(negedge clk);
            m_ready = 0;
            if (fatal_fault) $fatal(1, "FAIL: reader fault during valid image data");
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        start_frame(2'd0);
        check_neighbors(0,1,0,1,4'hf,20'd0,0);
        check_neighbors(31,32,3,4,4'hf,20'd1,0);
        check_neighbors(63,63,7,7,4'hf,20'd2,0);
        check_neighbors(0,0,0,1,4'ha,20'd3,0);
        start_frame(2'd1);
        check_neighbors(0,1,0,1,4'hf,20'd4,1);
        if (read_error_count !== 16'd0 || fetched_rows < 32'd5 ||
            issued_reads < 5)
            $fatal(1, "FAIL: DDR/cache accounting");
        $display("PASS: DDR Tile Cache neighbors, border, metadata and frame invalidation");
        $finish;
    end
endmodule
