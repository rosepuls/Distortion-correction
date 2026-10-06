`timescale 1ns/1ps

module tb_pgl50h_board_top_compile;
    reg sys_clk = 1'b0;
    reg pixclk_in = 1'b0;
    reg vs_in = 1'b0;
    reg hs_in = 1'b0;
    reg de_in = 1'b0;
    reg [7:0] r_in = 8'd0;
    reg [7:0] g_in = 8'd0;
    reg [7:0] b_in = 8'd0;
    wire rstn_out, iic_scl, iic_sda, iic_tx_scl, iic_tx_sda;
    wire pixclk_out, vs_out, hs_out, de_out;
    wire [7:0] r_out, g_out, b_out;
    wire mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_cs_n;
    wire mem_ras_n, mem_cas_n, mem_we_n, mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    wire [3:0] mem_dqs, mem_dqs_n;
    wire [31:0] mem_dq;
    wire [3:0] mem_dm;
    wire hdmi_int_led, ddr_init_done, heart_beat_led;
    integer input_reset_hold_edges = 0;
    integer core_reset_hold_edges = 0;
    integer video_reset_hold_edges = 0;
    integer ddr_reset_hold_edges = 0;
    integer process_start_count = 0;

    always #10 sys_clk = ~sys_clk;
    always #7 pixclk_in = ~pixclk_in;

    // The board reset request is generated in cfg_clk.  Each foreign domain
    // must see two local edges with reset asserted before its reset releases.
    always @(posedge pixclk_in) begin
        if (!rstn_out)
            input_reset_hold_edges = 0;
        else if (!dut.input_rst_n)
            input_reset_hold_edges = input_reset_hold_edges + 1;
    end
    always @(posedge dut.core_clk) begin
        if (!dut.core_reset_request_n)
            core_reset_hold_edges = 0;
        else if (!dut.core_rst_n)
            core_reset_hold_edges = core_reset_hold_edges + 1;
    end
    always @(posedge dut.video_pixel_clk) begin
        if (!rstn_out)
            video_reset_hold_edges = 0;
        else if (!dut.video_rst_n)
            video_reset_hold_edges = video_reset_hold_edges + 1;
    end
    always @(posedge sys_clk) begin
        if (!rstn_out)
            ddr_reset_hold_edges = 0;
        else if (!dut.ddr_reset_n)
            ddr_reset_hold_edges = ddr_reset_hold_edges + 1;
    end
    always @(posedge dut.core_clk) begin
        if (dut.algo_frame_start)
            process_start_count = process_start_count + 1;
    end

    pgl50h_board_top #(
        .IMAGE_WIDTH(32),
        .IMAGE_HEIGHT(2),
        .RESET_DELAY_CYCLES(4),
        .SIMULATION(1)
    ) dut (
        .sys_clk(sys_clk), .rstn_out(rstn_out),
        .iic_scl(iic_scl), .iic_sda(iic_sda),
        .iic_tx_scl(iic_tx_scl), .iic_tx_sda(iic_tx_sda),
        .pixclk_in(pixclk_in), .vs_in(vs_in), .hs_in(hs_in), .de_in(de_in),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .pixclk_out(pixclk_out), .vs_out(vs_out), .hs_out(hs_out), .de_out(de_out),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n),
        .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm),
        .hdmi_int_led(hdmi_int_led), .ddr_init_done(ddr_init_done),
        .heart_beat_led(heart_beat_led)
    );

    initial begin
        repeat (30) @(posedge sys_clk);
        if (!rstn_out || !ddr_init_done || !hdmi_int_led)
            $fatal(1, "TEST_FAIL: board initialization outputs did not settle");
        if (!dut.input_rst_n || !dut.core_rst_n || !dut.video_rst_n
            || !dut.ddr_reset_n)
            $fatal(1, "TEST_FAIL: a synchronized board reset did not release");
        if (input_reset_hold_edges != 2 || core_reset_hold_edges != 2 ||
            video_reset_hold_edges != 2 || ddr_reset_hold_edges != 2)
            $fatal(1,
                   "TEST_FAIL: reset release edges input=%0d core=%0d video=%0d ddr=%0d expected=2",
                   input_reset_hold_edges, core_reset_hold_edges,
                   video_reset_hold_edges, ddr_reset_hold_edges);
        if (mem_rst_n !== dut.ddr_reset_n)
            $fatal(1, "TEST_FAIL: DDR controller reset is not driven by ddr_reset_n");
        if ($isunknown({pixclk_out,vs_out,hs_out,de_out,r_out,g_out,b_out,
                        mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_cs_n,mem_ras_n,
                        mem_cas_n,mem_we_n,mem_odt,mem_a,mem_ba,mem_dm,
                        heart_beat_led})) begin
            $display("DIAG video=%b %b %b %b rgb=%h_%h_%h",
                     pixclk_out,vs_out,hs_out,de_out,r_out,g_out,b_out);
            $display("DIAG ddr ctl=%b%b%b%b%b%b%b%b%b a=%h ba=%h dm=%h heartbeat=%b",
                     mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_cs_n,mem_ras_n,
                     mem_cas_n,mem_we_n,mem_odt,mem_a,mem_ba,mem_dm,heart_beat_led);
            $fatal(1, "TEST_FAIL: X/Z on driven board outputs");
        end

        // Two completed input frames must launch two separate jobs.  The
        // first job is explicitly completed before the second arrives so this
        // checks continuous operation rather than the scheduler overrun flag.
        force dut.input_frame_complete = 1'b1;
        @(posedge dut.core_clk);
        #1;
        release dut.input_frame_complete;
        repeat (2) @(posedge dut.core_clk);
        if (process_start_count != 1 || !dut.process_enable)
            $fatal(1, "TEST_FAIL: first captured frame did not start processing");
        force dut.algo_frame_done = 1'b1;
        force dut.output_frame_complete = 1'b1;
        @(posedge dut.core_clk);
        #1;
        release dut.algo_frame_done;
        release dut.output_frame_complete;
        repeat (2) @(posedge dut.core_clk);
        if (dut.process_enable || !dut.display_enable)
            $fatal(1, "TEST_FAIL: completed first frame did not enable display");
        force dut.input_frame_complete = 1'b1;
        @(posedge dut.core_clk);
        #1;
        release dut.input_frame_complete;
        repeat (2) @(posedge dut.core_clk);
        if (process_start_count != 2 || !dut.process_enable || !dut.display_enable)
            $fatal(1, "TEST_FAIL: continuous second frame did not process while display stayed enabled");
        // The throughput path must enter the board through the Tile Cache
        // command port, retain byte addressing in the portable core, then
        // convert to the official controller's 32-bit-word address here.
        force dut.input_frame_base = 28'h0200000;
        force dut.cache_rd_cmd_en = 1'b1;
        force dut.cache_rd_cmd_addr = 32'h0000_0080;
        force dut.cache_rd_cmd_len = 32'd4;
        #1;
        if (dut.cache_ctrl_cmd_addr !== 28'h0200020 ||
            dut.cache_ctrl_cmd_len !== 32'd4) begin
            $fatal(1, "TEST_FAIL: board cache adapter address/length mismatch");
        end
        release dut.cache_rd_cmd_en;
        release dut.cache_rd_cmd_addr;
        release dut.cache_rd_cmd_len;
        release dut.input_frame_base;
        $display("TEST_PASS: pgl50h_board_top_compile");
        $finish;
    end
endmodule
