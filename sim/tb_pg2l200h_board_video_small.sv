`timescale 1ns/1ps

module tb_pg2l200h_board_video_small;
    localparam integer IMAGE_WIDTH = 32;
    localparam integer IMAGE_HEIGHT = 16;

    reg sys_clk = 1'b0;
    reg ddr_ref_clk = 1'b0;
    reg rst_in = 1'b0;
    reg pixclk_in = 1'b0;
    reg vs_in = 1'b0;
    reg hs_in = 1'b0;
    reg de_in = 1'b0;
    reg [7:0] r_in = 8'd0;
    reg [7:0] g_in = 8'd0;
    reg [7:0] b_in = 8'd0;

    wire clk_n = ~ddr_ref_clk;
    wire rstn_out, hd_scl, hd_sda;
    wire pix_clk, vs_out, hs_out, de_out;
    wire [7:0] r_out, g_out, b_out;
    wire mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_cs_n;
    wire mem_ras_n, mem_cas_n, mem_we_n, mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    wire [3:0] mem_dqs, mem_dqs_n, mem_dm;
    wire [31:0] mem_dq;
    wire hdmi_int_led, ddr_init_done, init_over_rx, heart_beat_led;

    integer frame_starts = 0;
    integer output_completes = 0;
    integer algorithm_pixels = 0;
    integer algorithm_unknown_pixels = 0;
    integer cycles = 0;
    integer errors = 0;

    always #18.5 sys_clk = ~sys_clk;
    always #4 ddr_ref_clk = ~ddr_ref_clk;
    always #6.5 pixclk_in = ~pixclk_in;

    pg2l200h_board_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .VIDEO_H_TOTAL(48), .VIDEO_H_SYNC(4), .VIDEO_H_BACK(4),
        .VIDEO_H_ACTIVE(IMAGE_WIDTH), .VIDEO_H_FRONT(8),
        .VIDEO_V_TOTAL(24), .VIDEO_V_SYNC(2), .VIDEO_V_BACK(2),
        .VIDEO_V_ACTIVE(IMAGE_HEIGHT), .VIDEO_V_FRONT(4),
        .RESET_DELAY_CYCLES(4),
        .SIMULATION(1),
        .CFG_FX_Q19(32'sd524288),
        .CFG_FY_Q19(32'sd524288),
        .CFG_CX_Q19(32'sd0),
        .CFG_CY_Q19(32'sd0),
        .CFG_INV_FX_Q30(32'sd1073741824),
        .CFG_INV_FY_Q30(32'sd1073741824)
    ) dut (
        .sys_clk(sys_clk), .clk_p(ddr_ref_clk), .clk_n(clk_n), .rst_in(rst_in),
        .rstn_out(rstn_out), .hd_scl(hd_scl), .hd_sda(hd_sda),
        .pixclk_in(pixclk_in), .vs_in(vs_in), .hs_in(hs_in), .de_in(de_in),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .pix_clk(pix_clk), .vs_out(vs_out), .hs_out(hs_out), .de_out(de_out),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n),
        .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm),
        .hdmi_int_led(hdmi_int_led), .ddr_init_done(ddr_init_done),
        .init_over_rx(init_over_rx), .heart_beat_led(heart_beat_led)
    );

    always @(posedge dut.core_clk) begin
        if (dut.algo_frame_start)
            frame_starts = frame_starts + 1;
        if (dut.algo_out_valid && $isunknown(dut.algo_out_pixel))
            algorithm_unknown_pixels = algorithm_unknown_pixels + 1;
        if (dut.algo_out_valid)
            algorithm_pixels = algorithm_pixels + 1;
        if (dut.output_frame_complete)
            output_completes = output_completes + 1;
    end

    task automatic start_frame;
        begin
            @(negedge pixclk_in);
            vs_in = 1'b1;
            repeat (2) @(negedge pixclk_in);
            vs_in = 1'b0;
        end
    endtask

    task automatic send_active_frame(input integer frame_id);
        integer x;
        integer y;
        begin
            start_frame();
            for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    @(negedge pixclk_in);
                    de_in = 1'b1;
                    r_in = x + frame_id * 32;
                    g_in = y + frame_id * 64;
                    b_in = x ^ y ^ frame_id;
                end
                @(negedge pixclk_in);
                de_in = 1'b0;
                repeat (2) @(negedge pixclk_in);
            end
        end
    endtask

    initial begin
        repeat (20) @(posedge sys_clk);
        if (!rstn_out || !ddr_init_done || !hdmi_int_led)
            $fatal(1, "TEST_FAIL: board initialization did not settle");

        wait (dut.capture_enable);
        send_active_frame(0);
        send_active_frame(1);

        while (frame_starts == 0 && cycles < 100000)
            @(posedge dut.core_clk);
        if (frame_starts != 1)
            $fatal(1, "TEST_FAIL: completed capture did not start processing");

        cycles = 0;
        while (output_completes == 0 && cycles < 1000000) begin
            @(posedge dut.core_clk);
            cycles = cycles + 1;
        end
        if (output_completes == 0)
            $fatal(1, "TEST_FAIL: output frame did not complete through DDR data path");
        $display("TEST_SCOPE: control-only; WIDTH=32 is below wr_buf's 20-pixel prefetch margin; pixel X is diagnostic, not a data-integrity verdict");
        $display("XDIAG algo_pixels=%0d algo_unknown=%0d ddr_unknown_reads=%0d first_read_addr=%0d ddr_unknown_writes=%0d first_write_addr=%0d", algorithm_pixels, algorithm_unknown_pixels, dut.memory_command_controller.unknown_read_words, dut.memory_command_controller.first_unknown_read_addr, dut.memory_command_controller.unknown_write_words, dut.memory_command_controller.first_unknown_write_addr);
        // This tiny-frame integration test checks control/frame completion.
        // Its DDR model intentionally leaves untouched frame-buffer regions
        // unknown, and the vendor wr_buf's fixed 20-pixel prefetch is not
        // representative at IMAGE_WIDTH=32. Pixel integrity is covered by
        // the dedicated 1280-pixel wr_buf capture test.
        if (dut.output_writer_overflow || dut.display_underflow)
            $fatal(1, "TEST_FAIL: board video path reported overflow or underflow");

        $display("TEST_PASS: pg2l200h_board_video_small control_cycles=%0d input_starts=%0d output_frames=%0d", cycles, frame_starts, output_completes);
        $finish;
    end
endmodule
