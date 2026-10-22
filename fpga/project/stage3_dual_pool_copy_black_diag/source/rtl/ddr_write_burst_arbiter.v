`timescale 1ns / 1ps

// Two Pango DDR3 write clients. Only one AW and its complete W burst may be
// active at a time. Capture uses ID 0; frame copy uses ID 1. In particular,
// the vendor capture controller generates WVALID from WREADY, so the inactive
// client's WREADY must stay low throughout the other client's burst.
module ddr_write_burst_arbiter (
    input  wire         clk,
    input  wire         rstn,
    input  wire         c0_awvalid,
    input  wire [27:0]  c0_awaddr,
    input  wire [3:0]   c0_awlen,
    output wire         c0_awready,
    input  wire         c0_wvalid,
    input  wire [255:0] c0_wdata,
    input  wire [31:0]  c0_wstrb,
    output wire         c0_wready,
    output wire         c0_wlast,
    input  wire         c1_awvalid,
    input  wire [27:0]  c1_awaddr,
    input  wire [3:0]   c1_awlen,
    output wire         c1_awready,
    input  wire         c1_wvalid,
    input  wire [255:0] c1_wdata,
    input  wire [31:0]  c1_wstrb,
    output wire         c1_wready,
    output wire         c1_wlast,
    output wire [27:0]  axi_awaddr,
    output wire [3:0]   axi_awid,
    output wire [3:0]   axi_awlen,
    output wire         axi_awvalid,
    input  wire         axi_awready,
    output wire [255:0] axi_wdata,
    output wire [31:0]  axi_wstrb,
    output wire         axi_wvalid,
    input  wire         axi_wready,
    input  wire         axi_wlast,
    input  wire [3:0]   axi_wusero_id,
    output reg          busy,
    output reg  [15:0]  protocol_error_count,
    output reg          protocol_fault
);
    reg owner;
    reg prefer_c1;
    reg held_aw;
    reg held_owner;
    reg [27:0] held_addr;
    reg [3:0] held_len;
    reg [4:0] beats_left;

    wire grant_c1 = c1_awvalid && (!c0_awvalid || prefer_c1);
    wire selected_owner = held_aw ? held_owner : grant_c1;
    wire [27:0] selected_addr = held_aw ? held_addr :
                                (grant_c1 ? c1_awaddr : c0_awaddr);
    wire [3:0] selected_len = held_aw ? held_len :
                              (grant_c1 ? c1_awlen : c0_awlen);
    wire aw_accept = axi_awvalid && axi_awready;
    wire w_transfer = busy && axi_wready && axi_wvalid;
    wire w_complete = busy && axi_wready && axi_wlast;
    wire w_fault = (axi_wready && axi_wlast && !busy) ||
                   (busy && axi_wready && !axi_wvalid) ||
                   (w_transfer && (axi_wlast != (beats_left == 5'd1) ||
                                    axi_wusero_id != {3'd0, owner}));

    assign axi_awvalid = rstn && !busy && !protocol_fault &&
                         (held_aw || c0_awvalid || c1_awvalid);
    assign axi_awaddr = selected_addr;
    assign axi_awid = {3'd0, selected_owner};
    assign axi_awlen = selected_len;
    assign c0_awready = aw_accept && !selected_owner;
    assign c1_awready = aw_accept && selected_owner;
    assign c0_wready = rstn && busy && !owner && axi_wready;
    assign c1_wready = rstn && busy && owner && axi_wready;
    assign c0_wlast = c0_wready && axi_wlast;
    assign c1_wlast = c1_wready && axi_wlast;
    assign axi_wdata = owner ? c1_wdata : c0_wdata;
    assign axi_wstrb = owner ? c1_wstrb : c0_wstrb;
    assign axi_wvalid = rstn && busy && (owner ? c1_wvalid : c0_wvalid);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            owner <= 1'b0;
            prefer_c1 <= 1'b0;
            held_aw <= 1'b0;
            held_owner <= 1'b0;
            held_addr <= 28'd0;
            held_len <= 4'd0;
            beats_left <= 5'd0;
            busy <= 1'b0;
            protocol_error_count <= 16'd0;
            protocol_fault <= 1'b0;
        end else begin
            if (axi_awvalid && !axi_awready && !held_aw) begin
                held_aw <= 1'b1;
                held_owner <= selected_owner;
                held_addr <= selected_addr;
                held_len <= selected_len;
            end
            if (aw_accept) begin
                held_aw <= 1'b0;
                owner <= selected_owner;
                prefer_c1 <= !selected_owner;
                beats_left <= {1'b0, selected_len} + 5'd1;
                busy <= 1'b1;
            end
            if (w_transfer && beats_left != 5'd0)
                beats_left <= beats_left - 1'b1;
            if (w_complete) begin
                busy <= 1'b0;
                beats_left <= 5'd0;
            end
            if (w_fault) begin
                protocol_fault <= 1'b1;
                if (protocol_error_count != 16'hffff)
                    protocol_error_count <= protocol_error_count + 1'b1;
            end
        end
    end
endmodule
