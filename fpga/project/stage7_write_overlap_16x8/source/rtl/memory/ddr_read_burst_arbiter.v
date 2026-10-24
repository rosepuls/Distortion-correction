`timescale 1ns / 1ps

// Two-client DDR read arbiter. Display client 0 keeps one outstanding burst;
// transform client 1 may queue the four rows of its current tile. AXI preserves
// response order for a given ID, so each client uses one stable ID while R
// beats from IDs 0 and 1 may interleave. Client 1 reserves a complete 16-beat
// tile buffer before it starts issuing its four four-beat row bursts.
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

    output wire         busy,
    output reg  [15:0]  response_error_count,
    output wire         c1_wait_arbiter,
    output wire         c1_wait_arready
);
    localparam [2:0] C1_MAX_OUTSTANDING = 3'd4;

    reg c0_outstanding;
    reg [2:0] c1_outstanding;
    reg c0_response_active;
    reg c1_response_active;
    reg [4:0] c0_beats_remaining;
    reg [2:0] c1_beats_remaining;
    reg prefer_c1;
    reg held_ar;
    reg held_owner;
    reg [27:0] held_addr;
    reg [3:0] held_len;

    wire eligible0 = c0_valid && c0_reserve && !c0_outstanding;
    wire eligible1 = c1_valid && c1_reserve &&
                     (c1_outstanding < C1_MAX_OUTSTANDING);
    wire grant_c1 = eligible1 && (!eligible0 || prefer_c1);
    wire selected_owner = held_ar ? held_owner : grant_c1;
    wire [27:0] selected_addr = held_ar ? held_addr :
                                (grant_c1 ? c1_addr : c0_addr);
    wire [3:0] grant_len = held_ar ? held_len :
                           (grant_c1 ? c1_len : c0_len);
    wire [4:0] grant_beats = {1'b0, grant_len} + 5'd1;
    wire ar_accept = axi_arvalid && axi_arready;
    wire c0_ar_accept = ar_accept && !selected_owner;
    wire c1_ar_accept = ar_accept && selected_owner;
    wire rid_is_c0 = (axi_rid == 4'd0);
    wire rid_is_c1 = (axi_rid == 4'd1);
    wire c0_has_owner = c0_outstanding || c0_ar_accept;
    wire c1_has_owner = (c1_outstanding != 3'd0) || c1_ar_accept;
    wire c0_response_fire = axi_rvalid && rid_is_c0 && c0_has_owner;
    wire c1_response_fire = axi_rvalid && rid_is_c1 && c1_has_owner;
    wire c0_expected_last = c0_response_active ?
                            (c0_beats_remaining == 5'd1) :
                            (c0_ar_accept && grant_beats == 5'd1);
    // Transform row requests are fixed four-beat bursts and retain ID 1.
    // AXI returns same-ID bursts in issue order, so this counter validates the
    // current response without storing per-request tags.
    wire c1_expected_last = c1_response_active ?
                            (c1_beats_remaining == 3'd1) : 1'b0;
    wire response_fault = axi_rvalid &&
        ((!rid_is_c0 && !rid_is_c1) ||
         (rid_is_c0 && (!c0_has_owner ||
                        axi_rlast != c0_expected_last)) ||
         (rid_is_c1 && (!c1_has_owner ||
                        axi_rlast != c1_expected_last)));

    assign axi_arvalid = rstn && (held_ar || eligible0 || eligible1);
    assign axi_araddr = selected_addr;
    assign axi_arid = {3'd0, selected_owner};
    assign axi_arlen = grant_len;
    assign c0_ready = c0_ar_accept;
    assign c1_ready = c1_ar_accept;
    assign c0_rvalid = axi_rvalid && rid_is_c0 && c0_has_owner;
    assign c1_rvalid = axi_rvalid && rid_is_c1 && c1_has_owner;
    assign c0_rdata = axi_rdata;
    assign c1_rdata = axi_rdata;
    assign c0_rlast = c0_rvalid && axi_rlast;
    assign c1_rlast = c1_rvalid && axi_rlast;
    assign busy = c0_outstanding || (c1_outstanding != 3'd0);
    assign c1_wait_arbiter = rstn && c1_valid && c1_reserve &&
        ((c1_outstanding == C1_MAX_OUTSTANDING) ||
         (eligible0 && !selected_owner));
    assign c1_wait_arready = rstn && !held_ar && c1_valid && c1_reserve &&
        (c1_outstanding < C1_MAX_OUTSTANDING) && selected_owner &&
        axi_arvalid && !axi_arready;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            c0_outstanding <= 1'b0;
            c1_outstanding <= 3'd0;
            c0_response_active <= 1'b0;
            c1_response_active <= 1'b0;
            c0_beats_remaining <= 5'd0;
            c1_beats_remaining <= 3'd0;
            prefer_c1 <= 1'b0;
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
                prefer_c1 <= !selected_owner;
            end

            case ({c0_ar_accept, c0_response_fire && axi_rlast})
                2'b10: c0_outstanding <= 1'b1;
                2'b01: c0_outstanding <= 1'b0;
                default: c0_outstanding <= c0_outstanding;
            endcase
            case ({c1_ar_accept, c1_response_fire && axi_rlast})
                2'b10: c1_outstanding <= c1_outstanding + 3'd1;
                2'b01: c1_outstanding <= c1_outstanding - 3'd1;
                2'b11: c1_outstanding <= c1_outstanding;
                default: c1_outstanding <= c1_outstanding;
            endcase

            if (c0_ar_accept) begin
                c0_response_active <= 1'b1;
                c0_beats_remaining <= grant_beats;
            end
            if (c0_response_fire) begin
                if (axi_rlast) begin
                    c0_response_active <= 1'b0;
                    c0_beats_remaining <= 5'd0;
                end else if (c0_response_active && c0_beats_remaining != 5'd0) begin
                    c0_beats_remaining <= c0_beats_remaining - 5'd1;
                end else if (c0_ar_accept && grant_beats > 5'd1) begin
                    c0_beats_remaining <= grant_beats - 5'd1;
                end
            end

            if (c1_response_fire) begin
                if (!c1_response_active) begin
                    c1_response_active <= 1'b1;
                    c1_beats_remaining <= 3'd3;
                end else if (axi_rlast) begin
                    c1_response_active <= 1'b0;
                    c1_beats_remaining <= 3'd0;
                end else if (c1_beats_remaining != 3'd0) begin
                    c1_beats_remaining <= c1_beats_remaining - 3'd1;
                end
            end

            if (response_fault && response_error_count != 16'hffff)
                response_error_count <= response_error_count + 16'd1;
        end
    end
endmodule
