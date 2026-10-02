`timescale 1ns/1ps

// Image-level verification of the synthesizable PGL50H algorithm top.
// One frame_start pulse must autonomously scan and correct the full frame.
module tb_mes50hp_top_image;
    localparam integer IMAGE_WIDTH = 256;
    localparam integer IMAGE_HEIGHT = 192;
    localparam integer ADDR_WIDTH = 16;
    localparam integer MEMORY_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/mes50hp_top_image_256x192/distorted_input_256x192.mem";
    localparam GOLDEN_MEM_FILE = "../../result/sim_assets/mes50hp_top_image_256x192/golden_corrected_q18_256x192.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/mes50hp_top_image_256x192/rtl_corrected_q18_256x192.mem";

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg frame_start = 1'b0;
    wire frame_busy;
    wire frame_done;
    wire mem_req_valid;
    wire mem_req_ready;
    wire [ADDR_WIDTH-1:0] mem_req_addr;
    wire mem_rsp_valid;
    wire mem_rsp_ready;
    wire [23:0] mem_rsp_data;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    reg [23:0] golden_words [0:MEMORY_WORDS-1];
    integer output_file;
    integer errors = 0;
    integer output_count = 0;
    integer timeout = 0;
    integer expected_x;
    integer frame_done_count = 0;
    integer request_stall_count = 0;
    reg waiting_for_request_accept = 1'b0;
    reg [ADDR_WIDTH-1:0] stalled_request_addr = {ADDR_WIDTH{1'b0}};
    reg busy_start_sent = 1'b0;

    // MES50HP board system clock: 50 MHz.
    always #10 clk = ~clk;

    mes50hp_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(13),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .frame_start(frame_start),
        .frame_busy(frame_busy),
        .frame_done(frame_done),
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
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_ready(mem_rsp_ready),
        .mem_rsp_data(mem_rsp_data),
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
        .MAX_LATENCY(4),
        .READY_STALL_PERIOD(3),
        .INIT_FILE(INPUT_MEM_FILE)
    ) ddr (
        .clk(clk),
        .rst_n(reset_n),
        .req_valid(mem_req_valid),
        .req_ready(mem_req_ready),
        .req_addr(mem_req_addr),
        .rsp_valid(mem_rsp_valid),
        .rsp_ready(mem_rsp_ready),
        .rsp_data(mem_rsp_data)
    );

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
            if ($isunknown({frame_busy, frame_done, mem_req_valid, mem_req_ready,
                            mem_req_addr, mem_rsp_valid, mem_rsp_ready,
                            out_valid, out_sof, out_eol, out_pixel})) begin
                if (errors < 20)
                    $display("FAIL: X/Z detected on a monitored interface");
                errors = errors + 1;
            end

            if (frame_busy === 1'b0 &&
                (mem_req_valid !== 1'b0 || out_valid !== 1'b0 || frame_done !== 1'b0)) begin
                if (errors < 20)
                    $display(
                        "FAIL: activity while idle req_valid=%b out_valid=%b frame_done=%b",
                        mem_req_valid, out_valid, frame_done
                    );
                errors = errors + 1;
            end else if (frame_busy !== 1'b0 && frame_busy !== 1'b1) begin
                if (errors < 20)
                    $display("FAIL: frame_busy is unknown");
                errors = errors + 1;
            end

            if (mem_req_valid && !mem_req_ready) begin
                request_stall_count = request_stall_count + 1;
                if (!waiting_for_request_accept) begin
                    waiting_for_request_accept = 1'b1;
                    stalled_request_addr = mem_req_addr;
                end else if (mem_req_addr !== stalled_request_addr) begin
                    if (errors < 20)
                        $display(
                            "FAIL: request address changed while stalled got=%0d expected=%0d",
                            mem_req_addr, stalled_request_addr
                        );
                    errors = errors + 1;
                end
            end else if (waiting_for_request_accept) begin
                if (!mem_req_valid || mem_req_addr !== stalled_request_addr) begin
                    if (errors < 20)
                        $display(
                            "FAIL: request was not held through acceptance valid=%b addr=%0d expected=%0d",
                            mem_req_valid, mem_req_addr, stalled_request_addr
                        );
                    errors = errors + 1;
                end
                if (mem_req_valid && mem_req_ready)
                    waiting_for_request_accept = 1'b0;
            end

            if (mem_req_valid && mem_req_ready && mem_req_addr >= MEMORY_WORDS) begin
                if (errors < 20)
                    $display("FAIL: DDR request address out of range: %0d", mem_req_addr);
                errors = errors + 1;
            end

            if (out_valid === 1'b1) begin
                if (output_count >= MEMORY_WORDS) begin
                    if (errors < 20)
                        $display("FAIL: extra output pixel %h", out_pixel);
                    errors = errors + 1;
                end else begin
                    expected_x = output_count % IMAGE_WIDTH;
                    expected_sof = (output_count == 0);
                    expected_eol = (expected_x == IMAGE_WIDTH - 1);
                    if (out_pixel !== golden_words[output_count]) begin
                        if (errors < 20)
                            $display(
                                "FAIL: pixel index=%0d got=%h expected=%h",
                                output_count, out_pixel, golden_words[output_count]
                            );
                        errors = errors + 1;
                    end
                    if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                        if (errors < 20)
                            $display(
                                "FAIL: controls index=%0d got sof=%b eol=%b expected sof=%b eol=%b",
                                output_count, out_sof, out_eol, expected_sof, expected_eol
                            );
                        errors = errors + 1;
                    end
                    $fdisplay(output_file, "%06h", out_pixel);
                end
                output_count = output_count + 1;
            end

            if (frame_done === 1'b1) begin
                frame_done_count = frame_done_count + 1;
                if (!out_valid || !out_eol || output_count != MEMORY_WORDS) begin
                    if (errors < 20)
                        $display(
                            "FAIL: frame_done misaligned valid=%b eol=%b count=%0d",
                            out_valid, out_eol, output_count
                        );
                    errors = errors + 1;
                end
            end
        end
    endtask

    task automatic check_reset_idle;
        begin
            if (frame_busy !== 1'b0 || frame_done !== 1'b0 ||
                mem_req_valid !== 1'b0 || mem_req_addr !== {ADDR_WIDTH{1'b0}} ||
                mem_rsp_ready !== 1'b0 || out_valid !== 1'b0 ||
                out_sof !== 1'b0 || out_eol !== 1'b0 || out_pixel !== 24'd0) begin
                if (errors < 20)
                    $display("FAIL: reset outputs are not known idle values");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh(GOLDEN_MEM_FILE, golden_words);
        output_file = $fopen(OUTPUT_MEM_FILE, "w");
        if (output_file == 0)
            $fatal(1, "cannot open output memory file: %s", OUTPUT_MEM_FILE);

        repeat (4) begin
            tick;
            check_reset_idle;
        end
        reset_n = 1'b1;
        repeat (4) begin
            tick;
            check_cycle;
        end

        @(negedge clk);
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;

        while (!frame_done && timeout < 3000000) begin
            tick;
            check_cycle;
            timeout = timeout + 1;
            if (timeout == 100)
                frame_start = 1'b1;
            if (timeout == 101) begin
                frame_start = 1'b0;
                busy_start_sent = 1'b1;
            end
        end

        if (!frame_done) begin
            $display("FAIL: frame timeout after %0d cycles", timeout);
            errors = errors + 1;
        end
        tick;
        check_cycle;
        if (frame_busy) begin
            $display("FAIL: frame_busy remained asserted after frame_done");
            errors = errors + 1;
        end
        if (output_count != MEMORY_WORDS) begin
            $display("FAIL: output count got=%0d expected=%0d", output_count, MEMORY_WORDS);
            errors = errors + 1;
        end
        if (frame_done_count != 1) begin
            $display("FAIL: frame_done pulse count got=%0d expected=1", frame_done_count);
            errors = errors + 1;
        end
        if (request_stall_count == 0) begin
            $display("FAIL: request backpressure was not exercised");
            errors = errors + 1;
        end
        if (!busy_start_sent) begin
            $display("FAIL: busy-time frame_start was not exercised");
            errors = errors + 1;
        end

        repeat (3) begin
            tick;
            check_cycle;
        end
        $fclose(output_file);

        if (errors == 0)
            $display("TEST_PASS: mes50hp_top_image outputs=%0d cycles=%0d", output_count, timeout);
        else
            $fatal(1, "TEST_FAIL: mes50hp_top_image errors=%0d", errors);
        $finish;
    end
endmodule
