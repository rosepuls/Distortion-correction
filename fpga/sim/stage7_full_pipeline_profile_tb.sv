`timescale 1ns / 1ps

// A complete deterministic frame through the production mapper, planner,
// cache, and interpolator. A single-row read model supplies four DDR beats.
module stage7_full_pipeline_profile_tb #(
    parameter integer CACHE_SETS = 16,
    parameter integer CACHE_WAYS = 4,
    parameter integer READ_DELAY = 2,
    parameter integer WRITE_PAUSE = 0
);
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer PIXELS = WIDTH * HEIGHT;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0, source_frame_start = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready, m_valid;
    reg [10:0] s_u = 11'd0;
    reg [9:0] s_v = 10'd0;
    reg [19:0] s_pixel_id = 20'd0;
    integer pause_count = 0;
    wire [19:0] m_pixel_id;
    wire m_ready = pause_count == 0;
    wire read_valid, read_reserve, reader_idle, reader_fault;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    wire [15:0] read_error_count;
    wire [31:0] fetched_rows;
    wire [23:0] diagnostic_miss_count, diagnostic_fill_cycles;
    reg pending = 1'b0;
    reg [1:0] beat = 2'd0;
    reg [7:0] delay_count = 8'd0;
    wire read_rvalid = pending && delay_count == 0;
    wire read_rlast = read_rvalid && beat == 2'd3;
    integer sent = 0, received = 0, cycles = 0;

    stage5_identity_pipeline #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT),
        .CACHE_SET_COUNT(CACHE_SETS), .CACHE_WAYS(CACHE_WAYS),
        .RADIAL_MAPPING(1), .RADIAL_DENOM_SHIFT(21)
    ) dut (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start), .source_frame_slot(2'd0),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'd0), .s_param_version(16'd0),
        .s_sof(s_pixel_id == 0), .s_eol(s_u == WIDTH-1),
        .s_eof(s_pixel_id == PIXELS-1),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(),
        .m_geometry_valid(), .m_pixel_id(m_pixel_id),
        .m_frame_id(), .m_param_version(), .m_sof(), .m_eol(), .m_eof(),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(1'b1), .read_rvalid(read_rvalid),
        .read_rdata(256'd0), .read_rlast(read_rlast),
        .reader_idle(reader_idle), .reader_fault(reader_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows),
        .diagnostic_miss_count(diagnostic_miss_count),
        .diagnostic_fill_cycles(diagnostic_fill_cycles),
        .read_response_wait(), .fifo_level()
    );

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        source_frame_start = 1'b1;
        @(negedge clk);
        source_frame_start = 1'b0;
    end

    always @(negedge clk) begin
        if (rstn && !source_frame_start && pause_count == 0 && sent < PIXELS) begin
            s_valid = 1'b1;
            s_u = sent % WIDTH;
            s_v = sent / WIDTH;
            s_pixel_id = sent;
        end else s_valid = 1'b0;
    end

    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (cycles > 10000000) $fatal(1, "Full pipeline profile timeout");
            if (pause_count != 0) pause_count <= pause_count - 1;
            if (s_valid && s_ready) sent = sent + 1;
            if (m_valid && m_ready) begin
                if (m_pixel_id !== received[19:0])
                    $fatal(1, "Full pipeline pixel order mismatch at %0d", received);
                received = received + 1;
                if (WRITE_PAUSE != 0 && received % 128 == 0 && received < PIXELS)
                    pause_count <= WRITE_PAUSE;
                if (received == PIXELS) begin
                    if (reader_fault || read_error_count != 0 || !reader_idle)
                        $fatal(1, "Full pipeline reader fault or not idle");
                    $display("PASS: Stage 7 full pipeline sets=%0d ways=%0d pixels=%0d misses=%0d fill_cycles=%0d cycles=%0d",
                             CACHE_SETS, CACHE_WAYS, received,
                             diagnostic_miss_count, diagnostic_fill_cycles, cycles);
                    $finish;
                end
            end
            if (read_valid && !pending) begin
                if (!read_reserve || read_len !== 4'd3)
                    $fatal(1, "Malformed tile-row request");
                pending <= 1'b1;
                beat <= 2'd0;
                delay_count <= READ_DELAY;
            end else if (pending && delay_count != 0) begin
                delay_count <= delay_count - 1'b1;
            end else if (read_rvalid) begin
                if (beat == 2'd3) pending <= 1'b0;
                else beat <= beat + 1'b1;
            end
        end
    end
endmodule
