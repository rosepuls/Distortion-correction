`timescale 1ns / 1ps

module stage12_full_frame_tb;
    localparam integer SOURCE_WIDTH = 1280;
    localparam integer SOURCE_HEIGHT = 720;
    localparam integer OUTPUT_WIDTH = 1920;
    localparam integer OUTPUT_HEIGHT = 1080;
    localparam integer PIXELS_PER_FRAME = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam integer BURSTS_PER_FRAME = PIXELS_PER_FRAME / 128;
    localparam integer BEATS_PER_FRAME = PIXELS_PER_FRAME / 8;

    reg clk = 1'b0;
    always #4 clk = ~clk; // 125 MHz processing clock
    reg rstn = 1'b0, start = 1'b0;
    reg [1:0] input_slot = 2'd2, output_slot = 2'd1;
    reg [31:0] input_sequence = 32'd99;
    wire start_ready, copy_done, copy_error, active, fatal_fault;
    wire [31:0] completed_sequence, fetched_rows;
    wire [15:0] tile_read_errors;
    wire read_valid, read_reserve;
    wire [27:0] read_addr;
    wire [3:0] read_len;
    reg read_rvalid = 1'b0, read_rlast = 1'b0;
    reg [255:0] read_rdata = 256'd0;
    wire write_awvalid, write_wvalid, write_source_busy;
    wire [27:0] write_awaddr;
    wire [3:0] write_awlen;
    wire [255:0] write_wdata;
    wire [31:0] write_wstrb;
    reg writing = 1'b0, returning = 1'b0, copy_write_idle = 1'b1;
    reg [27:0] current_read_addr = 28'd0;
    integer r_index = 0, w_index = 0, drain_delay = 0;
    integer ar_count = 0, aw_count = 0, returned = 0, written = 0;
    integer finished = 0, cycle_count = 0, start_cycle = 0, lane;

    wire write_wready = writing;
    wire write_wlast = writing && (w_index == 15);

    frame_identity_transform_engine #(
        .SOURCE_WIDTH(SOURCE_WIDTH), .SOURCE_HEIGHT(SOURCE_HEIGHT),
        .OUTPUT_WIDTH(OUTPUT_WIDTH), .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
        .CACHE_SET_COUNT(16), .CACHE_WAYS(8), .STALL_LIMIT(24'hffffff)
    ) dut (
        .clk(clk), .rstn(rstn), .start(start), .start_ready(start_ready),
        .input_slot(input_slot), .output_slot(output_slot),
        .input_sequence(input_sequence), .copy_done(copy_done),
        .copy_error(copy_error), .active(active), .fatal_fault(fatal_fault),
        .completed_sequence(completed_sequence),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(1'b1),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .write_awvalid(write_awvalid), .write_awaddr(write_awaddr),
        .write_awlen(write_awlen), .write_awready(1'b1),
        .write_wvalid(write_wvalid), .write_wdata(write_wdata),
        .write_wstrb(write_wstrb), .write_wready(write_wready),
        .write_wlast(write_wlast), .write_source_busy(write_source_busy),
        .copy_write_idle(copy_write_idle), .read_fault(1'b0), .write_fault(1'b0),
        .fetched_rows(fetched_rows), .tile_read_errors(tile_read_errors)
    );

    function automatic [31:0] source_pixel(input integer index);
        reg [7:0] r, g, b;
        begin
            r = (index >> 2) & 8'hff;
            g = (index >> 1) & 8'hff;
            b = index & 8'hff;
            source_pixel = {r,g,b,8'h00};
        end
    endfunction

    function automatic [255:0] make_beat(input integer first_word);
        integer n;
        begin
            for (n = 0; n < 8; n = n + 1)
                make_beat[n*32 +: 32] = source_pixel(first_word+n);
        end
    endfunction

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!rstn) begin
            returning <= 1'b0; writing <= 1'b0;
            read_rvalid <= 1'b0; read_rlast <= 1'b0;
            r_index <= 0; w_index <= 0;
            copy_write_idle <= 1'b1; drain_delay <= 0;
        end else begin
            read_rvalid <= 1'b0;
            read_rlast <= 1'b0;
            if (read_valid) begin
                if (!read_reserve || read_len != 4'd3 ||
                    read_addr[2:0] != 3'd0 || read_addr[24:22] != input_slot ||
                    (read_addr[21:0] + 22'd31) >= (SOURCE_WIDTH * SOURCE_HEIGHT) || returning)
                    $fatal(1,"FAIL: invalid source tile-row request addr=%h len=%0d",read_addr,read_len);
                ar_count <= ar_count + 1;
                returning <= 1'b1;
                current_read_addr <= read_addr;
                r_index <= 0;
            end
            if (returning) begin
                read_rvalid <= 1'b1;
                read_rlast <= (r_index == 3);
                read_rdata <= make_beat((current_read_addr & 28'h3fffff) + r_index*8);
                returned <= returned + 1;
                if (r_index == 3) returning <= 1'b0;
                else r_index <= r_index + 1;
            end
            if (write_awvalid) begin
                if (write_awlen != 4'd15 ||
                    aw_count >= BURSTS_PER_FRAME ||
                    (aw_count*128 + 127) >= PIXELS_PER_FRAME ||
                    write_awaddr !== (((output_slot + 3) << 22) + aw_count*128) || writing)
                    $fatal(1,"FAIL: output burst address/count mismatch at burst %0d",aw_count);
                aw_count <= aw_count + 1;
                writing <= 1'b1;
                w_index <= 0;
                copy_write_idle <= 1'b0;
            end
            if (write_wvalid && write_wready) begin
                if (write_wstrb !== 32'hffffffff || !write_source_busy)
                    $fatal(1,"FAIL: invalid output write beat");
                for (lane = 0; lane < 8; lane = lane + 1)
                    if (write_wdata[lane*32 +: 8] !== 8'h00)
                        $fatal(1,"FAIL: RGBX low byte changed");
                written <= written + 1;
                if (w_index == 15) begin
                    writing <= 1'b0;
                    drain_delay <= 4;
                end else w_index <= w_index + 1;
            end
            if (drain_delay > 0) begin
                drain_delay <= drain_delay - 1;
                if (drain_delay == 1) copy_write_idle <= 1'b1;
            end
            if (copy_done) begin
                if (!copy_write_idle || writing || fatal_fault ||
                    completed_sequence != input_sequence)
                    $fatal(1,"FAIL: output frame published before write drain");
                finished <= finished + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rstn=1'b1;
        wait(start_ready);
        @(negedge clk); start_cycle=cycle_count; start=1'b1;
        @(posedge clk);
        @(negedge clk); start=1'b0;
        wait(finished == 1);
        @(negedge clk);
        if (copy_error || fatal_fault || aw_count != BURSTS_PER_FRAME ||
            written != BEATS_PER_FRAME || returned != ar_count*4 ||
            tile_read_errors != 0 || fetched_rows != ar_count)
            $fatal(1,"FAIL: frame totals AR=%0d AW=%0d R=%0d W=%0d rows=%0d",
                   ar_count,aw_count,returned,written,fetched_rows);
        $display("PASS: Stage 12 1080p frame pixels=%0d bursts=%0d cycles=%0d fps_at_125MHz=%0d AR=%0d R=%0d",
                 PIXELS_PER_FRAME,BURSTS_PER_FRAME,cycle_count-start_cycle,
                 125000000/(cycle_count-start_cycle),ar_count,returned);
        $finish;
    end

    initial begin
        repeat (8000000) @(posedge clk);
        $fatal(1,"FAIL: 1080p frame simulation timed out");
    end
endmodule
