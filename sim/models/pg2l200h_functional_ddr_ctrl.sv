`timescale 1ns/1ps

// Functional command-side DDR model for board data-path regressions.
// This models the controller's burst protocol and storage, not the PG2L200H
// PHY calibration, electrical timing, or AXI implementation.
module wr_rd_ctrl_top #(
    parameter CTRL_ADDR_WIDTH=28,
    parameter MEM_DQ_WIDTH=32
) (
    input wire clk, input wire rstn,
    input wire wr_cmd_en, input wire [CTRL_ADDR_WIDTH-1:0] wr_cmd_addr,
    input wire [31:0] wr_cmd_len, output wire wr_cmd_ready, output reg wr_cmd_done,
    output wire wr_bac, input wire [MEM_DQ_WIDTH*8-1:0] wr_ctrl_data,
    output wire wr_data_re,
    input wire rd_cmd_en, input wire [CTRL_ADDR_WIDTH-1:0] rd_cmd_addr,
    input wire [31:0] rd_cmd_len, output wire rd_cmd_ready, output reg rd_cmd_done,
    input wire read_ready, output wire [MEM_DQ_WIDTH*8-1:0] read_rdata,
    output wire read_en,
    output wire [CTRL_ADDR_WIDTH-1:0] axi_awaddr, output wire [3:0] axi_awid,
    output wire [3:0] axi_awlen, output wire [2:0] axi_awsize,
    output wire [1:0] axi_awburst, input wire axi_awready, output wire axi_awvalid,
    output wire [MEM_DQ_WIDTH*8-1:0] axi_wdata,
    output wire [MEM_DQ_WIDTH-1:0] axi_wstrb, input wire axi_wlast,
    output wire axi_wvalid, input wire axi_wready, input wire [3:0] axi_bid,
    input wire [1:0] axi_bresp, input wire axi_bvalid, output wire axi_bready,
    output wire [CTRL_ADDR_WIDTH-1:0] axi_araddr, output wire [3:0] axi_arid,
    output wire [3:0] axi_arlen, output wire [2:0] axi_arsize,
    output wire [1:0] axi_arburst, output wire axi_arvalid, input wire axi_arready,
    output wire axi_rready, input wire [MEM_DQ_WIDTH*8-1:0] axi_rdata,
    input wire axi_rvalid, input wire axi_rlast, input wire [3:0] axi_rid,
    input wire [1:0] axi_rresp
);
    localparam integer BEAT_W = 16;
    localparam integer WORDS_W = BEAT_W + 3;
    localparam integer MEM_WORDS = 32768;
    localparam [1:0] IDLE=2'd0, WRITE=2'd1, READ=2'd2;

    reg [1:0] state;
    reg [CTRL_ADDR_WIDTH-1:0] active_addr;
    reg [31:0] beats_left;
    reg [2:0] stall_phase;
    reg [31:0] memory [0:MEM_WORDS-1];
    reg [MEM_DQ_WIDTH*8-1:0] read_data_reg;
    integer lane;
    integer mem_index;
    integer unknown_write_words = 0;
    integer unknown_read_words = 0;
    integer first_unknown_write_addr = -1;
    integer first_unknown_read_addr = -1;

    function integer address_index(input [CTRL_ADDR_WIDTH-1:0] word_addr);
        reg [1:0] region;
        reg [11:0] low_word;
        begin
            region = word_addr[23:22];
            low_word = word_addr[11:0];
            address_index = region * 8192 + low_word;
        end
    endfunction

    assign wr_cmd_ready = (state == IDLE);
    assign rd_cmd_ready = (state == IDLE);
    assign wr_data_re = (state == WRITE) && (stall_phase[1:0] != 2'b00);
    assign wr_bac = 1'b0;
    assign read_en = (state == READ) && read_ready && (stall_phase[1:0] != 2'b00);
    assign read_rdata = read_data_reg;

    assign axi_awaddr='0; assign axi_awid='0; assign axi_awlen='0;
    assign axi_awsize='0; assign axi_awburst='0; assign axi_awvalid=1'b0;
    assign axi_wdata='0; assign axi_wstrb='0; assign axi_wvalid=1'b0;
    assign axi_bready=1'b1; assign axi_araddr='0; assign axi_arid='0;
    assign axi_arlen='0; assign axi_arsize='0; assign axi_arburst='0;
    assign axi_arvalid=1'b0; assign axi_rready=1'b0;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            active_addr <= 0;
            beats_left <= 0;
            stall_phase <= 0;
            wr_cmd_done <= 0;
            rd_cmd_done <= 0;
            read_data_reg <= 0;
        end else begin
            wr_cmd_done <= 0;
            rd_cmd_done <= 0;
            stall_phase <= stall_phase + 1'b1;

            if (state == IDLE) begin
                if (wr_cmd_en && wr_cmd_ready && (wr_cmd_len != 0)) begin
                    state <= WRITE;
                    active_addr <= wr_cmd_addr;
                    beats_left <= wr_cmd_len;
                    stall_phase <= 0;
                end else if (rd_cmd_en && rd_cmd_ready && (rd_cmd_len != 0)) begin
                    state <= READ;
                    active_addr <= rd_cmd_addr;
                    beats_left <= rd_cmd_len;
                    stall_phase <= 0;
                end
            end else if ((stall_phase[1:0] != 2'b00) && (state == WRITE)) begin
                if (wr_data_re) begin
                    for (lane = 0; lane < 8; lane = lane + 1) begin
                        mem_index = address_index(active_addr) + lane;
                        if ($isunknown(wr_ctrl_data[lane*32 +: 32])) begin
                            unknown_write_words = unknown_write_words + 1;
                            if (first_unknown_write_addr < 0)
                                first_unknown_write_addr = active_addr + lane;
                        end
                        if ((mem_index >= 0) && (mem_index < MEM_WORDS))
                            memory[mem_index] <= wr_ctrl_data[lane*32 +: 32];
                    end
                    active_addr <= active_addr + 8;
                    if (beats_left == 1) begin
                        beats_left <= 0;
                        state <= IDLE;
                        wr_cmd_done <= 1'b1;
                    end else
                        beats_left <= beats_left - 1'b1;
                end
            end else if ((state == READ) && read_ready && (stall_phase[1:0] != 2'b00)) begin
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    mem_index = address_index(active_addr) + lane;
                    if ((mem_index >= 0) && (mem_index < MEM_WORDS)) begin
                        if ($isunknown(memory[mem_index])) begin
                            unknown_read_words = unknown_read_words + 1;
                            if (first_unknown_read_addr < 0)
                                first_unknown_read_addr = active_addr + lane;
                        end
                        read_data_reg[lane*32 +: 32] <= memory[mem_index];
                    end else
                        read_data_reg[lane*32 +: 32] <= 32'd0;
                end
                active_addr <= active_addr + 8;
                if (beats_left == 1) begin
                    beats_left <= 0;
                    state <= IDLE;
                    rd_cmd_done <= 1'b1;
                end else
                    beats_left <= beats_left - 1'b1;
            end
        end
    end
endmodule
