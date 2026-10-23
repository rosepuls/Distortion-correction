`timescale 1ns / 1ps

module stage6_radial_pipeline_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0, source_frame_start = 0;
    reg s_valid = 0;
    wire s_ready, m_valid;
    reg [10:0] s_u = 0;
    reg [9:0] s_v = 0;
    reg [19:0] s_pixel_id = 0;
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
    integer beat = 0, delay_count = 0, outputs_seen = 0, coords_seen = 0;
    integer cycle_count = 0;
    integer dx, dy, r2, t, gain, tangent_x, tangent_y;
    integer expected_sx, expected_sy;

    stage5_identity_pipeline #(
        .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720),
        .RADIAL_MAPPING(1), .RADIAL_DENOM_SHIFT(21)
    ) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start), .source_frame_slot(2'd0),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'h12345678), .s_param_version(16'h002a),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(1'b1), .m_pixel(m_pixel),
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

    function automatic [31:0] pixel_value(input integer x, y);
        pixel_value = {8'h40, x[7:0], y[7:0], 8'h00};
    endfunction
    function automatic [255:0] beat_data(input integer address, beat_no);
        integer lane, word_index;
        reg [255:0] result;
        begin
            result = 0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                word_index = (address & 28'h3fffff) + beat_no*8 + lane;
                result[lane*32 +: 32] = pixel_value(
                    word_index % 1280, word_index / 1280);
            end
            beat_data = result;
        end
    endfunction

    always @(negedge clk) begin
        if (!rstn) begin
            pending = 0;
            read_rvalid = 0;
            read_rlast = 0;
        end else if (!pending && read_valid) begin
            if (!read_reserve || read_len !== 4'd3)
                $fatal(1, "FAIL: malformed DDR tile-row request");
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
            read_rdata = beat_data(pending_addr, beat);
            read_rlast = beat == 3;
            beat = beat + 1;
            if (beat == 4) pending = 0;
        end else begin
            read_rvalid = 0;
            read_rlast = 0;
        end
    end

    always @(posedge clk) if (rstn) begin
        cycle_count = cycle_count + 1;
        if (dut.coord_valid && dut.coord_ready) begin
            case (coords_seen)
                0: begin dx = 0; dy = 0; end
                1: begin dx = 360; dy = 140; end
                2: begin dx = -640; dy = -360; end
                3: begin dx = 639; dy = 359; end
                default: $fatal(1, "FAIL: extra coordinate");
            endcase
            r2 = dx*dx + dy*dy;
            t = r2 >> 6;
            gain = -(t << 2) + ((t*t) >> 12);
            tangent_x = (2*dx*dy - r2 - 2*dx*dx) << 2;
            tangent_y = (r2 + 2*dy*dy - 2*dx*dy) << 2;
            expected_sx = ((dx + 640) << 16) + dx*gain + tangent_x;
            expected_sy = ((dy + 360) << 16) + dy*gain + tangent_y;
            if (dut.sx !== expected_sx || dut.sy !== expected_sy ||
                dut.coord_pixel_id !== coords_seen)
                $fatal(1, "FAIL: radial coordinate %0d sx=%h expected=%h",
                    coords_seen, dut.sx, expected_sx);
            coords_seen = coords_seen + 1;
        end
        if (m_valid) begin
            if (m_pixel_id !== outputs_seen ||
                m_frame_id !== 32'h12345678 ||
                m_param_version !== 16'h002a || !m_geometry_valid ||
                m_sof !== (outputs_seen == 0) ||
                m_eol !== (outputs_seen == 3) ||
                m_eof !== (outputs_seen == 3))
                $fatal(1, "FAIL: radial output metadata %0d", outputs_seen);
            case (outputs_seen)
                0: if (m_pixel !== pixel_value(640,360))
                    $fatal(1, "FAIL: optical center changed %h", m_pixel);
                1: if (m_pixel === pixel_value(1000,500) || m_pixel === 0)
                    $fatal(1, "FAIL: interior was not resampled %h", m_pixel);
                2,3: if (m_pixel === 32'd0)
                    $fatal(1, "FAIL: strong barrel correction did not fill corner %h", m_pixel);
                default: $fatal(1, "FAIL: extra output");
            endcase
            outputs_seen = outputs_seen + 1;
        end
    end

    task automatic send(input [10:0] u, input [9:0] v, input [19:0] id);
        begin
            @(negedge clk);
            s_valid = 1;
            s_u = u; s_v = v; s_pixel_id = id;
            s_sof = id == 0; s_eol = id == 3; s_eof = id == 3;
            do @(posedge clk); while (!s_ready);
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        @(negedge clk);
        source_frame_start = 1;
        @(negedge clk);
        source_frame_start = 0;
        send(640,360,0);
        send(1000,500,1);
        send(0,0,2);
        send(1279,719,3);
        wait (outputs_seen == 4);
        repeat (4) @(negedge clk);
        if (coords_seen != 4 || reader_fault || read_error_count != 0 ||
            fetched_rows == 0 || fifo_level != 0 || !reader_idle)
            $fatal(1, "FAIL: radial reader did not drain cleanly");
        $display("PASS: Stage 6 Brown mapping sampled DDR pixels and preserved metadata");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "FAIL: radial pipeline simulation timed out");
    end
endmodule


