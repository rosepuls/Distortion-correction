`timescale 1ns/1ps

// Image-level verification of mes50hp_top through the RGBX Tile Cache path.
// The behavioral backend accepts one four-beat DDR burst at a time and packs
// eight RGBX8888 pixels into each 256-bit beat, matching the board adapter.
module tb_mes50hp_top_cache_image;
`ifdef CACHE_IMAGE_720P
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer IMAGE_HEIGHT = 720;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_1280x720/distorted_input_rgb888_1280x720.mem";
    localparam GOLDEN_MEM_FILE = "../../result/sim_assets/cache_full_chain_1280x720/golden_corrected_q18_1280x720.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_1280x720/rtl_corrected_q18_1280x720.mem";
    localparam integer SIM_TIMEOUT_CYCLES = 30000000;
    localparam signed [31:0] CFG_FX_Q19 = 32'sd314572800;
    localparam signed [31:0] CFG_FY_Q19 = 32'sd314572800;
    localparam signed [31:0] CFG_CX_Q19 = 32'sd335282176;
    localparam signed [31:0] CFG_CY_Q19 = 32'sd188481536;
    localparam signed [31:0] CFG_INV_FX_Q30 = 32'sd1789569;
    localparam signed [31:0] CFG_INV_FY_Q30 = 32'sd1789569;
`elsif FULL_HD_CACHE_IMAGE
    localparam integer IMAGE_WIDTH = 1920;
    localparam integer IMAGE_HEIGHT = 1080;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_1920x1080/distorted_input_rgb888_1920x1080.mem";
    localparam GOLDEN_MEM_FILE = "../../result/sim_assets/cache_full_chain_1920x1080/golden_corrected_q18_1920x1080.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_1920x1080/rtl_corrected_q18_1920x1080.mem";
    localparam integer SIM_TIMEOUT_CYCLES = 50000000;
    localparam signed [31:0] CFG_FX_Q19 = 32'sd471859200;
    localparam signed [31:0] CFG_FY_Q19 = 32'sd471859200;
    localparam signed [31:0] CFG_CX_Q19 = 32'sd503054336;
    localparam signed [31:0] CFG_CY_Q19 = 32'sd282853376;
    localparam signed [31:0] CFG_INV_FX_Q30 = 32'sd1193046;
    localparam signed [31:0] CFG_INV_FY_Q30 = 32'sd1193046;
`else
    localparam integer IMAGE_WIDTH = 256;
    localparam integer IMAGE_HEIGHT = 192;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_256x192/distorted_input_rgb888_256x192.mem";
    localparam GOLDEN_MEM_FILE = "../../result/sim_assets/cache_full_chain_256x192/golden_corrected_q18_256x192.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/cache_full_chain_256x192/rtl_corrected_q18_256x192.mem";
    localparam integer SIM_TIMEOUT_CYCLES = 4000000;
    localparam signed [31:0] CFG_FX_Q19 = 32'sd94371840;
    localparam signed [31:0] CFG_FY_Q19 = 32'sd94371840;
    localparam signed [31:0] CFG_CX_Q19 = 32'sd66846720;
    localparam signed [31:0] CFG_CY_Q19 = 32'sd50069504;
    localparam signed [31:0] CFG_INV_FX_Q30 = 32'sd5965232;
    localparam signed [31:0] CFG_INV_FY_Q30 = 32'sd5965232;
`endif
`ifdef CACHE_WAYS_2
    localparam integer TILE_CACHE_WAY_COUNT = 2;
`elsif CACHE_IMAGE_720P
    localparam integer TILE_CACHE_WAY_COUNT = 4;
`else
    localparam integer TILE_CACHE_WAY_COUNT = 8;
`endif
`ifdef TILE_CACHE_SETS_32
    localparam integer TILE_CACHE_SET_COUNT = 32;
`elsif TILE_CACHE_SETS_48
    localparam integer TILE_CACHE_SET_COUNT = 48;
`else
    localparam integer TILE_CACHE_SET_COUNT = 16;
`endif
    localparam integer ADDR_WIDTH = 32;
    localparam integer MEMORY_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg frame_start = 1'b0;
    wire frame_busy;
    wire frame_done;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    wire cache_rd_cmd_en;
    reg cache_rd_cmd_ready = 1'b0;
    wire [ADDR_WIDTH-1:0] cache_rd_cmd_addr;
    wire [31:0] cache_rd_cmd_len;
    reg cache_rd_data_valid = 1'b0;
    wire cache_rd_data_ready;
    reg [255:0] cache_rd_data = 256'd0;
    reg cache_rd_data_last = 1'b0;

    reg [23:0] input_words [0:MEMORY_WORDS-1];
    reg [23:0] golden_words [0:MEMORY_WORDS-1];
    integer output_file;
    integer errors = 0;
    integer output_count = 0;
    integer timeout = 0;
    integer command_count = 0;
    integer data_beat_count = 0;
    integer frame_done_count = 0;
    integer post_output_cycles = 0;
    reg frame_done_seen = 1'b0;
    integer expected_x;
    integer backend_word_base = 0;
    integer backend_beat = 0;
    integer backend_wait = 0;
    reg backend_active = 1'b0;

    always #10 clk = ~clk;

    // frame_done is a one-cycle pulse.  Keep a sticky observation so the
    // long full-HD run cannot spin until its watchdog after the last pixel.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            frame_done_seen <= 1'b0;
        else if (frame_done)
            frame_done_seen <= 1'b1;
    end

    mes50hp_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(13),
        .ADDR_WIDTH(ADDR_WIDTH),
        .USE_TILE_CACHE(1),
        .TILE_CACHE_SET_COUNT(TILE_CACHE_SET_COUNT),
        .TILE_CACHE_WAYS(TILE_CACHE_WAY_COUNT),
        .USE_PSEUDO_LRU(1),
        .FRAME_BASE_BYTE_ADDR(32'd0)
    ) dut (
        .clk(clk), .reset_n(reset_n), .frame_start(frame_start),
        .frame_busy(frame_busy), .frame_done(frame_done),
        .cfg_fx_q19(CFG_FX_Q19), .cfg_fy_q19(CFG_FY_Q19),
        .cfg_cx_q19(CFG_CX_Q19), .cfg_cy_q19(CFG_CY_Q19),
        .cfg_inv_fx_q30(CFG_INV_FX_Q30), .cfg_inv_fy_q30(CFG_INV_FY_Q30),
        .cfg_k1_q28(-32'sd67108864), .cfg_k2_q28(32'sd13421773),
        .cfg_p1_q28(32'sd268435), .cfg_p2_q28(-32'sd268435),
        .mem_req_valid(), .mem_req_ready(1'b0), .mem_req_addr(),
        .mem_rsp_valid(1'b0), .mem_rsp_ready(), .mem_rsp_data(24'd0),
        .cache_rd_cmd_en(cache_rd_cmd_en),
        .cache_rd_cmd_ready(cache_rd_cmd_ready),
        .cache_rd_cmd_addr(cache_rd_cmd_addr),
        .cache_rd_cmd_len(cache_rd_cmd_len),
        .cache_rd_data_valid(cache_rd_data_valid),
        .cache_rd_data_ready(cache_rd_data_ready),
        .cache_rd_data(cache_rd_data), .cache_rd_data_last(cache_rd_data_last),
        .out_pixel(out_pixel), .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    function automatic [255:0] make_beat(input integer word_base, input integer beat_index);
        integer lane;
        integer word_index;
        begin
            make_beat = 256'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                word_index = word_base + beat_index * 8 + lane;
                if (word_index >= 0 && word_index < MEMORY_WORDS)
                    make_beat[lane * 32 +: 32] = {input_words[word_index], 8'h00};
            end
        end
    endfunction

    // Model a controller that occasionally cannot accept a command.  Once a
    // command is accepted, return exactly four accepted beats in order.
    always @(posedge clk) begin
        if (!reset_n) begin
            cache_rd_cmd_ready <= 1'b0;
            cache_rd_data_valid <= 1'b0;
            cache_rd_data <= 256'd0;
            cache_rd_data_last <= 1'b0;
            backend_active <= 1'b0;
            backend_word_base <= 0;
            backend_beat <= 0;
            backend_wait <= 0;
        end else begin
            cache_rd_cmd_ready <= !backend_active && !cache_rd_data_valid && ((timeout % 5) != 2);

            if (cache_rd_cmd_en && cache_rd_cmd_ready) begin
                command_count = command_count + 1;
                if (cache_rd_cmd_len != 32'd4) begin
                    $display("FAIL: cache burst length got=%0d expected=4", cache_rd_cmd_len);
                    errors = errors + 1;
                end
                if ((cache_rd_cmd_addr[4:0] != 5'd0) ||
                    (cache_rd_cmd_addr + 32'd128 > MEMORY_WORDS * 4)) begin
                    $display("FAIL: cache burst address out of range or unaligned: %0d", cache_rd_cmd_addr);
                    errors = errors + 1;
                end
                backend_word_base <= cache_rd_cmd_addr >> 2;
                backend_beat <= 0;
                backend_wait <= 2;
                backend_active <= 1'b1;
            end

            if (cache_rd_data_valid && cache_rd_data_ready) begin
                data_beat_count = data_beat_count + 1;
                cache_rd_data_valid <= 1'b0;
                cache_rd_data_last <= 1'b0;
                if (backend_beat == 3) begin
                    backend_active <= 1'b0;
                    backend_beat <= 0;
                end else begin
                    backend_beat <= backend_beat + 1;
                end
            end else if (backend_active && !cache_rd_data_valid) begin
                if (backend_wait != 0) begin
                    backend_wait <= backend_wait - 1;
                end else begin
                    cache_rd_data <= make_beat(backend_word_base, backend_beat);
                    cache_rd_data_valid <= 1'b1;
                    cache_rd_data_last <= (backend_beat == 3);
                end
            end
        end
    end

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_cycle;
        reg expected_sof;
        reg expected_eol;
        begin
            if ($isunknown({frame_busy, frame_done, cache_rd_cmd_en,
                            cache_rd_data_valid, cache_rd_data_ready,
                            out_valid, out_sof, out_eol, out_pixel})) begin
                $display("FAIL: X/Z detected on cache image interface");
                errors = errors + 1;
            end

            if (out_valid) begin
                if (output_count >= MEMORY_WORDS) begin
                    $display("FAIL: extra output pixel %h", out_pixel);
                    errors = errors + 1;
                end else begin
                    expected_x = output_count % IMAGE_WIDTH;
                    expected_sof = (output_count == 0);
                    expected_eol = (expected_x == IMAGE_WIDTH - 1);
                    if (out_pixel !== golden_words[output_count]) begin
                        if (errors < 20)
                            $display("FAIL: pixel index=%0d got=%h expected=%h",
                                     output_count, out_pixel, golden_words[output_count]);
                        errors = errors + 1;
                    end
                    if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                        $display("FAIL: controls index=%0d got sof=%b eol=%b expected sof=%b eol=%b",
                                 output_count, out_sof, out_eol, expected_sof, expected_eol);
                        errors = errors + 1;
                    end
                    $fdisplay(output_file, "%06h", out_pixel);
                end
                output_count = output_count + 1;
            end

            if (frame_done) begin
                frame_done_count = frame_done_count + 1;
                if (output_count != MEMORY_WORDS) begin
                    $display("FAIL: frame_done before complete output count=%0d", output_count);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $readmemh(INPUT_MEM_FILE, input_words);
        $readmemh(GOLDEN_MEM_FILE, golden_words);
`ifdef EXPECT_CACHE_WAYS_2
        if (TILE_CACHE_WAY_COUNT != 2)
            $fatal(1, "TEST_FAIL: CACHE_WAYS_2 did not select a 2-way Tile Cache");
`endif
        // Every 720p routability candidate must retain the production 32 KiB
        // RGBX cache capacity: 64 tiles x 32 x 4 x 4 bytes.
        if ((TILE_CACHE_SET_COUNT * TILE_CACHE_WAY_COUNT) != 64)
            $fatal(1, "TEST_FAIL: cache capacity changed: sets=%0d ways=%0d",
                   TILE_CACHE_SET_COUNT, TILE_CACHE_WAY_COUNT);
        output_file = $fopen(OUTPUT_MEM_FILE, "w");
        if (output_file == 0)
            $fatal(1, "cannot open output memory file: %s", OUTPUT_MEM_FILE);

        repeat (4) tick;
        reset_n = 1'b1;
        repeat (4) begin
            tick;
            check_cycle;
        end

        @(negedge clk);
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;

        while (!frame_done_seen && timeout < SIM_TIMEOUT_CYCLES &&
               post_output_cycles < 8) begin
            tick;
            check_cycle;
            timeout = timeout + 1;
            if (output_count == MEMORY_WORDS)
                post_output_cycles = post_output_cycles + 1;
        end
        if (!frame_done_seen) begin
            $display("FAIL: frame_done was not observed after %0d cycles", timeout);
            errors = errors + 1;
        end
        tick;
        check_cycle;
        $fclose(output_file);

        if (output_count != MEMORY_WORDS) begin
            $display("FAIL: output count got=%0d expected=%0d", output_count, MEMORY_WORDS);
            errors = errors + 1;
        end
        if (frame_done_count != 1) begin
            $display("FAIL: frame_done count got=%0d expected=1", frame_done_count);
            errors = errors + 1;
        end
        if (command_count == 0 || data_beat_count != command_count * 4) begin
            $display("FAIL: burst accounting commands=%0d data_beats=%0d", command_count, data_beat_count);
            errors = errors + 1;
        end
`ifdef CACHE_IMAGE_720P
        if (timeout > 3333333) begin
            $display("FAIL: 720p30 frame used %0d cycles, budget is 3333333", timeout);
            errors = errors + 1;
        end
`endif

        if (errors == 0)
            $display("TEST_PASS: mes50hp_top_cache_image outputs=%0d commands=%0d beats=%0d cycles=%0d",
                     output_count, command_count, data_beat_count, timeout);
        else
            $fatal(1, "TEST_FAIL: mes50hp_top_cache_image errors=%0d", errors);
        $finish;
    end
endmodule
