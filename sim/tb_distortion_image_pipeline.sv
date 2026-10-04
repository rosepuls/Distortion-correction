`timescale 1ns/1ps

// Image-level test for the real RTL coordinate and Pixel Fetch chain.
// Run from xsim.dir/distortion_image_pipeline so all relative paths resolve
// to the dedicated result/sim_assets/full_chain_256x192 directory.
module tb_distortion_image_pipeline;
    localparam integer IMAGE_WIDTH = 256;
    localparam integer IMAGE_HEIGHT = 192;
    localparam integer ADDR_WIDTH = 16;
    localparam integer MEMORY_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/full_chain_256x192/color_checkerboard_256x192.mem";
    localparam GOLDEN_MEM_FILE = "../../result/sim_assets/full_chain_256x192/golden_barrel_256x192.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/full_chain_256x192/rtl_full_chain_256x192.mem";

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_start = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire in_ready;

    wire req_valid;
    wire req_ready;
    wire [ADDR_WIDTH-1:0] req_addr;
    wire rsp_valid;
    wire rsp_ready;
    wire [23:0] rsp_data;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    reg [23:0] golden_words [0:MEMORY_WORDS-1];
    integer output_file;
    integer errors = 0;
    integer pixel_index;

    always #5 clk = ~clk;

    distortion_image_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(13),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_start(frame_start),
        .in_valid(in_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .in_ready(in_ready),
        .cfg_fx_q19(32'sd94371840),
        .cfg_fy_q19(32'sd94371840),
        .cfg_cx_q19(32'sd66846720),
        .cfg_cy_q19(32'sd50069504),
        .cfg_inv_fx_q30(32'sd5965232),
        .cfg_inv_fy_q30(32'sd5965232),
        .cfg_k1_q28(-32'sd67108864),
        .cfg_k2_q28(32'sd13421773),
        .cfg_p1_q28(32'sd268435),
        .cfg_p2_q28(-32'sd268435),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    ddr_behavior_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PIXEL_WIDTH(24),
        .MEMORY_WORDS(MEMORY_WORDS),
        .FIXED_LATENCY(2),
        .MAX_LATENCY(2),
        .INIT_FILE(INPUT_MEM_FILE)
    ) ddr (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic send_and_check(input integer index);
        integer timeout;
        integer pixel_x;
        integer pixel_y;
        reg expected_sof;
        reg expected_eol;
        begin
            pixel_x = index % IMAGE_WIDTH;
            pixel_y = index / IMAGE_WIDTH;
            expected_sof = (index == 0);
            expected_eol = (pixel_x == IMAGE_WIDTH - 1);

            while (!in_ready) tick;
            @(negedge clk);
            in_valid = 1'b1;
            in_sof = expected_sof;
            in_eol = expected_eol;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;

            timeout = 0;
            while (!out_valid && timeout < 200) begin
                tick;
                timeout = timeout + 1;
            end
            if (!out_valid) begin
                if (errors < 20)
                    $display("FAIL: output timeout at x=%0d y=%0d", pixel_x, pixel_y);
                errors = errors + 1;
            end else begin
                if (out_pixel !== golden_words[index]) begin
                    if (errors < 20)
                        $display("FAIL: pixel x=%0d y=%0d got=%h expected=%h", pixel_x, pixel_y, out_pixel, golden_words[index]);
                    errors = errors + 1;
                end
                if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                    if (errors < 20)
                        $display("FAIL: controls x=%0d y=%0d got sof=%b eol=%b", pixel_x, pixel_y, out_sof, out_eol);
                    errors = errors + 1;
                end
                $fdisplay(output_file, "%06h", out_pixel);
            end
        end
    endtask

    initial begin
        $readmemh(GOLDEN_MEM_FILE, golden_words);
        output_file = $fopen(OUTPUT_MEM_FILE, "w");
        if (output_file == 0)
            $fatal(1, "cannot open output memory file: %s", OUTPUT_MEM_FILE);

        repeat (3) tick;
        rst_n = 1'b1;

        for (pixel_index = 0; pixel_index < MEMORY_WORDS; pixel_index = pixel_index + 1)
            send_and_check(pixel_index);

        $fclose(output_file);
        if (errors == 0)
            $display("TEST_PASS: distortion_image_pipeline");
        else
            $display("TEST_FAIL: distortion_image_pipeline errors=%0d", errors);
        $finish;
    end
endmodule
