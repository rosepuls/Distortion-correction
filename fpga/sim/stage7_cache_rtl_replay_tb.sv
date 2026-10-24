`timescale 1ns / 1ps

// Full-frame miss-event trace from the exact Stage 7 project cache RTL.
// The adapter accepts one tile request and returns four rows (16 beats).
module stage7_cache_rtl_replay_tb;
    localparam integer PIXELS = 1280 * 720;
    localparam integer FRAMES = 5;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0;
    reg invalidate = 1'b0;
    reg lookup_valid = 1'b0;
    reg [11:0] lookup_x0 = 12'd0, lookup_y0 = 12'd0;
    wire lookup_ready, lookup_rsp_valid;
    wire fill_req_valid, fill_req_ready, fill_data_ready;
    wire [11:0] fill_tile_x, fill_tile_y;
    wire [1:0] fill_row_index;
    wire [23:0] diagnostic_miss_count, diagnostic_fill_cycles;
    reg fill_busy = 1'b0;
    reg [1:0] held_row = 2'd0, beat = 2'd0;
    reg accepted = 1'b0;
    integer trace_file, miss_file;
    integer parsed, trace_id, trace_x0, trace_y0, trace_valid;
    integer sent = 0, received = 0, cycles = 0, miss_index = 0;
    integer frame_index = 0;

    assign fill_req_ready = !fill_busy;
    pixel_tile_cache #(
        .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720),
        .SET_COUNT(16), .WAYS(8)
    ) dut (
        .clk(clk), .rst_n(rstn), .invalidate(invalidate),
        .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
        .lookup_x0(lookup_x0), .lookup_y0(lookup_y0),
        .lookup_rsp_valid(lookup_rsp_valid), .lookup_rsp_ready(1'b1),
        .pixel_p00(), .pixel_p10(), .pixel_p01(), .pixel_p11(),
        .cache_hit(), .coord_valid(),
        .fill_req_valid(fill_req_valid), .fill_req_ready(fill_req_ready),
        .fill_tile_x(fill_tile_x), .fill_tile_y(fill_tile_y),
        .fill_row_index(fill_row_index),
        .fill_data_valid(fill_busy), .fill_data_ready(fill_data_ready),
        .fill_data(256'd0), .fill_data_row_index(held_row),
        .fill_data_beat_index(beat),
        .diagnostic_miss_count(diagnostic_miss_count),
        .diagnostic_fill_cycles(diagnostic_fill_cycles)
    );

    initial begin
        trace_file = $fopen("stage7_tile_trace.csv", "r");
        if (trace_file == 0) $fatal(1, "Could not open coordinate trace");
        miss_file = $fopen("stage7_rtl_misses.csv", "w");
        if (miss_file == 0) $fatal(1, "Could not create RTL miss trace");
        $fwrite(miss_file, "frame,tile_x,tile_y,set,victim_way,miss_index\n");
        repeat (4) @(negedge clk);
        rstn = 1'b1;
    end

    always @(negedge clk) begin
        if (rstn && (!lookup_valid || accepted)) begin
            if (sent < PIXELS) begin
                parsed = $fscanf(trace_file, "%d,%d,%d,%d\n",
                                 trace_id, trace_x0, trace_y0, trace_valid);
                if (parsed != 4 || trace_id != sent)
                    $fatal(1, "Bad coordinate trace at %0d", sent);
                lookup_x0 = (trace_x0 >= 1279) ? 1278 : trace_x0;
                lookup_y0 = (trace_y0 >= 719) ? 718 : trace_y0;
                lookup_valid = 1'b1;
            end else lookup_valid = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (cycles > 10000000) $fatal(1, "RTL cache replay timeout");
            if (invalidate) invalidate <= 1'b0;
            accepted <= lookup_valid && lookup_ready;
            if (lookup_valid && lookup_ready) sent = sent + 1;
            if (dut.start_miss) begin
                $fwrite(miss_file, "%0d,%0d,%0d,%0d,%0d,%0d\n",
                    frame_index, dut.s2_missing_tile_x, dut.s2_missing_tile_y,
                    dut.s2_missing_set, dut.selected_way_comb, miss_index);
                miss_index = miss_index + 1;
            end
            if (lookup_rsp_valid) begin
                received = received + 1;
                if (received == PIXELS) begin
                    $display("FRAME %0d: pixels=%0d misses=%0d fill_cycles=%0d",
                             frame_index + 1, received, diagnostic_miss_count,
                             diagnostic_fill_cycles);
                    if (frame_index == FRAMES - 1) begin
                        $display("PASS: Stage 7 RTL replay frames=%0d pixels_per_frame=%0d cycles=%0d",
                                 FRAMES, PIXELS, cycles);
                        $fclose(trace_file);
                        $fclose(miss_file);
                        $finish;
                    end else begin
                        $fclose(trace_file);
                        trace_file = $fopen("stage7_tile_trace.csv", "r");
                        if (trace_file == 0) $fatal(1, "Could not reopen coordinate trace");
                        frame_index = frame_index + 1;
                        sent = 0;
                        received = 0;
                        miss_index = 0;
                        invalidate <= 1'b1;
                    end
                end
            end
            if (fill_req_valid && fill_req_ready) begin
                fill_busy <= 1'b1;
                held_row <= fill_row_index;
                beat <= 2'd0;
            end else if (fill_busy && fill_data_ready) begin
                if (beat == 2'd3) begin
                    beat <= 2'd0;
                    if (held_row == 2'd3)
                        fill_busy <= 1'b0;
                    else
                        held_row <= held_row + 1'b1;
                end
                else beat <= beat + 1'b1;
            end
        end
    end
endmodule
