`timescale 1ns/1ps

// Project-owned CEA-style 1920x1080@30 timing.  The pixel clock supplied by
// the board PLL is expected to be 74.25 MHz; this module only defines the
// raster and active-video coordinates.
module video_mode_1080p30 #(
    parameter integer H_TOTAL = 2200,
    parameter integer H_SYNC = 44,
    parameter integer H_BACK = 148,
    parameter integer H_ACTIVE = 1920,
    parameter integer H_FRONT = 88,
    parameter integer V_TOTAL = 1125,
    parameter integer V_SYNC = 5,
    parameter integer V_BACK = 36,
    parameter integer V_ACTIVE = 1080,
    parameter integer V_FRONT = 4,
    parameter integer X_WIDTH = 12,
    parameter integer Y_WIDTH = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    output wire             hs,
    output wire             vs,
    output wire             de,
    output wire [X_WIDTH-1:0] x,
    output wire [Y_WIDTH-1:0] y,
    output wire             frame_start
);
    localparam integer H_WIDTH = (H_TOTAL <= 2) ? 1 : $clog2(H_TOTAL);
    localparam integer V_WIDTH = (V_TOTAL <= 2) ? 1 : $clog2(V_TOTAL);
    localparam integer H_ACTIVE_START = H_SYNC + H_BACK;
    localparam integer V_ACTIVE_START = V_SYNC + V_BACK;

    reg [H_WIDTH-1:0] h_count;
    reg [V_WIDTH-1:0] v_count;

    wire active_x = (h_count >= H_ACTIVE_START)
                    && (h_count < H_ACTIVE_START + H_ACTIVE);
    wire active_y = (v_count >= V_ACTIVE_START)
                    && (v_count < V_ACTIVE_START + V_ACTIVE);

    assign hs = rst_n && (h_count < H_SYNC);
    assign vs = rst_n && (v_count < V_SYNC);
    assign de = rst_n && active_x && active_y;
    assign x = de ? h_count - H_ACTIVE_START : {X_WIDTH{1'b0}};
    assign y = de ? v_count - V_ACTIVE_START : {Y_WIDTH{1'b0}};
    assign frame_start = de && (h_count == H_ACTIVE_START)
                         && (v_count == V_ACTIVE_START);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= {H_WIDTH{1'b0}};
            v_count <= {V_WIDTH{1'b0}};
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= {H_WIDTH{1'b0}};
            if (v_count == V_TOTAL - 1)
                v_count <= {V_WIDTH{1'b0}};
            else
                v_count <= v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end
endmodule
