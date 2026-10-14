`timescale 1ns/1ps

module tb_pg2l200h_board_top_compile;
    reg sys_clk = 1'b0;
    reg clk_p = 1'b0;
    wire clk_n = ~clk_p;
    reg rst_in = 1'b0;
    reg pixclk_in = 1'b0;
    reg vs_in = 1'b0;
    reg hs_in = 1'b0;
    reg de_in = 1'b0;
    reg [7:0] r_in = 8'd0;
    reg [7:0] g_in = 8'd0;
    reg [7:0] b_in = 8'd0;
    wire rstn_out, hd_scl, hd_sda, pix_clk, vs_out, hs_out, de_out;
    wire [7:0] r_out, g_out, b_out;
    wire mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_cs_n;
    wire mem_ras_n, mem_cas_n, mem_we_n, mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    wire [3:0] mem_dqs, mem_dqs_n;
    wire [31:0] mem_dq;
    wire [3:0] mem_dm;
    wire hdmi_int_led, ddr_init_done, init_over_rx, heart_beat_led;

    always #18.5 sys_clk = ~sys_clk;
    always #4 clk_p = ~clk_p;
    always #7 pixclk_in = ~pixclk_in;

    pg2l200h_board_top #(
        .IMAGE_WIDTH(32),
        .IMAGE_HEIGHT(2),
        .RESET_DELAY_CYCLES(4),
        .SIMULATION(1)
    ) dut (
        .sys_clk(sys_clk), .clk_p(clk_p), .clk_n(clk_n), .rst_in(rst_in),
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

    initial begin
        repeat (30) @(posedge sys_clk);
        if (!rstn_out || !ddr_init_done || !hdmi_int_led || !init_over_rx)
            $fatal(1, "TEST_FAIL: PG2L200H board initialization did not settle");
        if (mem_rst_n !== dut.ddr_reset_n)
            $fatal(1, "TEST_FAIL: DDR reset is not driven by the synchronized reset");
        if ($isunknown({pix_clk, vs_out, hs_out, de_out, r_out, g_out, b_out,
                        mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_cs_n,
                        mem_ras_n, mem_cas_n, mem_we_n, mem_odt, mem_a, mem_ba,
                        mem_dm, heart_beat_led}))
            $fatal(1, "TEST_FAIL: X/Z on a driven PG2L200H board output");
        $display("TEST_PASS: pg2l200h_board_top_compile");
        $finish;
    end
endmodule
