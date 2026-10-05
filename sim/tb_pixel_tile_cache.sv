`timescale 1ns/1ps

module tb_pixel_tile_cache;
    localparam integer IMAGE_WIDTH = 640;
    localparam integer IMAGE_HEIGHT = 40;
    localparam integer SET_COUNT = 16;
    localparam integer WAYS = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg invalidate = 1'b0;
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
    integer frame_id = 0;
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
        .invalidate(invalidate),
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
            source_word = {8'hC3 + frame_id, source_y[7:0], source_x[7:0], 8'h5A};
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

    // A miss must cross separate request-decode and tag-result registers
    // before it can affect replacement or DDR-fill control.  The three quiet
    // cycles below are the externally observable contract that prevents the
    // accepted lookup, address arithmetic, tag probe and victim selection
    // from collapsing back into one timing path.
    task automatic lookup_miss_requires_registered_request(
        input integer x0,
        input integer y0
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
            #1;
            if (fill_req_valid) begin
                $display("FAIL: lookup miss raised fill_req_valid in its acceptance cycle");
                errors = errors + 1;
            end
            @(negedge clk);
            lookup_valid <= 1'b0;

            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk);
                #1;
                if (fill_req_valid) begin
                    $display("FAIL: lookup miss reached fill control before S1/tag/S2 pipeline completed (cycle %0d)", i + 1);
                    errors = errors + 1;
                end
            end

            while (1) begin
                @(posedge clk);
                if (lookup_rsp_valid && lookup_rsp_ready)
                    break;
            end

            expected_count = before_fill_count + 4;
            if (fill_req_count != expected_count) begin
                $display("FAIL: registered miss expected fill count %0d, got %0d",
                         expected_count, fill_req_count);
                errors = errors + 1;
            end
        end
    endtask

    // After S0 is filled, consecutive hits must keep accepting one lookup per
    // clock and return in request order without a response bubble.
    task automatic continuous_hit_stream_no_bubble;
        integer request_x;
        integer response_x;
        begin
            @(negedge clk);
            lookup_rsp_ready <= 1'b0;
            for (request_x = 1; request_x <= 3; request_x = request_x + 1) begin
                @(negedge clk);
                lookup_x0 <= request_x;
                lookup_y0 <= 1;
                lookup_valid <= 1'b1;
                @(posedge clk);
                if (!lookup_ready) begin
                    $display("FAIL: continuous hit %0d was not accepted", request_x);
                    errors = errors + 1;
                end
            end
            @(negedge clk);
            lookup_valid <= 1'b0;
            repeat (4) @(posedge clk);

            @(negedge clk);
            lookup_rsp_ready <= 1'b1;
            for (response_x = 1; response_x <= 3; response_x = response_x + 1) begin
                @(posedge clk);
                if (!lookup_rsp_valid || !coord_valid || !cache_hit
                    || pixel_p00 !== source_word(response_x, 1)
                    || pixel_p10 !== source_word(response_x + 1, 1)
                    || pixel_p01 !== source_word(response_x, 2)
                    || pixel_p11 !== source_word(response_x + 1, 2)) begin
                    $display("FAIL: continuous hit response/bubble at x=%0d", response_x);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // If frame invalidation catches a registered S2 hit, the old Tag result
    // must not survive the set-by-set valid-bit clear.  The held request has
    // to probe the new frame metadata again and refill before responding.
    task automatic invalidate_inflight_hit_requires_recheck;
        integer expected_count;
        begin
            before_fill_count = fill_req_count;
            @(negedge clk);
            lookup_x0 <= 1;
            lookup_y0 <= 1;
            lookup_valid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (lookup_ready)
                    break;
            end
            @(negedge clk);
            lookup_valid <= 1'b0;

            // Advance the accepted hit through S0 and S1 into S2, then
            // invalidate before S2 is allowed to retire.
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            invalidate <= 1'b1;
            @(negedge clk);
            invalidate <= 1'b0;

            while (1) begin
                @(posedge clk);
                if (lookup_rsp_valid && lookup_rsp_ready)
                    break;
            end

            expected_count = before_fill_count + 4;
            if (fill_req_count != expected_count) begin
                $display("FAIL: in-flight hit survived invalidate without recheck/refill expected=%0d got=%0d",
                         expected_count, fill_req_count);
                errors = errors + 1;
            end
        end
    endtask

    // invalidate is a pulse without ready/acknowledge.  A pulse arriving
    // during refill must be remembered, retire the just-filled old-frame Tag,
    // and force the held request to refill from the new frame.
    task automatic invalidate_during_refill_is_not_lost;
        integer expected_count;
        begin
            before_fill_count = fill_req_count;
            @(negedge clk);
            lookup_x0 <= 33;
            lookup_y0 <= 1;
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
                if (fill_data_valid && fill_data_ready)
                    break;
            end
            @(negedge clk);
            frame_id = frame_id + 1;
            invalidate <= 1'b1;
            @(negedge clk);
            invalidate <= 1'b0;

            while (1) begin
                @(posedge clk);
                if (lookup_rsp_valid && lookup_rsp_ready) begin
                    if (!coord_valid || !cache_hit
                        || pixel_p00 !== source_word(33, 1)
                        || pixel_p10 !== source_word(34, 1)
                        || pixel_p01 !== source_word(33, 2)
                        || pixel_p11 !== source_word(34, 2)) begin
                        $display("FAIL: invalidate-during-refill returned stale/wrong frame pixels");
                        errors = errors + 1;
                    end
                    break;
                end
            end

            expected_count = before_fill_count + 8;
            if (fill_req_count != expected_count) begin
                $display("FAIL: invalidate pulse during refill was lost expected=%0d got=%0d",
                         expected_count, fill_req_count);
                errors = errors + 1;
            end
        end
    endtask

    // A younger request may enter S0/S1 before an older request is known to
    // miss.  Once that miss reaches S2, the younger request must remain held
    // behind it through DDR command backpressure and refill, then respond
    // strictly second.
    task automatic miss_blocks_younger_request_order;
        integer response_index;
        integer wait_cycles;
        begin
            before_fill_count = fill_req_count;
            @(negedge clk);
            lookup_rsp_ready <= 1'b0;
            fill_req_ready <= 1'b0;
            lookup_x0 <= 65;
            lookup_y0 <= 1;
            lookup_valid <= 1'b1;

            @(posedge clk);
            if (!lookup_ready) begin
                $display("FAIL: older miss request was not accepted");
                errors = errors + 1;
            end

            @(negedge clk);
            // This request shares the older miss's Tile.  Its Tag result is
            // sampled before the fill completes, so it must be re-probed
            // rather than launch a redundant second fill afterward.
            lookup_x0 <= 66;
            lookup_y0 <= 1;
            @(posedge clk);
            if (!lookup_ready) begin
                $display("FAIL: younger request could not enter before miss resolution");
                errors = errors + 1;
            end
            @(negedge clk);
            lookup_valid <= 1'b0;

            wait_cycles = 0;
            while (!fill_req_valid && wait_cycles < 20) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!fill_req_valid) begin
                $display("FAIL: older miss did not reach fill control");
                errors = errors + 1;
            end

            // Exercise a held fill command while both requests are resident
            // in the front-end pipeline.
            repeat (3) @(posedge clk);
            if (!fill_req_valid) begin
                $display("FAIL: fill request was not held under backpressure");
                errors = errors + 1;
            end
            @(negedge clk);
            fill_req_ready <= 1'b1;

            wait_cycles = 0;
            while (!lookup_rsp_valid && wait_cycles < 200) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!lookup_rsp_valid) begin
                $display("FAIL: ordered miss sequence produced no response");
                errors = errors + 1;
            end

            @(negedge clk);
            lookup_rsp_ready <= 1'b1;
            response_index = 0;
            wait_cycles = 0;
            while (response_index < 2 && wait_cycles < 20) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (lookup_rsp_valid && lookup_rsp_ready) begin
                    if (response_index == 0) begin
                        if (!coord_valid || !cache_hit
                            || pixel_p00 !== source_word(65, 1)
                            || pixel_p10 !== source_word(66, 1)
                            || pixel_p01 !== source_word(65, 2)
                            || pixel_p11 !== source_word(66, 2)) begin
                            $display("FAIL: younger request overtook older miss");
                            errors = errors + 1;
                        end
                    end else if (!coord_valid || !cache_hit
                                 || pixel_p00 !== source_word(66, 1)
                                 || pixel_p10 !== source_word(67, 1)
                                 || pixel_p01 !== source_word(66, 2)
                                 || pixel_p11 !== source_word(67, 2)) begin
                        $display("FAIL: younger shared-Tile response payload/order mismatch");
                        errors = errors + 1;
                    end
                    response_index = response_index + 1;
                end
            end
            if (response_index != 2) begin
                $display("FAIL: ordered miss sequence returned %0d/2 responses",
                         response_index);
                errors = errors + 1;
            end
            if (fill_req_count != before_fill_count + 4) begin
                $display("FAIL: ordered miss sequence expected fill count %0d, got %0d",
                         before_fill_count + 4, fill_req_count);
                errors = errors + 1;
            end
        end
    endtask

    // A completed refill must not feed the held S2 address straight through
    // the tag comparator and back into S2 metadata on the next cycle.  The
    // retry address is required to spend one isolated cycle in a dedicated
    // register before its tag result can arm the Bank read.  This makes the
    // refill-only control path independently placeable without changing the
    // steady-state hit pipeline.
    task automatic refill_recheck_requires_isolation_cycle;
        integer wait_cycles;
        begin
            @(negedge clk);
            lookup_x0 <= 289;
            lookup_y0 <= 33;
            lookup_valid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (lookup_ready)
                    break;
            end
            @(negedge clk);
            lookup_valid <= 1'b0;

            wait_cycles = 0;
            while (!(fill_data_valid && fill_data_ready
                     && fill_data_row_index == 2'd3
                     && fill_data_beat_index == 2'd3)
                   && wait_cycles < 200) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (wait_cycles == 200) begin
                $display("FAIL: retry-isolation lookup did not complete its refill");
                errors = errors + 1;
            end else begin
                repeat (3) @(posedge clk);
                #1;
                if (lookup_rsp_valid) begin
                    $display("FAIL: refill retry reached the response pipeline without an isolated retry-address cycle");
                    errors = errors + 1;
                end

                wait_cycles = 0;
                while (!lookup_rsp_valid && wait_cycles < 20) begin
                    @(posedge clk);
                    wait_cycles = wait_cycles + 1;
                end
                if (!lookup_rsp_valid || !coord_valid || !cache_hit
                    || pixel_p00 !== source_word(289, 33)
                    || pixel_p10 !== source_word(290, 33)
                    || pixel_p01 !== source_word(289, 34)
                    || pixel_p11 !== source_word(290, 34)) begin
                    $display("FAIL: retry-isolation lookup returned an invalid response");
                    errors = errors + 1;
                end
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

        // First miss fills one Tile; its control must begin only after the
        // request is captured.  The next lookup is therefore a cache hit.
        lookup_miss_requires_registered_request(1, 1);
        lookup_and_check(1, 1, 1, 0);
        continuous_hit_stream_no_bubble();
        invalidate_inflight_hit_requires_recheck();
        invalidate_during_refill_is_not_lost();
        miss_blocks_younger_request_order();
        refill_recheck_requires_isolation_cycle();

        // Payload RAM is intentionally not reset.  A reset must retire its
        // valid tag, so the first lookup after reset refills from the new
        // source frame rather than exposing this tile's old data.
        frame_id = 1;
        @(negedge clk);
        rst_n <= 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n <= 1'b1;
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

        // A new frame must not reuse the previous frame's Tile contents.
        frame_id = 2;
        @(negedge clk);
        invalidate <= 1'b1;
        @(negedge clk);
        invalidate <= 1'b0;
        lookup_and_check(1, 1, 1, 4);

        if (errors != 0)
            $fatal(1, "TEST_FAIL: pixel_tile_cache errors=%0d", errors);

        $display("TEST_PASS: pixel_tile_cache");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "TEST_FAIL: pixel_tile_cache timeout");
    end
endmodule
