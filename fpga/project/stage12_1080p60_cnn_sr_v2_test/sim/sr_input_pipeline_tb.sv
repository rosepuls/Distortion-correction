`timescale 1ns/1ps
module sr_input_pipeline_tb;
    localparam IMAGE_WIDTH = 128;
    localparam IMAGE_HEIGHT = 2;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, source_frame_start = 0;
    reg [1:0] source_frame_slot = 2;
    reg [31:0] source_frame_id = 32'h89abcdef;
    wire frame_done, fatal_fault;
    wire [15:0] error_count;
    wire read_valid;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    wire read_reserve;
    reg read_ready = 0, read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [71:0] m_window;
    wire [10:0] m_x;
    wire [9:0] m_y;
    wire [20:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire m_sof, m_eol, m_eof;
    sr_input_pipeline #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)) dut (
        .clk(clk), .rstn(rstn), .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .source_frame_id(source_frame_id),
        .source_done(frame_done), .fatal_fault(fatal_fault), .read_error_count(error_count),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
    integer requests = 0, beat = 0, delay_count = 0, cycle = 0;
    reg sending = 0;
    integer outputs = 0, x, y, dx, dy, tap, expected;
    always @(negedge clk) begin
        cycle = cycle + 1;
        m_ready = (cycle % 7 != 0) && (cycle % 11 != 0);
        read_ready = !sending && (cycle % 3 != 0);
        if (read_valid && read_ready) begin
            requests = requests + 1;
            if (read_len != 15 || read_addr != (28'd2*28'd4194304 + (requests-1)*IMAGE_WIDTH))
                $fatal(1, "bad row read request %0d addr=%0d len=%0d", requests, read_addr, read_len);
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
                for (integer lane = 0; lane < 8; lane = lane + 1) begin
                    integer value;
                    value = 16 + (requests-1)*30 + beat*8 + lane;
                    read_rdata[lane*32 +: 8] = 0;
                    read_rdata[lane*32+8 +: 8] = value;
                    read_rdata[lane*32+16 +: 8] = value;
                    read_rdata[lane*32+24 +: 8] = value;
                end
                if (beat == 15) sending = 0;
                beat = beat + 1;
            end
        end else begin
            read_rvalid = 0;
            read_rlast = 0;
        end
    end
    always @(posedge clk) begin
        if (rstn && fatal_fault) $fatal(1, "source DMA fault %0d", error_count);
        if (rstn && m_valid && m_ready) begin
            x = outputs % IMAGE_WIDTH;
            y = outputs / IMAGE_WIDTH;
            if (m_x != x || m_y != y || m_pixel_id != outputs || m_frame_id != source_frame_id)
                $fatal(1, "window metadata mismatch output=%0d got=(%0d,%0d)", outputs, m_x, m_y);
            if (m_sof != (outputs == 0) || m_eol != (x == IMAGE_WIDTH-1) ||
                m_eof != (outputs == IMAGE_WIDTH*IMAGE_HEIGHT-1))
                $fatal(1, "window raster marker mismatch");
            for (integer row = 0; row < 3; row = row + 1) begin
                for (integer col = 0; col < 3; col = col + 1) begin
                    dx = col - 1;
                    dy = row - 1;
                    if (x+dx < 0 || x+dx >= IMAGE_WIDTH || y+dy < 0 || y+dy >= IMAGE_HEIGHT)
                        expected = 0;
                    else expected = 16 + (y+dy)*30 + x+dx;
                    tap = 8*(8-(row*3+col));
                    if (m_window[tap +: 8] != expected)
                        $fatal(1, "tap mismatch output=(%0d,%0d) tap=(%0d,%0d) got=%0d expected=%0d", x,y,row,col,m_window[tap +: 8],expected);
                end
            end
            outputs = outputs + 1;
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        @(negedge clk); source_frame_start = 1;
        @(negedge clk); source_frame_start = 0;
        repeat (20000) begin
            @(negedge clk);
            if (outputs == IMAGE_WIDTH*IMAGE_HEIGHT) begin
                if (requests != IMAGE_HEIGHT) $fatal(1, "expected two DDR rows, got %0d", requests);
                $display("PASS: integrated DMA, RGBX-to-luma, ready isolation FIFO, and 3x3 windows");
                $finish;
            end
        end
        $fatal(1, "timeout: outputs=%0d requests=%0d", outputs, requests);
    end
endmodule

