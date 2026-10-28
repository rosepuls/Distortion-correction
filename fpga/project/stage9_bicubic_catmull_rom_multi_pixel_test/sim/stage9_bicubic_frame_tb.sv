`timescale 1ns / 1ps

module stage9_bicubic_frame_tb;
`ifdef STAGE9_FULL_HD
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
`else
    localparam integer WIDTH = 64;
    localparam integer HEIGHT = 8;
`endif
    localparam integer PIXELS = WIDTH * HEIGHT;
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
    wire [23:0] diagnostic_miss_count;
    wire [31:0] fetched_rows;
    wire [4:0] fifo_level;
    reg pending = 0;
    wire read_ready = !pending;
    reg [27:0] pending_addr = 0;
    integer beat = 0, delay_count = 0;
    integer outputs_seen = 0, accepted_inputs = 0;
    integer cycle_count = 0;
    integer u, v, stim_u, stim_v, lane, word_index;
    reg [7:0] value;

    stage5_identity_pipeline #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT),
        .RADIAL_MAPPING(0), .CACHE_SET_COUNT(16), .CACHE_WAYS(4)
    ) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start), .source_frame_slot(2'd0),
        .homography_words(288'd0),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'h12345678), .s_param_version(16'h002a),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(1'b1), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(read_ready), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .reader_idle(reader_idle), .reader_fault(reader_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows),
        .diagnostic_miss_count(diagnostic_miss_count),
        .fifo_level(fifo_level)
    );

    function automatic [31:0] pixel_value(input integer x, input integer y);
        reg [7:0] bx, by;
        begin
            bx = x; by = y;
            pixel_value = {8'h40, bx, by, 8'h00};
        end
    endfunction

    always @(negedge clk) begin
        if (!rstn) begin
            pending = 0;
            read_rvalid = 0;
            read_rlast = 0;
        end else if (!pending && read_valid) begin
            if (!read_reserve || read_len !== 4'd3)
                $fatal(1, "Malformed DDR tile-row request");
            pending = 1;
            pending_addr = read_addr;
            beat = 0;
            delay_count = 1;
            read_rvalid = 0;
        end else if (pending && delay_count != 0) begin
            delay_count = delay_count - 1;
            read_rvalid = 0;
        end else if (pending) begin
            read_rvalid = 1;
            read_rlast = beat == 3;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                word_index = (pending_addr & 28'h3fffff) + beat*8 + lane;
                read_rdata[lane*32 +: 32] = pixel_value(
                    word_index % WIDTH, word_index / WIDTH);
            end
            beat = beat + 1;
            if (beat == 4) pending = 0;
        end else begin
            read_rvalid = 0;
            read_rlast = 0;
        end
    end

    always @(posedge clk) if (rstn) begin
        cycle_count = cycle_count + 1;
        if (s_valid && s_ready)
            accepted_inputs = accepted_inputs + 1;
        if (m_valid) begin
            u = m_pixel_id % WIDTH;
            v = m_pixel_id / WIDTH;
            if (m_pixel_id !== outputs_seen ||
                m_frame_id !== 32'h12345678 ||
                m_param_version !== 16'h002a ||
                m_sof !== (outputs_seen == 0) ||
                m_eol !== (u == WIDTH-1) ||
                m_eof !== (outputs_seen == PIXELS-1))
                $fatal(1, "Output metadata mismatch at pixel %0d", outputs_seen);
`ifdef STAGE9_USE_BILINEAR
            if (u <= WIDTH-2 && v <= HEIGHT-2) begin
`else
            if (u >= 1 && u <= WIDTH-3 && v >= 1 && v <= HEIGHT-3) begin
`endif
                if (!m_geometry_valid || m_pixel !== pixel_value(u, v))
                    $fatal(1, "Interior identity pixel %0d mismatch: %h", outputs_seen, m_pixel);
            end else if (m_geometry_valid || m_pixel !== 32'd0)
                $fatal(1, "Strict border pixel %0d was not black", outputs_seen);
            outputs_seen = outputs_seen + 1;
            if ((outputs_seen % (WIDTH * 60)) == 0)
                $display("Stage 9 frame progress: %0d / %0d", outputs_seen, PIXELS);
        end
    end

    task automatic send_pixel(input [10:0] x, input [9:0] y,
                              input [19:0] id);
        begin
            @(negedge clk);
            s_valid = 1; s_u = x; s_v = y; s_pixel_id = id;
            s_sof = id == 0; s_eol = x == WIDTH-1;
            s_eof = id == PIXELS-1;
            do @(posedge clk); while (!s_ready);
            @(negedge clk); s_valid = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        @(negedge clk); source_frame_start = 1;
        @(negedge clk); source_frame_start = 0;
        for (stim_v = 0; stim_v < HEIGHT; stim_v = stim_v + 1)
            for (stim_u = 0; stim_u < WIDTH; stim_u = stim_u + 1)
                send_pixel(stim_u, stim_v, stim_v*WIDTH+stim_u);
        wait (outputs_seen == PIXELS);
        repeat (5) @(negedge clk);
        if (accepted_inputs != PIXELS || reader_fault || read_error_count != 0 ||
            fetched_rows == 0 || fifo_level != 0 || !reader_idle)
            $fatal(1, "Stage 9 test frame did not drain cleanly");
`ifdef STAGE9_USE_BILINEAR
        $display("PASS: Stage 9 complete %0dx%0d bilinear identity frame and strict borders", WIDTH, HEIGHT);
`else
        $display("PASS: Stage 9 complete %0dx%0d bicubic identity frame and strict borders", WIDTH, HEIGHT);
`endif
        $finish;
    end

    initial begin
`ifdef STAGE9_FULL_HD
        #2000000000;
`else
        #200000000;
`endif
        $fatal(1, "Stage 9 frame simulation timed out");
    end
endmodule
