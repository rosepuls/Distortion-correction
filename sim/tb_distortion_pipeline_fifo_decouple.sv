`timescale 1ns/1ps

// Regression for the coordinate-FIFO boundary.  The cache side is held on
// its first miss; the coordinate side must nevertheless absorb one FIFO's
// worth of raster inputs before exerting backpressure.
module tb_distortion_pipeline_fifo_decouple;
    localparam integer FIFO_DEPTH = 512;
    localparam integer REQUIRED_ACCEPTS = FIFO_DEPTH;
    localparam integer OBSERVATION_CYCLES = 800;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_start = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire in_ready;

    wire req_valid;
    wire [31:0] req_addr;
    wire rsp_ready;
    wire cache_rd_cmd_en;
    wire [31:0] cache_rd_cmd_addr;
    wire [31:0] cache_rd_cmd_len;
    wire cache_rd_data_ready;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    integer accepted_count = 0;
    integer cycle_count = 0;
    integer errors = 0;

    always #5 clk = ~clk;

    distortion_image_pipeline #(
        .IMAGE_WIDTH(64),
        .IMAGE_HEIGHT(32),
        .COORD_WIDTH(12),
        .ADDR_WIDTH(32),
        .USE_OPTIMIZED_CORE(1),
        .USE_TILE_CACHE(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol), .in_ready(in_ready),
        .cfg_fx_q19(32'sd33554432), .cfg_fy_q19(32'sd33554432),
        .cfg_cx_q19(32'sd0), .cfg_cy_q19(32'sd0),
        .cfg_inv_fx_q30(32'sd16777216), .cfg_inv_fy_q30(32'sd16777216),
        .cfg_k1_q28(32'sd0), .cfg_k2_q28(32'sd0),
        .cfg_p1_q28(32'sd0), .cfg_p2_q28(32'sd0),
        .req_valid(req_valid), .req_ready(1'b0), .req_addr(req_addr),
        .rsp_valid(1'b0), .rsp_ready(rsp_ready), .rsp_data(24'd0),
        .cache_rd_cmd_en(cache_rd_cmd_en), .cache_rd_cmd_ready(1'b0),
        .cache_rd_cmd_addr(cache_rd_cmd_addr), .cache_rd_cmd_len(cache_rd_cmd_len),
        .cache_rd_data_valid(1'b0), .cache_rd_data_ready(cache_rd_data_ready),
        .cache_rd_data(256'd0), .cache_rd_data_last(1'b0),
        .out_pixel(out_pixel), .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    // The pipeline must not accept scanner traffic until every local reset
    // leaf is synchronously released.  This catches a reset-tree branch
    // that is omitted or released independently from the data plane.
    always @(negedge clk) begin
        if (rst_n && dut.reset_tree_inst.all_ready) begin
            in_valid <= 1'b1;
            in_sof <= (accepted_count == 0);
            in_eol <= ((accepted_count % 64) == 63);
        end else begin
            in_valid <= 1'b0;
            in_sof <= 1'b0;
            in_eol <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (in_valid && in_ready)
                accepted_count = accepted_count + 1;
            if (out_valid) begin
                $display("FAIL: cache-stalled pipeline emitted a pixel");
                errors = errors + 1;
            end
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // Reset leaves must not be equivalent signals.  Their staggered
        // release prevents synthesis from merging them back into the one
        // high-fanout reset net that made detailed routing fail.
        @(posedge clk);
        #1;
        if (dut.reset_tree_inst.geometry_rst_n !== 1'b0
            || dut.reset_tree_inst.fetch_storage_rst_n !== 1'b0) begin
            $display("FAIL: reset leaves released too early");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (dut.reset_tree_inst.geometry_rst_n !== 1'b1
            || dut.reset_tree_inst.fifo_rst_n !== 1'b0
            || dut.reset_tree_inst.fetch_control_rst_n !== 1'b0
            || dut.reset_tree_inst.fetch_storage_rst_n !== 1'b0) begin
            $display("FAIL: reset leaves were not staggered at geometry release");
            errors = errors + 1;
        end
        wait (dut.reset_tree_inst.all_ready);

        // The arithmetic core itself is deliberately reset-free to avoid a
        // multi-thousand-load reset/CE net.  The wrapper must therefore keep
        // its input closed for the post-reset flush window.
        @(posedge clk);
        #1;
        if (in_ready !== 1'b0) begin
            $display("FAIL: pipeline accepted input before the core flush window completed");
            errors = errors + 1;
        end
        wait (in_ready);
        repeat (OBSERVATION_CYCLES) @(posedge clk);

        if (accepted_count < REQUIRED_ACCEPTS) begin
            $display("FAIL: accepted only %0d coordinates while cache stalled; need >= %0d",
                     accepted_count, REQUIRED_ACCEPTS);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "TEST_FAIL: distortion_pipeline_fifo_decouple errors=%0d", errors);

        $display("TEST_PASS: distortion_pipeline_fifo_decouple accepts=%0d", accepted_count);
        $finish;
    end
endmodule
