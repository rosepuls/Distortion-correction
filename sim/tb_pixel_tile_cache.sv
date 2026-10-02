`timescale 1ns/1ps

module tb_pixel_tile_cache;
    localparam integer IMAGE_WIDTH = 640;
    localparam integer IMAGE_HEIGHT = 40;
    localparam integer SET_COUNT = 16;
    localparam integer WAYS = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg lookup_valid = 1'b0;
    wire lookup_ready;
    reg [11:0] lookup_x0 = 12'd0;
    reg [11:0] lookup_y0 = 12'd0;
    wire lookup_rsp_valid;
    reg lookup_rsp_ready = 1'b1;
    wire [31:0] pixel_p00;
    wire [31:0] pixel_p10;
    wire [31:0] pixel_p01;
    wire [31:0] pixel_p11;
    wire cache_hit;
    wire coord_valid;

    wire fill_req_valid;
    reg fill_req_ready = 1'b1;
    wire [11:0] fill_tile_x;
    wire [11:0] fill_tile_y;
    wire [1:0] fill_row_index;
    reg fill_data_valid = 1'b0;
    wire fill_data_ready;
    reg [255:0] fill_data = 256'd0;
    reg [1:0] fill_data_row_index = 2'd0;
    reg [1:0] fill_data_beat_index = 2'd0;

    integer errors = 0;
    integer fill_req_count = 0;
    integer backend_active = 0;
    integer backend_beat = 0;
    integer backend_tx = 0;
    integer backend_ty = 0;
    integer backend_row = 0;
    integer backend_wait = 0;
    integer before_fill_count;
    integer i;
    integer replacement_x [0:7];
    integer replacement_y [0:7];

    always #5 clk = ~clk;

    pixel_tile_cache #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .SET_COUNT(SET_COUNT),
        .WAYS(WAYS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_valid(lookup_valid),
        .lookup_ready(lookup_ready),
        .lookup_x0(lookup_x0),
        .lookup_y0(lookup_y0),
        .lookup_rsp_valid(lookup_rsp_valid),
        .lookup_rsp_ready(lookup_rsp_ready),
        .pixel_p00(pixel_p00),
        .pixel_p10(pixel_p10),
        .pixel_p01(pixel_p01),
        .pixel_p11(pixel_p11),
        .cache_hit(cache_hit),
        .coord_valid(coord_valid),
        .fill_req_valid(fill_req_valid),
        .fill_req_ready(fill_req_ready),
        .fill_tile_x(fill_tile_x),
        .fill_tile_y(fill_tile_y),
        .fill_row_index(fill_row_index),
        .fill_data_valid(fill_data_valid),
        .fill_data_ready(fill_data_ready),
        .fill_data(fill_data),
        .fill_data_row_index(fill_data_row_index),
        .fill_data_beat_index(fill_data_beat_index)
    );

    function automatic [31:0] source_word(input integer source_x, input integer source_y);
        begin
            source_word = {8'hC3, source_y[7:0], source_x[7:0], 8'h5A};
        end
    endfunction

    function automatic [255:0] make_fill_beat(
        input integer tile_x,
        input integer tile_y,
        input integer row_index,
        input integer beat_index
    );
        integer lane;
        begin
            make_fill_beat = 256'd0;
            for (lane = 0; lane < 8; lane = lane + 1)
                make_fill_beat[lane*32 +: 32] = source_word(
                    tile_x * 32 + beat_index * 8 + lane,
                    tile_y * 4 + row_index
                );
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            fill_data_valid <= 1'b0;
            backend_active <= 0;
            fill_req_count <= 0;
        end else begin
            if (fill_req_valid && fill_req_ready) begin
                fill_req_count = fill_req_count + 1;
                backend_active <= 1;
                backend_beat <= 0;
                backend_tx <= fill_tile_x;
                backend_ty <= fill_tile_y;
                backend_row <= fill_row_index;
                backend_wait <= 1;
            end

            if (fill_data_valid && fill_data_ready) begin
                fill_data_valid <= 1'b0;
                if (backend_beat == 3) begin
                    backend_active <= 0;
                end else begin
                    backend_beat <= backend_beat + 1;
                end
            end else if (backend_active && !fill_data_valid) begin
                if (backend_wait != 0) begin
                    backend_wait <= backend_wait - 1;
                end else begin
                    fill_data <= make_fill_beat(
                        backend_tx, backend_ty, backend_row, backend_beat
                    );
                    fill_data_row_index <= backend_row;
                    fill_data_beat_index <= backend_beat;
                    fill_data_valid <= 1'b1;
                end
            end
        end
    end

    task automatic lookup_and_check(
        input integer x0,
        input integer y0,
        input integer expected_valid,
        input integer expected_fill_delta
    );
        integer expected_count;
        begin
            before_fill_count = fill_req_count;
            @(negedge clk);
            lookup_x0 <= x0;
            lookup_y0 <= y0;
            lookup_valid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (lookup_ready)
                    break;
            end
            @(negedge clk);
            lookup_valid <= 1'b0;

            while (1) begin
                @(posedge clk);
                if (lookup_rsp_valid && lookup_rsp_ready) begin
                    if (coord_valid !== expected_valid || cache_hit !== expected_valid) begin
                        $display("FAIL: validity mismatch at (%0d,%0d)", x0, y0);
                        errors = errors + 1;
                    end
                    if (expected_valid != 0) begin
                        if (pixel_p00 !== source_word(x0, y0)
                            || pixel_p10 !== source_word(x0 + 1, y0)
                            || pixel_p01 !== source_word(x0, y0 + 1)
                            || pixel_p11 !== source_word(x0 + 1, y0 + 1)) begin
                            $display("FAIL: pixel neighborhood mismatch at (%0d,%0d)", x0, y0);
                            errors = errors + 1;
                        end
                    end else if (pixel_p00 !== 32'd0 || pixel_p10 !== 32'd0
                                || pixel_p01 !== 32'd0 || pixel_p11 !== 32'd0) begin
                        $display("FAIL: invalid lookup was not black");
                        errors = errors + 1;
                    end
                    break;
                end
            end

            expected_count = before_fill_count + expected_fill_delta;
            if (fill_req_count != expected_count) begin
                $display("FAIL: expected fill count %0d, got %0d",
                         expected_count, fill_req_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        replacement_x[0] = 1; replacement_y[0] = 1;
        replacement_x[1] = 2; replacement_y[1] = 2;
        replacement_x[2] = 3; replacement_y[2] = 3;
        replacement_x[3] = 4; replacement_y[3] = 5;
        replacement_x[4] = 5; replacement_y[4] = 6;
        replacement_x[5] = 6; replacement_y[5] = 7;
        replacement_x[6] = 7; replacement_y[6] = 8;
        replacement_x[7] = 16; replacement_y[7] = 4;

        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // First miss fills one Tile; the next lookup crosses its x boundary.
        lookup_and_check(1, 1, 1, 4);
        lookup_and_check(31, 1, 1, 4);
        // Tile (0,1) hashes to set 15; verify the full set index is retained
        // instead of being truncated to the way-index width.
        lookup_and_check(1, 3, 1, 4);
        lookup_and_check(1, 3, 1, 0);
        lookup_and_check(639, 1, 0, 0);

        // Eight tags map to one set.  Promote tile (0,0) before adding the
        // eighth new tag; true LRU must retain the promoted tag.
        for (i = 0; i < 7; i = i + 1)
            lookup_and_check(
                replacement_x[i] * 32 + 1,
                replacement_y[i] * 4 + 1,
                1,
                4
            );
        lookup_and_check(1, 1, 1, 0);
        lookup_and_check(
            replacement_x[7] * 32 + 1,
            replacement_y[7] * 4 + 1,
            1,
            4
        );
        lookup_and_check(1, 1, 1, 0);

        if (errors != 0)
            $fatal(1, "TEST_FAIL: pixel_tile_cache errors=%0d", errors);

        $display("TEST_PASS: pixel_tile_cache");
        $finish;
    end
endmodule
