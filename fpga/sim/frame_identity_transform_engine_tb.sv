`timescale 1ns / 1ps

module frame_identity_transform_engine_tb;
`ifdef FULL_FRAME_TEST
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer IMAGE_HEIGHT = 720;
    localparam integer CACHE_SETS = 16;
    localparam integer CACHE_WAYS = 4;
`else
    localparam integer IMAGE_WIDTH = 64;
    localparam integer IMAGE_HEIGHT = 8;
    localparam integer CACHE_SETS = 2;
    localparam integer CACHE_WAYS = 2;
`endif
    localparam integer BURSTS_PER_FRAME = IMAGE_WIDTH*IMAGE_HEIGHT/128;
    localparam integer BEATS_PER_FRAME = IMAGE_WIDTH*IMAGE_HEIGHT/8;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, start = 0;
    reg [1:0] input_slot = 2, output_slot = 1;
    reg [31:0] input_sequence = 99;
    wire start_ready, copy_done, copy_error, active, fatal_fault;
    wire [31:0] completed_sequence, fetched_rows;
    wire [15:0] tile_read_errors;
    wire read_valid, read_reserve;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_rvalid = 0, read_rlast = 0;
    reg [255:0] read_rdata = 0;
    wire write_awvalid, write_wvalid, write_source_busy;
    wire [27:0] write_awaddr;
    wire [3:0] write_awlen;
    wire [255:0] write_wdata;
    wire [31:0] write_wstrb;
    reg writing = 0, returning = 0, copy_write_idle = 1;
    reg [27:0] current_read_addr = 0;
    integer r_index = 0, w_index = 0, drain_delay = 0;
    integer ar_count = 0, aw_count = 0, returned = 0, written = 0;
    integer finished = 0, lane;
    integer cycle_count = 0;
    integer start_cycle = 0;

    wire write_wready = writing;
    wire write_wlast = writing && w_index == 15;
    frame_identity_transform_engine #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CACHE_SET_COUNT(CACHE_SETS), .CACHE_WAYS(CACHE_WAYS),
        .STALL_LIMIT(5000)
    ) dut (
        .clk(clk), .rstn(rstn), .start(start), .start_ready(start_ready),
        .input_slot(input_slot), .output_slot(output_slot),
        .input_sequence(input_sequence), .copy_done(copy_done),
        .copy_error(copy_error), .active(active), .fatal_fault(fatal_fault),
        .completed_sequence(completed_sequence),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(1'b1), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .write_awvalid(write_awvalid), .write_awaddr(write_awaddr),
        .write_awlen(write_awlen), .write_awready(1'b1),
        .write_wvalid(write_wvalid), .write_wdata(write_wdata),
        .write_wstrb(write_wstrb), .write_wready(write_wready),
        .write_wlast(write_wlast),
        .write_source_busy(write_source_busy),
        .copy_write_idle(copy_write_idle),
        .read_fault(1'b0), .write_fault(1'b0),
        .fetched_rows(fetched_rows), .tile_read_errors(tile_read_errors)
    );

    function automatic [31:0] pixel_word(input integer index);
        reg [7:0] green, blue;
        begin
            green = index;
            blue = index >> 8;
            pixel_word = {8'h5a,green,blue,8'h00};
        end
    endfunction

    function automatic [255:0] make_beat(input integer first_word);
        integer word_lane;
        begin
            for (word_lane = 0; word_lane < 8; word_lane = word_lane + 1)
                make_beat[word_lane*32 +: 32] = pixel_word(first_word + word_lane);
        end
    endfunction

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!rstn) begin
            returning <= 0;
            writing <= 0;
            read_rvalid <= 0;
            read_rlast <= 0;
            r_index <= 0;
            w_index <= 0;
            copy_write_idle <= 1;
            drain_delay <= 0;
        end else begin
            read_rvalid <= 0;
            read_rlast <= 0;
            if (read_valid) begin
                if (!read_reserve || read_len != 3 || read_addr[2:0] != 0 ||
                    (read_addr >> 22) != input_slot || returning)
                    $fatal(1, "FAIL: tile-row AR address/reservation");
                ar_count <= ar_count + 1;
                returning <= 1;
                current_read_addr <= read_addr;
                r_index <= 0;
            end
            if (returning) begin
                read_rvalid <= 1;
                read_rlast <= r_index == 3;
                read_rdata <= make_beat((current_read_addr & 28'h3fffff) + r_index*8);
                returned <= returned + 1;
                if (r_index == 3) returning <= 0;
                else r_index <= r_index + 1;
            end
            if (write_awvalid) begin
                if (write_awlen != 15 ||
                    write_awaddr !== (((output_slot + 3) << 22) +
                                       (aw_count % BURSTS_PER_FRAME)*128) || writing)
                    $fatal(1, "FAIL: output-frame AW address");
                aw_count <= aw_count + 1;
                writing <= 1;
                w_index <= 0;
                copy_write_idle <= 0;
            end
            if (write_wvalid && write_wready) begin
                if (write_wdata !== make_beat((written % BEATS_PER_FRAME)*8) ||
                    write_wstrb !== 32'hffffffff || !write_source_busy)
                    $fatal(1, "FAIL: transformed output beat %0d got %h expected %h",
                        written, write_wdata,
                        make_beat((written % BEATS_PER_FRAME)*8));
                written <= written + 1;
                if (w_index == 15) begin
                    writing <= 0;
                    drain_delay <= 4;
                end else w_index <= w_index + 1;
            end
            if (drain_delay > 0) begin
                drain_delay <= drain_delay - 1;
                if (drain_delay == 1) copy_write_idle <= 1;
            end
            if (copy_done) begin
                if (!copy_write_idle || writing || fatal_fault)
                    $fatal(1, "FAIL: frame published before drain or after fault");
                finished <= finished + 1;
            end
        end
    end

    task automatic run_frame(
        input [1:0] src_slot,
        input [1:0] dst_slot,
        input [31:0] seq_value,
        input integer completion_target
    );
        begin
            @(negedge clk);
            if (!start_ready) $fatal(1, "FAIL: transform engine not ready");
            input_slot = src_slot;
            output_slot = dst_slot;
            input_sequence = seq_value;
            start_cycle = cycle_count;
            start = 1;
            @(posedge clk);
            @(negedge clk);
            start = 0;
            wait (finished == completion_target);
            @(negedge clk);
            if (!start_ready || completed_sequence !== seq_value)
                $fatal(1, "FAIL: transform completion sequence");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rstn = 1;
        run_frame(2'd2,2'd1,32'd99,1);
`ifndef FULL_FRAME_TEST
        run_frame(2'd0,2'd2,32'd100,2);
        if (copy_error || fatal_fault || aw_count != 8 || written != 128 ||
            ar_count < 16 || returned != ar_count*4 ||
            tile_read_errors != 0 || fetched_rows != ar_count)
            $fatal(1, "FAIL: transform totals AR=%0d AW=%0d R=%0d W=%0d",
                ar_count,aw_count,returned,written);
        $display("PASS: identity transform engine copied two 512-pixel frames through DDR Tile Cache");
`else
        if (copy_error || fatal_fault || aw_count != BURSTS_PER_FRAME ||
            written != BEATS_PER_FRAME || returned != ar_count*4 ||
            tile_read_errors != 0 || fetched_rows != ar_count)
            $fatal(1, "FAIL: full frame totals AR=%0d AW=%0d R=%0d W=%0d",
                ar_count,aw_count,returned,written);
        $display("PASS: full 1280x720 DDR identity frame, cycles=%0d AR=%0d AW=%0d",
                 cycle_count-start_cycle, ar_count, aw_count);
`endif
        $finish;
    end

    initial begin
`ifdef FULL_FRAME_TEST
        repeat (4000000) @(posedge clk);
`else
        repeat (30000) @(posedge clk);
`endif
        $fatal(1, "FAIL: identity transform engine timeout");
    end
endmodule
