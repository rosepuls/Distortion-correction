`timescale 1ns/1ps

// Pixel-accurate sequential video regression for the production 720p RGBX
// Tile Cache path.  One complete input frame is loaded at a time so XSim does
// not need to keep 30 x 1280 x 720 words in its simulation memory.
module tb_distortion_frame_processor_cache_video;
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer IMAGE_HEIGHT = 720;
    localparam integer FRAME_COUNT = 30;
    localparam integer MEMORY_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer ADDR_WIDTH = 32;
    localparam integer SIM_TIMEOUT_CYCLES = 120000000;
    localparam signed [31:0] CFG_FX_Q19 = 32'sd314572800;
    localparam signed [31:0] CFG_FY_Q19 = 32'sd314572800;
    localparam signed [31:0] CFG_CX_Q19 = 32'sd335282176;
    localparam signed [31:0] CFG_CY_Q19 = 32'sd188481536;
    localparam signed [31:0] CFG_INV_FX_Q30 = 32'sd1789569;
    localparam signed [31:0] CFG_INV_FY_Q30 = 32'sd1789569;

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
    integer errors = 0;
    integer timeout = 0;
    integer frame_index = 0;
    integer frame_done_count = 0;
    integer output_count = 0;
    integer command_count = 0;
    integer data_beat_count = 0;
    integer frame_command_start = 0;
    integer frame_data_beat_start = 0;
    integer output_file = 0;
    integer expected_x;
    integer backend_word_base = 0;
    integer backend_beat = 0;
    integer backend_wait = 0;
    reg backend_active = 1'b0;

    always #10 clk = ~clk;

    distortion_frame_processor #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(13),
        .ADDR_WIDTH(ADDR_WIDTH),
        .USE_TILE_CACHE(1),
        .TILE_CACHE_SET_COUNT(16),
        .TILE_CACHE_WAYS(4),
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
        .out_pixel(out_pixel), .out_valid(out_valid), .out_sof(out_sof),
        .out_eol(out_eol)
    );

    task automatic check_cond(input condition, input [8*150-1:0] message);
        begin
            if (!condition) begin
                $display("FAIL: frame=%0d %0s", frame_index, message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic load_frame(input integer index);
        string input_file_name;
        string golden_file_name;
        begin
            input_file_name = $sformatf(
                "../../result/sim_assets/cache_video_30frames_1280x720/input_frame_%02d.mem",
                index);
            golden_file_name = $sformatf(
                "../../result/sim_assets/cache_video_30frames_1280x720/golden_frame_%02d.mem",
                index);
            $readmemh(input_file_name, input_words);
            $readmemh(golden_file_name, golden_words);
            check_cond((^input_words[0]) !== 1'bx,
                       "input frame memory was not loaded");
            check_cond((^golden_words[0]) !== 1'bx,
                       "golden frame memory was not loaded");
        end
    endtask

    task automatic open_output_frame(input integer index);
        string output_file_name;
        begin
            output_file_name = $sformatf(
                "../../result/sim_assets/cache_video_30frames_1280x720/rtl_frame_%02d.mem",
                index);
            output_file = $fopen(output_file_name, "w");
            if (output_file == 0)
                $fatal(1, "cannot open RTL output frame: %s", output_file_name);
        end
    endtask

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

    // The model accepts one four-beat burst at a time and inserts a short,
    // deterministic command/data delay on every request.
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
                    $display("FAIL: frame=%0d cache burst length got=%0d expected=4",
                             frame_index, cache_rd_cmd_len);
                    errors = errors + 1;
                end
                if ((cache_rd_cmd_addr[4:0] != 5'd0) ||
                    (cache_rd_cmd_addr + 32'd128 > MEMORY_WORDS * 4)) begin
                    $display("FAIL: frame=%0d cache burst address invalid: %0d",
                             frame_index, cache_rd_cmd_addr);
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
                $display("FAIL: frame=%0d X/Z detected on cache image interface", frame_index);
                errors = errors + 1;
            end

            if (out_valid) begin
                if (output_count >= MEMORY_WORDS) begin
                    $display("FAIL: frame=%0d extra output pixel %h", frame_index, out_pixel);
                    errors = errors + 1;
                end else begin
                    expected_x = output_count % IMAGE_WIDTH;
                    expected_sof = (output_count == 0);
                    expected_eol = (expected_x == IMAGE_WIDTH - 1);
                    if (out_pixel !== golden_words[output_count]) begin
                        if (errors < 20)
                            $display("FAIL: frame=%0d pixel=%0d got=%h expected=%h",
                                     frame_index, output_count, out_pixel,
                                     golden_words[output_count]);
                        errors = errors + 1;
                    end
                    if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                        $display("FAIL: frame=%0d controls pixel=%0d got sof=%b eol=%b",
                                 frame_index, output_count, out_sof, out_eol);
                        errors = errors + 1;
                    end
                    $fdisplay(output_file, "%06h", out_pixel);
                end
                output_count = output_count + 1;
            end

            if (frame_done) begin
                frame_done_count = frame_done_count + 1;
                check_cond(output_count == MEMORY_WORDS,
                           "frame_done arrived before all output pixels");
                check_cond(data_beat_count - frame_data_beat_start ==
                           (command_count - frame_command_start) * 4,
                           "DDR command/data beat accounting mismatch");
                check_cond(!backend_active && !cache_rd_data_valid,
                           "DDR model still owned a burst at frame_done");
                $fclose(output_file);
                output_file = 0;
            end
        end
    endtask

    task automatic pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    initial begin
        load_frame(0);
        open_output_frame(0);
        repeat (4) tick;
        reset_n = 1'b1;
        repeat (4) begin
            tick;
            check_cycle;
        end

        pulse_frame_start;
        while (frame_done_count < FRAME_COUNT && timeout < SIM_TIMEOUT_CYCLES) begin
            tick;
            check_cycle;
            timeout = timeout + 1;
            if (frame_done) begin
                if (frame_done_count < FRAME_COUNT) begin
                    frame_index = frame_done_count;
                    output_count = 0;
                    frame_command_start = command_count;
                    frame_data_beat_start = data_beat_count;
                    load_frame(frame_index);
                    open_output_frame(frame_index);
                    pulse_frame_start;
                end
            end
        end

        check_cond(frame_done_count == FRAME_COUNT,
                   "not all 30 complete frames reached frame_done");
        check_cond(timeout < SIM_TIMEOUT_CYCLES,
                   "30-frame pixel regression exceeded watchdog");
        check_cond(command_count > 0 && data_beat_count == command_count * 4,
                   "total DDR burst accounting mismatch");

        if (errors == 0)
            $display("TEST_PASS: distortion_frame_processor_cache_video frames=%0d pixels_per_frame=%0d cycles=%0d",
                     FRAME_COUNT, MEMORY_WORDS, timeout);
        else
            $fatal(1, "TEST_FAIL: distortion_frame_processor_cache_video errors=%0d", errors);
        $finish;
    end
endmodule
