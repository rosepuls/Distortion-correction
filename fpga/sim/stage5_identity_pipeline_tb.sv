`timescale 1ns / 1ps

module stage5_identity_pipeline_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0, source_frame_start = 0;
    reg [1:0] source_frame_slot = 0;
    reg s_valid = 0, m_ready = 0;
    wire s_ready, m_valid;
    reg [10:0] s_u = 0;
    reg [9:0] s_v = 0;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire [31:0] m_pixel, m_frame_id;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    wire [19:0] m_pixel_id;
    wire [15:0] m_param_version;
    wire read_valid, read_reserve, reader_idle, reader_fault;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire [15:0] read_error_count;
    wire [31:0] fetched_rows;
    wire [4:0] fifo_level;
    reg pending = 0;
    reg [27:0] pending_addr = 0;
    integer beat = 0, delay_count = 0;
    integer cycle_count = 0;
    integer outputs_seen = 0;
    integer frame_index, pixel_index, expected_index, expected_slot, expected_x, expected_y;

    stage5_identity_pipeline #(
        .IMAGE_WIDTH(64), .IMAGE_HEIGHT(8),
        .CACHE_SET_COUNT(2), .CACHE_WAYS(2)
    ) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_param_version(16'h002a),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(1'b1), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .reader_idle(reader_idle), .reader_fault(reader_fault),
        .read_error_count(read_error_count),
        .fetched_rows(fetched_rows), .fifo_level(fifo_level)
    );

    function automatic [31:0] pixel_value(input integer slot, x, y);
        reg [7:0] r,g,b;
        begin
            r = 8'h40 + slot;
            g = x;
            b = y;
            pixel_value = {r,g,b,8'h00};
        end
    endfunction
    function automatic [255:0] beat_data(input integer address, beat_no);
        integer lane, word_index, slot;
        reg [255:0] result;
        begin
            result = 0;
            slot = address >> 22;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                word_index = (address & 28'h3fffff) + beat_no*8 + lane;
                result[lane*32 +: 32] = pixel_value(slot,
                    word_index % 64, word_index / 64);
            end
            beat_data = result;
        end
    endfunction

    // Delayed but unstoppable four-beat DDR responses; output stalls are
    // independent of the DDR return schedule.
    always @(negedge clk) begin
        if (!rstn) begin
            pending = 0;
            read_rvalid = 0;
            read_rlast = 0;
            m_ready = 0;
        end else begin
            cycle_count = cycle_count + 1;
            m_ready = (cycle_count % 11 != 0);
            if (!pending && read_valid) begin
                if (!read_reserve || read_len !== 4'd3)
                    $fatal(1, "FAIL: source burst was not fully reserved");
                pending = 1;
                pending_addr = read_addr;
                beat = 0;
                delay_count = 2;
                read_rvalid = 0;
            end else if (pending && delay_count != 0) begin
                delay_count = delay_count - 1;
                read_rvalid = 0;
            end else if (pending) begin
                read_rvalid = 1;
                read_rdata = beat_data(pending_addr,beat);
                read_rlast = beat == 3;
                beat = beat + 1;
                if (beat == 4) pending = 0;
            end else begin
                read_rvalid = 0;
                read_rlast = 0;
            end
        end
    end

    always @(posedge clk) if (rstn && m_valid && m_ready) begin
        expected_slot = outputs_seen / 512;
        expected_index = outputs_seen % 512;
        expected_x = expected_index % 64;
        expected_y = expected_index / 64;
        if (m_pixel !== pixel_value(expected_slot,expected_x,expected_y) ||
            m_pixel_id !== expected_index ||
            m_frame_id !== 32'h1000 + expected_slot ||
            m_param_version !== 16'h002a || !m_geometry_valid ||
            m_sof !== (expected_index == 0) ||
            m_eol !== (expected_x == 63) ||
            m_eof !== (expected_index == 511))
            $fatal(1, "FAIL: frame %0d pixel %0d output=%h id=%0d", expected_slot,
                expected_index, m_pixel, m_pixel_id);
        outputs_seen = outputs_seen + 1;
    end

`ifdef TRACE_PIPELINE
    always @(posedge clk) if (rstn && cycle_count < 140) begin
        if (s_valid && s_ready)
            $display("TRACE input id=%0d u=%0d v=%0d t=%0t",s_pixel_id,s_u,s_v,$time);
        if (dut.coord_valid && dut.coord_ready)
            $display("TRACE coord id=%0d t=%0t",dut.coord_pixel_id,$time);
        if (dut.plan_valid && dut.plan_ready)
            $display("TRACE plan id=%0d t=%0t",dut.plan_pixel_id,$time);
        if (dut.reader.accept)
            $display("TRACE cache accept id=%0d count=%0d t=%0t",dut.plan_pixel_id,dut.reader.count,$time);
        if (dut.reader.response)
            $display("TRACE cache resp id=%0d count=%0d t=%0t",dut.reader.m_pixel_id,dut.reader.count,$time);
        if (m_valid && m_ready)
            $display("TRACE output id=%0d count=%0d t=%0t",m_pixel_id,outputs_seen,$time);
    end
`endif

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        for (frame_index = 0; frame_index < 2; frame_index = frame_index + 1) begin
            @(negedge clk);
            if (!reader_idle || fifo_level != 0)
                $fatal(1, "FAIL: prior frame was not drained");
            source_frame_slot = frame_index;
            source_frame_start = 1;
            @(posedge clk);
            @(negedge clk);
            source_frame_start = 0;
            for (pixel_index = 0; pixel_index < 512; pixel_index = pixel_index + 1) begin
                @(negedge clk);
                s_valid = 1;
                s_u = pixel_index % 64;
                s_v = pixel_index / 64;
                s_pixel_id = pixel_index;
                s_frame_id = 32'h1000 + frame_index;
                s_sof = pixel_index == 0;
                s_eol = (pixel_index % 64) == 63;
                s_eof = pixel_index == 511;
                do @(posedge clk); while (!s_ready);
                @(negedge clk);
                s_valid = 0;
            end
            wait (outputs_seen == (frame_index+1)*512);
        end
        repeat (3) @(negedge clk);
        if (reader_fault || read_error_count != 0 || fetched_rows < 16)
            $fatal(1, "FAIL: reader status after two frames");
        $display("PASS: Stage 5 DDR-backed identity restored 1024 ordered pixels across two frames");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "FAIL: Stage 5 full-frame simulation timed out");
    end
endmodule
