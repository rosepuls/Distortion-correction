`timescale 1ns / 1ps

// Full-frame miss count from the actual pixel_tile_cache RTL. Row data is
// deterministic and immediately available; its payload does not affect tags.
module stage7_cache_rtl_replay_tb;
    localparam integer PIXELS = 1280 * 720;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0;
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
    integer trace_file;
    integer parsed, trace_id, trace_x0, trace_y0, trace_valid;
    integer sent = 0, received = 0, cycles = 0;

    assign fill_req_ready = !fill_busy;
    pixel_tile_cache #(
        .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720),
        .SET_COUNT(16), .WAYS(4)
    ) dut (
        .clk(clk), .rst_n(rstn), .invalidate(1'b0),
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
            accepted <= lookup_valid && lookup_ready;
            if (lookup_valid && lookup_ready) sent = sent + 1;
            if (lookup_rsp_valid) begin
                received = received + 1;
                if (received == PIXELS) begin
                    $display("PASS: Stage 7 RTL replay pixels=%0d misses=%0d fill_cycles=%0d cycles=%0d",
                             received, diagnostic_miss_count,
                             diagnostic_fill_cycles, cycles);
                    $fclose(trace_file);
                    $finish;
                end
            end
            if (fill_req_valid && fill_req_ready) begin
                fill_busy <= 1'b1;
                held_row <= fill_row_index;
                beat <= 2'd0;
            end else if (fill_busy && fill_data_ready) begin
                if (beat == 2'd3) fill_busy <= 1'b0;
                else beat <= beat + 1'b1;
            end
        end
    end
endmodule
