`timescale 1ns/1ps
module sr_source_dma_tb;
    localparam IMAGE_WIDTH = 128;
    localparam IMAGE_HEIGHT = 2;
    localparam PADDED_WIDTH = IMAGE_WIDTH + 2;
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + 2;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg source_frame_start = 0;
    reg [1:0] source_frame_slot = 2;
    reg [31:0] source_frame_id = 32'h12345678;
    wire s_valid;
    reg s_ready = 0;
    wire [31:0] s_rgbx, s_frame_id;
    wire [20:0] s_pixel_id;
    wire [10:0] s_x;
    wire [9:0] s_y;
    wire s_sof, s_eol, s_eof;
    wire read_valid;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    wire read_reserve;
    reg read_ready = 0, read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire done, fault;
    wire [15:0] error_count;
    sr_source_dma #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)) dut (
        .clk(clk), .rstn(rstn), .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .source_frame_id(source_frame_id),
        .m_valid(s_valid), .m_ready(s_ready), .m_rgbx(s_rgbx),
        .m_pixel_id(s_pixel_id), .m_frame_id(s_frame_id), .m_x(s_x), .m_y(s_y),
        .m_sof(s_sof), .m_eol(s_eol), .m_eof(s_eof),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .source_done(done), .fatal_fault(fault), .read_error_count(error_count)
    );
    integer request_seen = 0, beat = 0, delay_count = 0;
    reg sending = 0;
    integer accepted = 0, cycles = 0, expected_y, expected_x;
    reg [31:0] expected_pixel;
    always @(negedge clk) begin
        cycles = cycles + 1;
        s_ready = (cycles % 5 != 0);
        read_ready = !sending && (cycles % 3 != 0);
        if (read_valid && read_ready) begin
            request_seen = request_seen + 1;
            if (read_len !== 4'd15) $fatal(1, "read_len must be 16 beats");
            if (read_addr !== (28'd2 * 28'd4194304 + (request_seen-1) * IMAGE_WIDTH))
                $fatal(1, "unexpected DDR address %0d request %0d", read_addr, request_seen);
            sending = 1;
            beat = 0;
            delay_count = 2;
        end
        if (sending) begin
            if (delay_count > 0) begin
                delay_count = delay_count - 1;
                read_rvalid = 0;
                read_rlast = 0;
            end else begin
                read_rvalid = 1;
                read_rlast = (beat == 15);
                for (integer lane = 0; lane < 8; lane = lane + 1)
                    read_rdata[lane*32 +: 32] = ((request_seen-1) * 1000) + beat*8 + lane + 1;
                if (beat == 15) sending = 0;
                beat = beat + 1;
            end
        end else begin
            read_rvalid = 0;
            read_rlast = 0;
        end
    end
    always @(posedge clk) begin
        if (rstn && s_valid && s_ready) begin
            expected_y = accepted / PADDED_WIDTH;
            expected_x = accepted % PADDED_WIDTH;
            if (s_x !== expected_x || s_y !== expected_y)
                $fatal(1, "raster coordinate mismatch at %0d: got (%0d,%0d)", accepted, s_x, s_y);
            if (s_frame_id !== source_frame_id) $fatal(1, "frame id mismatch");
            if (s_pixel_id !== accepted) $fatal(1, "pixel id mismatch");
            if (expected_y == 0 || expected_y == PADDED_HEIGHT-1 || expected_x == 0 || expected_x == PADDED_WIDTH-1)
                expected_pixel = 0;
            else expected_pixel = (expected_y-1) * 1000 + expected_x;
            if (s_rgbx !== expected_pixel)
                $fatal(1, "pixel mismatch at (%0d,%0d): got %0d expected %0d", expected_x, expected_y, s_rgbx, expected_pixel);
            if (s_sof !== (accepted == 0) || s_eol !== (expected_x == PADDED_WIDTH-1) || s_eof !== (accepted == PADDED_WIDTH*PADDED_HEIGHT-1))
                $fatal(1, "raster marker mismatch");
            accepted = accepted + 1;
        end
        if (rstn && fault) $fatal(1, "DMA fault, error count %0d", error_count);
    end
    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        @(negedge clk); source_frame_start = 1;
        @(negedge clk); source_frame_start = 0;
        repeat (10000) begin
            @(negedge clk);
            if (done) begin
                if (accepted != PADDED_WIDTH*PADDED_HEIGHT || request_seen != IMAGE_HEIGHT)
                    $fatal(1, "completion count mismatch pixels=%0d reads=%0d", accepted, request_seen);
                $display("PASS: source DMA row fetch, halo raster, addresses, metadata, and backpressure");
                $finish;
            end
        end
        $display("DEBUG state=%0d accepted=%0d requests=%0d read_valid=%b read_rvalid=%b beat=%0d out=%b x=%0d y=%0d", dut.state, accepted, request_seen, read_valid, read_rvalid, dut.beat_index, s_valid, s_x, s_y); $fatal(1, "timeout waiting for frame_done");
    end
endmodule







