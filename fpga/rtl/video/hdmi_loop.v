`timescale 1ns / 1ps

// Stage 1: forward the HDMI receiver's pixel clock and RGB/sync signals.
// The cfg_pll is the PG2L200H IP from the vendor's 4_10_timing example.
module hdmi_loop (
    input  wire       sys_clk,
    output wire       rstn_out,
    output wire       hd_scl,
    inout  wire       hd_sda,
    output wire       led_int,
    output wire       pixclk_out,
    output reg        vs_out,
    output reg        hs_out,
    output reg        de_out,
    output reg [7:0]  r_out,
    output reg [7:0]  g_out,
    output reg [7:0]  b_out,
    input  wire       pixclk_in,
    input  wire       vs_in,
    input  wire       hs_in,
    input  wire       de_in,
    input  wire [7:0] r_in,
    input  wire [7:0] g_in,
    input  wire [7:0] b_in
);

    wire cfg_clk;
    wire cfg_locked;
    wire rx_init_done;
    wire tx_init_done;
    reg [13:0] reset_count;
    reg init_reset_done;
    reg [1:0] tx_ready_sync;

    cfg_pll u_cfg_pll (
        .clkin1  (sys_clk),
        .clkout0 (cfg_clk),
        .lock    (cfg_locked)
    );

    // cfg_clk is 10 MHz; 10,000 cycles hold the HDMI chips in reset for 1 ms.
    always @(posedge cfg_clk or negedge cfg_locked) begin
        if (!cfg_locked) begin
            reset_count <= 14'd0;
            init_reset_done <= 1'b0;
        end else if (!init_reset_done) begin
            if (reset_count == 14'd9999)
                init_reset_done <= 1'b1;
            else
                reset_count <= reset_count + 1'b1;
        end
    end

    assign rstn_out = init_reset_done;

    ms72xx_ctl u_ms72xx_ctl (
        .clk          (cfg_clk),
        .rst_n        (rstn_out),
        .init_over_rx (rx_init_done),
        .init_over    (tx_init_done),
        .iic_scl      (hd_scl),
        .iic_sda      (hd_sda)
    );

    assign led_int = tx_init_done;
    assign pixclk_out = pixclk_in;

    // I2C initialization completes in cfg_clk domain. Only its stable status
    // crosses to the receiver pixel clock domain; all RGB/sync bits stay there.
    always @(posedge pixclk_in) begin
        tx_ready_sync <= {tx_ready_sync[0], tx_init_done};
        if (tx_ready_sync[1]) begin
            vs_out <= vs_in;
            hs_out <= hs_in;
            de_out <= de_in;
            r_out <= r_in;
            g_out <= g_in;
            b_out <= b_in;
        end else begin
            vs_out <= 1'b0;
            hs_out <= 1'b0;
            de_out <= 1'b0;
            r_out <= 8'd0;
            g_out <= 8'd0;
            b_out <= 8'd0;
        end
    end
endmodule
