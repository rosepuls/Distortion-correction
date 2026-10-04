`timescale 1ns/1ps

// Project-owned CEA-style 1280x720@30 timing.  The board PLL must provide
// a 37.125 MHz pixel clock (1650 x 750 x 30 Hz).
module video_mode_720p30 #(
    parameter integer H_TOTAL = 1650,
    parameter integer H_SYNC = 40,
    parameter integer H_BACK = 220,
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FRONT = 110,
    parameter integer V_TOTAL = 750,
    parameter integer V_SYNC = 5,
    parameter integer V_BACK = 20,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FRONT = 5,
    parameter integer X_WIDTH = 12,
    parameter integer Y_WIDTH = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    output wire             hs,
    output wire             vs,
    output wire             de,
    output wire             de_request,
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
    wire request_x = (h_count >= H_ACTIVE_START - 2)
                     && (h_count < H_ACTIVE_START + H_ACTIVE - 2);
    wire active_y = (v_count >= V_ACTIVE_START)
                    && (v_count < V_ACTIVE_START + V_ACTIVE);

    assign hs = rst_n && (h_count < H_SYNC);
    assign vs = rst_n && (v_count < V_SYNC);
    assign de = rst_n && active_x && active_y;
    assign de_request = rst_n && request_x && active_y;
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
