`timescale 1ns/1ps

// One-transaction Pixel Fetch -> Bilinear engine.
//
// The memory interface uses logical pixel addresses:
//   addr = y * FRAME_STRIDE_PIXELS + x
// Requests are issued in P00, P10, P01, P11 order.  The engine accepts a new
// coordinate only in IDLE and holds it until four ordered responses arrive.
module pixel_fetch_engine #(
    parameter integer FRAME_STRIDE_PIXELS = 1280,
    parameter integer ADDR_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [ADDR_WIDTH-1:0]   in_x0,
    input  wire [ADDR_WIDTH-1:0]   in_y0,
    input  wire [15:0]              in_dx_q16,
    input  wire [15:0]              in_dy_q16,
    input  wire                    in_coord_valid,
    input  wire                    in_valid,
    input  wire                    in_sof,
    input  wire                    in_eol,
    output wire                    in_ready,
    output wire                    req_valid,
    input  wire                    req_ready,
    output wire [ADDR_WIDTH-1:0]   req_addr,
    input  wire                    rsp_valid,
    output wire                    rsp_ready,
    input  wire [23:0]             rsp_data,
    output wire [23:0]             out_pixel,
    output wire                    out_valid,
    output wire                    out_sof,
    output wire                    out_eol
);

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_REQ_P00    = 4'd1;
    localparam [3:0] ST_WAIT_P00   = 4'd2;
    localparam [3:0] ST_REQ_P10    = 4'd3;
    localparam [3:0] ST_WAIT_P10   = 4'd4;
    localparam [3:0] ST_REQ_P01    = 4'd5;
    localparam [3:0] ST_WAIT_P01   = 4'd6;
    localparam [3:0] ST_REQ_P11    = 4'd7;
    localparam [3:0] ST_WAIT_P11   = 4'd8;
    localparam [3:0] ST_INTERP     = 4'd9;
    localparam [3:0] ST_INVALID    = 4'd10;

    reg [3:0] state;
    reg [ADDR_WIDTH-1:0] base_addr;
    reg [15:0] interp_dx;
    reg [15:0] interp_dy;
    reg         interp_coord_valid;
    reg         interp_sof;
    reg         interp_eol;
    reg [23:0]  pixel_p00;
    reg [23:0]  pixel_p10;
    reg [23:0]  pixel_p01;
    reg [23:0]  pixel_p11;

    reg         interp_in_valid;

    assign in_ready = (state == ST_IDLE);
    assign req_valid =
        (state == ST_REQ_P00) ||
        (state == ST_REQ_P10) ||
        (state == ST_REQ_P01) ||
        (state == ST_REQ_P11);
    assign rsp_ready =
        (state == ST_WAIT_P00) ||
        (state == ST_WAIT_P10) ||
        (state == ST_WAIT_P01) ||
        (state == ST_WAIT_P11);

    assign req_addr =
        (state == ST_REQ_P00) ? base_addr :
        (state == ST_REQ_P10) ? (base_addr + 1) :
        (state == ST_REQ_P01) ? (base_addr + FRAME_STRIDE_PIXELS) :
        (state == ST_REQ_P11) ? (base_addr + FRAME_STRIDE_PIXELS + 1) :
        {ADDR_WIDTH{1'b0}};

    bilinear_interp bilinear_interp_inst (
        .clk(clk),
        .rst_n(rst_n),
        .p00(pixel_p00),
        .p10(pixel_p10),
        .p01(pixel_p01),
        .p11(pixel_p11),
        .dx(interp_dx),
        .dy(interp_dy),
        .coord_valid(interp_coord_valid),
        .in_valid(interp_in_valid),
        .in_sof(interp_sof),
        .in_eol(interp_eol),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            base_addr <= {ADDR_WIDTH{1'b0}};
            interp_dx <= 16'd0;
            interp_dy <= 16'd0;
            interp_coord_valid <= 1'b0;
            interp_sof <= 1'b0;
            interp_eol <= 1'b0;
            pixel_p00 <= 24'd0;
            pixel_p10 <= 24'd0;
            pixel_p01 <= 24'd0;
            pixel_p11 <= 24'd0;
            interp_in_valid <= 1'b0;
        end else begin
            interp_in_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (in_valid) begin
                        base_addr <= in_y0 * FRAME_STRIDE_PIXELS + in_x0;
                        interp_dx <= in_dx_q16;
                        interp_dy <= in_dy_q16;
                        interp_sof <= in_sof;
                        interp_eol <= in_eol;
                        pixel_p00 <= 24'd0;
                        pixel_p10 <= 24'd0;
                        pixel_p01 <= 24'd0;
                        pixel_p11 <= 24'd0;
                        if (in_coord_valid) begin
                            interp_coord_valid <= 1'b1;
                            state <= ST_REQ_P00;
                        end else begin
                            interp_coord_valid <= 1'b0;
                            state <= ST_INVALID;
                        end
                    end
                end

                ST_REQ_P00: begin
                    if (req_valid && req_ready)
                        state <= ST_WAIT_P00;
                end

                ST_REQ_P10: begin
                    if (req_valid && req_ready)
                        state <= ST_WAIT_P10;
                end

                ST_REQ_P01: begin
                    if (req_valid && req_ready)
                        state <= ST_WAIT_P01;
                end

                ST_REQ_P11: begin
                    if (req_valid && req_ready) begin
                        state <= ST_WAIT_P11;
                    end
                end

                ST_WAIT_P00: begin
                    if (rsp_valid && rsp_ready) begin
                        pixel_p00 <= rsp_data;
                        state <= ST_REQ_P10;
                    end
                end

                ST_WAIT_P10: begin
                    if (rsp_valid && rsp_ready) begin
                        pixel_p10 <= rsp_data;
                        state <= ST_REQ_P01;
                    end
                end

                ST_WAIT_P01: begin
                    if (rsp_valid && rsp_ready) begin
                        pixel_p01 <= rsp_data;
                        state <= ST_REQ_P11;
                    end
                end

                ST_WAIT_P11: begin
                    if (rsp_valid && rsp_ready) begin
                        pixel_p11 <= rsp_data;
                        state <= ST_INTERP;
                    end
                end

                ST_INTERP: begin
                    interp_in_valid <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_INVALID: begin
                    interp_in_valid <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
