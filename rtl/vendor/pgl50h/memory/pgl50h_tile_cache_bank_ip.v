//////////////////////////////////////////////////////////////////////////////
// PGL50H implementation of one parameterized depth x 128 Tile Cache bank.
// The underlying ipml_sdpram source is already imported by the PDS project
// through rtl/vendor/pgl50h/ddr/rd_fram_buf/rd_fram_buf.idf.
//////////////////////////////////////////////////////////////////////////////
module pgl50h_tile_cache_bank_ip #(
    parameter integer ADDR_WIDTH = 11
) (
    input  wire [127:0] wr_data,
    input  wire [ADDR_WIDTH-1:0]  wr_addr,
    input  wire         wr_en,
    input  wire         wr_clk,
    input  wire         wr_clk_en,
    input  wire         wr_rst,
    input  wire [3:0]   wr_byte_en,
    input  wire         wr_addr_strobe,
    output wire [127:0] rd_data,
    input  wire [ADDR_WIDTH-1:0]  rd_addr,
    input  wire         rd_clk,
    input  wire         rd_clk_en,
    input  wire         rd_rst,
    input  wire         rd_oce,
    input  wire         rd_addr_strobe
);
    ipml_sdpram_v1_6_rd_fram_buf #(
        .c_SIM_DEVICE("LOGOS"),
        .c_WR_ADDR_WIDTH(ADDR_WIDTH),
        .c_WR_DATA_WIDTH(128),
        .c_RD_ADDR_WIDTH(ADDR_WIDTH),
        .c_RD_DATA_WIDTH(128),
        .c_OUTPUT_REG(1),
        .c_RD_OCE_EN(1),
        .c_WR_ADDR_STROBE_EN(0),
        .c_RD_ADDR_STROBE_EN(0),
        .c_WR_CLK_EN(1),
        .c_RD_CLK_EN(1),
        .c_RD_CLK_OR_POL_INV(0),
        .c_RESET_TYPE("ASYNC_RESET"),
        .c_POWER_OPT(0),
        .c_INIT_FILE("NONE"),
        .c_INIT_FORMAT("BIN"),
        .c_WR_BYTE_EN(0),
        .c_BE_WIDTH(4)
    ) impl (
        .wr_data(wr_data),
        .wr_addr(wr_addr),
        .wr_en(wr_en),
        .wr_clk(wr_clk),
        .wr_clk_en(wr_clk_en),
        .wr_rst(wr_rst),
        .wr_byte_en(wr_byte_en),
        .wr_addr_strobe(wr_addr_strobe),
        .rd_data(rd_data),
        .rd_addr(rd_addr),
        .rd_clk(rd_clk),
        .rd_clk_en(rd_clk_en),
        .rd_rst(rd_rst),
        .rd_oce(rd_oce),
        .rd_addr_strobe(rd_addr_strobe)
    );
endmodule
