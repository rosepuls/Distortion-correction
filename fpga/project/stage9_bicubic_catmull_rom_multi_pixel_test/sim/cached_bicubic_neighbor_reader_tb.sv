`timescale 1ns / 1ps

module cached_bicubic_neighbor_reader_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg source_frame_start = 0;
    reg [1:0] source_frame_slot = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [10:0] s_x0 = 30, s_x1 = 31, s_x2 = 32, s_x3 = 33;
    reg [9:0] s_y0 = 2, s_y1 = 3, s_y2 = 4, s_y3 = 5;
    reg [15:0] s_fx = 16'h8000, s_fy = 16'h4000;
    reg [15:0] s_neighbor_valid = 16'hffff;
    reg s_geometry_valid = 1;
    reg [19:0] s_pixel_id = 20'h12345;
    reg [31:0] s_frame_id = 32'h10203040;
    reg [15:0] s_param_version = 16'h0055;
    reg s_sof = 1, s_eol = 0, s_eof = 1;
    wire m_valid;
    reg m_ready = 0;
    wire [511:0] m_samples;
    wire [15:0] m_fx, m_fy, m_neighbor_valid;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;
    wire read_valid;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    wire read_reserve;
    reg read_pending = 0;
    reg [27:0] active_read_addr = 0;
    reg [1:0] read_beat = 0;
    wire read_ready = !read_pending;
    wire read_rvalid = read_pending;
    reg [255:0] read_rdata;
    wire read_rlast = (read_beat == 3);
    wire idle, fatal_fault;
    wire [15:0] read_error_count;
    wire [31:0] fetched_rows;
    wire [23:0] diagnostic_miss_count, diagnostic_fill_cycles;
    wire read_response_wait, first_beat_wait, interbeat_wait;

    integer lane;
    integer word_address;
    integer pixel_x, pixel_y;

    function automatic [31:0] pattern_pixel(input integer x, input integer y);
        reg [7:0] px, py, pb;
        begin
            px = x; py = y; pb = x + y;
            pattern_pixel = {px, py, pb, 8'h00};
        end
    endfunction

    always @* begin
        for (lane = 0; lane < 8; lane = lane + 1) begin
            word_address = active_read_addr + (read_beat * 8) + lane;
            pixel_x = word_address % 64;
            pixel_y = word_address / 64;
            read_rdata[lane*32 +: 32] = pattern_pixel(pixel_x, pixel_y);
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            read_pending <= 0;
            active_read_addr <= 0;
            read_beat <= 0;
        end else if (read_valid && read_ready) begin
            read_pending <= 1;
            active_read_addr <= read_addr;
            read_beat <= 0;
        end else if (read_pending) begin
            if (read_beat == 3) begin
                read_pending <= 0;
                read_beat <= 0;
            end else
                read_beat <= read_beat + 1'b1;
        end
    end

    cached_bicubic_neighbor_reader #(
        .IMAGE_WIDTH(64), .IMAGE_HEIGHT(8), .SET_COUNT(16), .WAYS(4)
    ) dut (
        .clk(clk), .rstn(rstn), .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .s_valid(s_valid),
        .s_ready(s_ready), .s_x0(s_x0), .s_x1(s_x1), .s_x2(s_x2),
        .s_x3(s_x3), .s_y0(s_y0), .s_y1(s_y1), .s_y2(s_y2), .s_y3(s_y3),
        .s_fx(s_fx), .s_fy(s_fy), .s_neighbor_valid(s_neighbor_valid),
        .s_geometry_valid(s_geometry_valid), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_samples(m_samples),
        .m_fx(m_fx), .m_fy(m_fy), .m_neighbor_valid(m_neighbor_valid),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata),
        .read_rlast(read_rlast), .idle(idle), .fatal_fault(fatal_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows),
        .diagnostic_miss_count(diagnostic_miss_count),
        .diagnostic_fill_cycles(diagnostic_fill_cycles),
        .read_response_wait(read_response_wait),
        .first_beat_wait(first_beat_wait), .interbeat_wait(interbeat_wait)
    );

    task automatic send_request_at(
        input geometry, input [19:0] id, input [10:0] x_start,
        input [9:0] y_start
    );
        begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_x0 = x_start; s_x1 = x_start + 1'b1;
            s_x2 = x_start + 2'd2; s_x3 = x_start + 2'd3;
            s_y0 = y_start; s_y1 = y_start + 1'b1;
            s_y2 = y_start + 2'd2; s_y3 = y_start + 2'd3;
            s_geometry_valid = geometry;
            s_neighbor_valid = geometry ? 16'hffff : 16'h0000;
            s_pixel_id = id;
            s_frame_id = 32'h10203040 + id;
            s_valid = 1;
            @(posedge clk); #1;
            @(negedge clk); s_valid = 0;
        end
    endtask

    task automatic send_request(input geometry, input [19:0] id);
        begin
            send_request_at(geometry, id, s_x0, s_y0);
        end
    endtask

    task automatic wait_for_response(input integer limit, output integer cycles);
        begin
            cycles = 0;
            while (!m_valid && cycles < limit) begin
                @(posedge clk); #1;
                cycles = cycles + 1;
            end
            if (!m_valid) $fatal(1, "Timed out waiting for 4x4 cache response");
        end
    endtask

    integer row, col;
    integer x, y;
    integer full_window_cycles, reused_window_cycles;
    integer monitor_cycle = 0;
    integer query_monitor_enable = 0;
    integer monitored_queries = 0;
    integer previous_query_cycle = -1;
    integer max_query_gap = 0;

    always @(posedge clk) begin
        if (!rstn) begin
            monitor_cycle = 0;
            monitored_queries = 0;
            previous_query_cycle = -1;
            max_query_gap = 0;
        end else begin
            monitor_cycle = monitor_cycle + 1;
            if (query_monitor_enable && dut.cache_lookup_valid &&
                dut.cache_lookup_ready) begin
                if (monitored_queries > 0 &&
                    monitor_cycle - previous_query_cycle > max_query_gap)
                    max_query_gap = monitor_cycle - previous_query_cycle;
                monitored_queries = monitored_queries + 1;
                previous_query_cycle = monitor_cycle;
            end
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        @(negedge clk); source_frame_start = 1; source_frame_slot = 0;
        @(negedge clk); source_frame_start = 0;
        repeat (3) @(negedge clk);

        send_request(1, 20'h12345);
        wait_for_response(5000, full_window_cycles);
        if (m_fx !== 16'h8000 || m_fy !== 16'h4000 ||
            m_neighbor_valid !== 16'hffff || !m_geometry_valid ||
            m_pixel_id !== 20'h12345 || m_frame_id !== 32'h10215385 ||
            m_param_version !== 16'h0055 || !m_sof || m_eol || !m_eof)
            $fatal(1, "4x4 reader response metadata mismatch");
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1) begin
                x = 30 + col;
                y = 2 + row;
                if (m_samples[(row*4+col)*32 +: 32] !== pattern_pixel(x, y))
                    $fatal(1, "4x4 sample mismatch at row %0d col %0d", row, col);
            end
        repeat (3) begin
            @(posedge clk); #1;
            if (!m_valid || m_pixel_id !== 20'h12345 ||
                m_samples[31:0] !== pattern_pixel(30, 2))
                $fatal(1, "Reader response changed under output backpressure");
        end
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        if (m_valid) $fatal(1, "Reader did not retire accepted response");

        @(negedge clk); m_ready = 0;
        monitored_queries = 0;
        previous_query_cycle = -1;
        max_query_gap = 0;
        query_monitor_enable = 1;
        send_request_at(1, 20'h12346, 11'd30, 10'd2);
        wait_for_response(100, full_window_cycles);
        query_monitor_enable = 0;
        if (monitored_queries != 4 || max_query_gap != 1)
            $fatal(1, "Warm full-window queries were not pipelined: count=%0d max gap=%0d cycles",
                   monitored_queries, max_query_gap);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(30 + col, 2 + row))
                    $fatal(1, "Full-window baseline sample mismatch");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        send_request_at(1, 20'h12347, 11'd31, 10'd2);
        wait_for_response(100, reused_window_cycles);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(31 + col, 2 + row))
                    $fatal(1, "Horizontally reused window sample mismatch at row %0d col %0d: got %h expected %h",
                           row, col,
                           m_samples[(row*4+col)*32 +: 32],
                           pattern_pixel(31 + col, 2 + row));
        if (reused_window_cycles >= full_window_cycles)
            $fatal(1, "Contiguous horizontal window did not reduce gather latency: full=%0d reuse=%0d",
                   full_window_cycles, reused_window_cycles);
        $display("PASS: horizontal cache-hit gather latency full=%0d cycles, reused=%0d cycles",
                 full_window_cycles, reused_window_cycles);
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        send_request_at(1, 20'h12348, 11'd34, 10'd2);
        wait_for_response(100, full_window_cycles);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(34 + col, 2 + row))
                    $fatal(1, "Non-adjacent fallback sample mismatch");
        if (full_window_cycles <= reused_window_cycles)
            $fatal(1, "Non-adjacent coordinate did not use the full gather path");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        send_request_at(1, 20'h12349, 11'd34, 10'd3);
        wait_for_response(100, full_window_cycles);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(34 + col, 3 + row))
                    $fatal(1, "Changed-row fallback sample mismatch");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        send_request(0, 20'h54321);
        wait_for_response(8, reused_window_cycles);
        if (m_geometry_valid || m_neighbor_valid !== 16'h0000 ||
            m_samples !== 512'd0 || m_pixel_id !== 20'h54321)
            $fatal(1, "Invalid border sample was not returned as black");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        send_request_at(1, 20'h54322, 11'd35, 10'd3);
        wait_for_response(100, full_window_cycles);
        if (full_window_cycles <= reused_window_cycles)
            $fatal(1, "Valid request after black border incorrectly reused the old window");
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(35 + col, 3 + row))
                    $fatal(1, "Post-border window sample mismatch");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;

        // A second adjacent pixel must be accepted while the first is still pending.
        s_fx = 16'h1111; s_fy = 16'h2222; s_param_version = 16'h0055;
        send_request_at(1, 20'h54330, 11'd30, 10'd2);
        if (!s_ready)
            $fatal(1, "Reader did not accept a second in-flight pixel context");
        s_fx = 16'h3333; s_fy = 16'h4444; s_param_version = 16'h0066;
        send_request_at(1, 20'h54331, 11'd31, 10'd2);
        wait_for_response(100, full_window_cycles);
        if (m_pixel_id !== 20'h54330 || m_frame_id !== 32'h10257370 ||
            m_param_version !== 16'h0055 || m_fx !== 16'h1111 || m_fy !== 16'h2222)
            $fatal(1, "First context metadata/order mismatch: id=%h frame=%h version=%h",
                   m_pixel_id, m_frame_id, m_param_version);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(30 + col, 2 + row))
                    $fatal(1, "First in-flight 4x4 window mismatch");
        repeat (2) begin
            @(posedge clk); #1;
            if (!m_valid || m_pixel_id !== 20'h54330)
                $fatal(1, "First context changed under output backpressure");
        end
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;
        wait_for_response(100, reused_window_cycles);
        if (m_pixel_id !== 20'h54331 || m_frame_id !== 32'h10257371 ||
            m_param_version !== 16'h0066 || m_fx !== 16'h3333 || m_fy !== 16'h4444)
            $fatal(1, "Second context metadata/order mismatch: id=%h frame=%h version=%h",
                   m_pixel_id, m_frame_id, m_param_version);
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(31 + col, 2 + row))
                    $fatal(1, "Second in-flight reused 4x4 window mismatch");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); m_ready = 0;
        source_frame_slot = 1;
        source_frame_start = 1;
        @(negedge clk); source_frame_start = 0;
        send_request_at(1, 20'h54323, 11'd36, 10'd3);
        wait_for_response(5000, full_window_cycles);
        if (full_window_cycles <= reused_window_cycles)
            $fatal(1, "First request after source-frame start incorrectly reused the old window");
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (m_samples[(row*4+col)*32 +: 32] !==
                    pattern_pixel(36 + col, 3 + row))
                    $fatal(1, "Post-frame-start window sample mismatch");

        $display("PASS: Stage 9 cached 4x4 neighbor gather across tile boundaries");
        $finish;
    end
endmodule
