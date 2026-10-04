`timescale 1ns/1ps

// Converts the algorithm's RGB888 pixel-address requests into one-beat reads
// accepted by the official MES50HP wr_rd_ctrl_top read-command interface.
// DDR command addresses are 32-bit-word addresses.  Every returned 256-bit
// beat starts at rd_cmd_addr * 4 bytes, so the requested RGB888 field begins
// at one of byte offsets 0, 1, 2, or 3.
module ddr3_pixel_read_adapter #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DDR_ADDR_WIDTH = 28
) (
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire                      mem_req_valid,
    output wire                      mem_req_ready,
    input  wire [ADDR_WIDTH-1:0]     mem_req_addr,
    input  wire [DDR_ADDR_WIDTH-1:0] frame_base_addr,
    output reg                       mem_rsp_valid,
    input  wire                      mem_rsp_ready,
    output reg  [23:0]               mem_rsp_data,

    output wire                      rd_cmd_en,
    output reg  [DDR_ADDR_WIDTH-1:0] rd_cmd_addr,
    output wire [31:0]               rd_cmd_len,
    input  wire                      rd_cmd_ready,
    input  wire                      rd_cmd_done,
    input  wire [255:0]              rd_data,
    input  wire                      rd_data_valid,
    output wire                      rd_data_ready
);
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_ISSUE = 2'd1;
    localparam [1:0] STATE_WAIT_DATA = 2'd2;
    localparam [1:0] STATE_RESPOND = 2'd3;

    reg [1:0] state;
    reg [1:0] requested_byte_offset;
    wire [ADDR_WIDTH:0] requested_byte_address;

    // RGB888 uses three consecutive bytes for each logical pixel address.
    assign requested_byte_address = {mem_req_addr, 1'b0} + mem_req_addr;
    assign mem_req_ready = (state == STATE_IDLE);
    assign rd_cmd_en = (state == STATE_ISSUE);
    assign rd_cmd_len = 32'd1;
    assign rd_data_ready = (state == STATE_WAIT_DATA);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            requested_byte_offset <= 2'd0;
            rd_cmd_addr <= {DDR_ADDR_WIDTH{1'b0}};
            mem_rsp_valid <= 1'b0;
            mem_rsp_data <= 24'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    mem_rsp_valid <= 1'b0;
                    if (mem_req_valid) begin
                        // (pixel_index * 3) modulo four selects the byte
                        // position within the returned 32-bit-word-aligned beat.
                        requested_byte_offset <= requested_byte_address[1:0];
                        rd_cmd_addr <= frame_base_addr +
                                       requested_byte_address[DDR_ADDR_WIDTH+1:2];
                        state <= STATE_ISSUE;
                    end
                end

                STATE_ISSUE: begin
                    if (rd_cmd_ready)
                        state <= STATE_WAIT_DATA;
                end

                STATE_WAIT_DATA: begin
                    if (rd_data_valid) begin
                        mem_rsp_data <= rd_data[(requested_byte_offset * 8) +: 24];
                        mem_rsp_valid <= 1'b1;
                        state <= STATE_RESPOND;
                    end
                end

                STATE_RESPOND: begin
                    if (mem_rsp_valid && mem_rsp_ready) begin
                        mem_rsp_valid <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    mem_rsp_valid <= 1'b0;
                end
            endcase
        end
    end

    // rd_cmd_done is supplied by the official controller for diagnostics and
    // command sequencing. Data validity, not completion timing, gates replies.
    wire unused_rd_cmd_done = rd_cmd_done;
endmodule
