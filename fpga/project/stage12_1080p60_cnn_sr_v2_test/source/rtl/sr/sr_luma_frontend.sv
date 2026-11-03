`timescale 1ns / 1ps

// Four-stage elastic RGBX-to-Y front end for the standalone SR stream.
// RGBX is {R,G,B,8'h00}; only valid bits reset, keeping reset fanout off the
// wide datapath. Arithmetic is deliberately split at product and sum bounds.
module sr_luma_frontend #(
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32,
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10
) (
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     s_valid,
    output wire                     s_ready,
    input  wire [31:0]              s_rgbx,
    input  wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input  wire [X_WIDTH-1:0]       s_x,
    input  wire [Y_WIDTH-1:0]       s_y,
    input  wire                     s_sof,
    input  wire                     s_eol,
    input  wire                     s_eof,
    output wire                     m_valid,
    input  wire                     m_ready,
    output wire [7:0]               m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire [X_WIDTH-1:0]       m_x,
    output wire [Y_WIDTH-1:0]       m_y_coord,
    output wire                     m_sof,
    output wire                     m_eol,
    output wire                     m_eof
);
    reg v0, v1, v2, v3;
    wire r3 = !v3 || m_ready;
    wire r2 = !v2 || r3;
    wire r1 = !v1 || r2;
    wire r0 = !v0 || r1;
    assign s_ready = rstn && r0;
    assign m_valid = rstn && v3;

    reg [7:0] r0_r, r0_g, r0_b;
    reg [PIXEL_ID_WIDTH-1:0] id0;
    reg [FRAME_ID_WIDTH-1:0] frame0;
    reg [X_WIDTH-1:0] x0;
    reg [Y_WIDTH-1:0] y0;
    reg sof0, eol0, eof0;

    // Constant coefficient products are bounded to 16 bits (8x8 operands).
    reg [15:0] rp1, gp1, bp1;
    reg [PIXEL_ID_WIDTH-1:0] id1;
    reg [FRAME_ID_WIDTH-1:0] frame1;
    reg [X_WIDTH-1:0] x1;
    reg [Y_WIDTH-1:0] y1;
    reg sof1, eol1, eof1;

    // Partial sum widths are explicit to prevent unintended wide sign math.
    reg [16:0] rg2;
    reg [15:0] b2;
    reg [PIXEL_ID_WIDTH-1:0] id2;
    reg [FRAME_ID_WIDTH-1:0] frame2;
    reg [X_WIDTH-1:0] x2;
    reg [Y_WIDTH-1:0] y2;
    reg sof2, eol2, eof2;

    reg [7:0] out_y;
    reg [PIXEL_ID_WIDTH-1:0] id3;
    reg [FRAME_ID_WIDTH-1:0] frame3;
    reg [X_WIDTH-1:0] x3;
    reg [Y_WIDTH-1:0] y3;
    reg sof3, eol3, eof3;

    wire [16:0] y_sum = rg2 + {1'b0, b2};
    wire [16:0] y_rounded = y_sum + 17'd128;
    assign m_y = out_y;
    assign m_pixel_id = id3;
    assign m_frame_id = frame3;
    assign m_x = x3;
    assign m_y_coord = y3;
    assign m_sof = sof3;
    assign m_eol = eol3;
    assign m_eof = eof3;

    always @(posedge clk) begin
        if (!rstn) begin
            v0 <= 1'b0;
            v1 <= 1'b0;
            v2 <= 1'b0;
            v3 <= 1'b0;
        end else begin
            if (r0) begin
                v0 <= s_valid;
                if (s_valid) begin
                    r0_r <= s_rgbx[31:24];
                    r0_g <= s_rgbx[23:16];
                    r0_b <= s_rgbx[15:8];
                    id0 <= s_pixel_id;
                    frame0 <= s_frame_id;
                    x0 <= s_x;
                    y0 <= s_y;
                    sof0 <= s_sof;
                    eol0 <= s_eol;
                    eof0 <= s_eof;
                end
            end
            if (r1) begin
                v1 <= v0;
                if (v0) begin
                    rp1 <= r0_r * 8'd77;
                    gp1 <= r0_g * 8'd150;
                    bp1 <= r0_b * 8'd29;
                    id1 <= id0;
                    frame1 <= frame0;
                    x1 <= x0;
                    y1 <= y0;
                    sof1 <= sof0;
                    eol1 <= eol0;
                    eof1 <= eof0;
                end
            end
            if (r2) begin
                v2 <= v1;
                if (v1) begin
                    rg2 <= {1'b0, rp1} + {1'b0, gp1};
                    b2 <= bp1;
                    id2 <= id1;
                    frame2 <= frame1;
                    x2 <= x1;
                    y2 <= y1;
                    sof2 <= sof1;
                    eol2 <= eol1;
                    eof2 <= eof1;
                end
            end
            if (r3) begin
                v3 <= v2;
                if (v2) begin
                    out_y <= y_rounded[15:8];
                    id3 <= id2;
                    frame3 <= frame2;
                    x3 <= x2;
                    y3 <= y2;
                    sof3 <= sof2;
                    eol3 <= eol2;
                    eof3 <= eof2;
                end
            end
        end
    end
endmodule
