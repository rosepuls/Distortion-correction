`timescale 1ns / 1ps

// Two-client burst arbiter for the Pango DDR3 read interface. The DDR IP has
// no RREADY input, so each client must reserve (ARLEN+1) 256-bit sink entries
// before asserting reserve. Exactly one burst may be outstanding; its owner
// remains fixed until RLAST. Addresses are DDR 32-bit-word addresses.
module ddr_read_burst_arbiter (
    input  wire         clk,
    input  wire         rstn,

    input  wire         c0_valid,
    input  wire [27:0]  c0_addr,
    input  wire [3:0]   c0_len,
    input  wire         c0_reserve,
    output wire         c0_ready,
    output wire         c0_rvalid,
    output wire [255:0] c0_rdata,
    output wire         c0_rlast,

    input  wire         c1_valid,
    input  wire [27:0]  c1_addr,
    input  wire [3:0]   c1_len,
    input  wire         c1_reserve,
    output wire         c1_ready,
    output wire         c1_rvalid,
    output wire [255:0] c1_rdata,
    output wire         c1_rlast,

    output wire [27:0]  axi_araddr,
    output wire [3:0]   axi_arid,
    output wire [3:0]   axi_arlen,
    output wire         axi_arvalid,
    input  wire         axi_arready,
    input  wire [255:0] axi_rdata,
    input  wire         axi_rvalid,
    input  wire         axi_rlast,
    input  wire [3:0]   axi_rid,

    output reg          busy,
    output reg  [15:0]  response_error_count
);
    reg owner;
    reg prefer_c1;
    reg [4:0] beats_remaining;
    reg held_ar;
    reg held_owner;
    reg [27:0] held_addr;
    reg [3:0] held_len;

    wire eligible0 = c0_valid && c0_reserve;
    wire eligible1 = c1_valid && c1_reserve;
    wire grant_c1 = eligible1 && (!eligible0 || prefer_c1);
    wire selected_owner = held_ar ? held_owner : grant_c1;
    wire [27:0] selected_addr = held_ar ? held_addr :
                                (grant_c1 ? c1_addr : c0_addr);
    wire [3:0] grant_len = held_ar ? held_len :
                           (grant_c1 ? c1_len : c0_len);
    wire [4:0] grant_beats = {1'b0, grant_len} + 5'd1;
    wire ar_accept = axi_arvalid && axi_arready;
    wire response_owned = busy || ar_accept;
    wire response_owner = busy ? owner : selected_owner;
    wire rid_match = (axi_rid == {3'd0, response_owner});
    wire response_fault = axi_rvalid &&
        (!response_owned ||
         !rid_match ||
         (axi_rlast != ((busy ? beats_remaining : grant_beats) == 5'd1)));

    assign axi_arvalid = rstn && !busy && (held_ar || eligible0 || eligible1);
    assign axi_araddr = selected_addr;
    assign axi_arid = {3'd0, selected_owner};
    assign axi_arlen = grant_len;
    assign c0_ready = ar_accept && !selected_owner;
    assign c1_ready = ar_accept && selected_owner;
    assign c0_rvalid = axi_rvalid && response_owned && rid_match && !response_owner;
    assign c1_rvalid = axi_rvalid && response_owned && rid_match && response_owner;
    assign c0_rdata = axi_rdata;
    assign c1_rdata = axi_rdata;
    assign c0_rlast = c0_rvalid && axi_rlast;
    assign c1_rlast = c1_rvalid && axi_rlast;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            busy <= 1'b0;
            owner <= 1'b0;
            prefer_c1 <= 1'b0;
            beats_remaining <= 5'd0;
            held_ar <= 1'b0;
            held_owner <= 1'b0;
            held_addr <= 28'd0;
            held_len <= 4'd0;
            response_error_count <= 16'd0;
        end else begin
            if (axi_arvalid && !axi_arready && !held_ar) begin
                held_ar <= 1'b1;
                held_owner <= selected_owner;
                held_addr <= selected_addr;
                held_len <= grant_len;
            end
            if (ar_accept) begin
                held_ar <= 1'b0;
                owner <= selected_owner;
                prefer_c1 <= !selected_owner;
                busy <= 1'b1;
                beats_remaining <= grant_beats;
            end

            if (axi_rvalid && response_owned) begin
                if (axi_rlast) begin
                    busy <= 1'b0;
                    beats_remaining <= 5'd0;
                end else if (busy) begin
                    if (beats_remaining != 5'd0)
                        beats_remaining <= beats_remaining - 5'd1;
                end else begin
                    beats_remaining <= grant_beats - 5'd1;
                end
            end

            if (response_fault && response_error_count != 16'hffff)
                response_error_count <= response_error_count + 16'd1;
        end
    end
endmodule
