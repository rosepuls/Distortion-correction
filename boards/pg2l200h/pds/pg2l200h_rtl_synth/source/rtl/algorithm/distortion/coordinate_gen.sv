`timescale 1ns/1ps

// Generates integer output-image coordinates for the project video stream.
// LATENCY: one registered valid cycle.  Coordinates advance only for
// in_valid=1; a valid in_sof always denotes coordinate (0, 0).
module coordinate_gen #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer COORD_WIDTH = 13
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire                   in_sof,
    input  wire                   in_eol,
    output reg  [COORD_WIDTH-1:0] out_u,
    output reg  [COORD_WIDTH-1:0] out_v,
    output reg                    out_valid,
    output reg                    out_sof,
    output reg                    out_eol
);

    reg [COORD_WIDTH-1:0] next_u;
    reg [COORD_WIDTH-1:0] next_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_u    <= {COORD_WIDTH{1'b0}};
            next_v    <= {COORD_WIDTH{1'b0}};
            out_u     <= {COORD_WIDTH{1'b0}};
            out_v     <= {COORD_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else if (in_valid) begin
            out_valid <= 1'b1;
            out_sof   <= in_sof;
            out_eol   <= in_eol;

            if (in_sof) begin
                out_u <= {COORD_WIDTH{1'b0}};
                out_v <= {COORD_WIDTH{1'b0}};
                if (in_eol) begin
                    next_u <= {COORD_WIDTH{1'b0}};
                    next_v <= {{(COORD_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    next_u <= {{(COORD_WIDTH-1){1'b0}}, 1'b1};
                    next_v <= {COORD_WIDTH{1'b0}};
                end
            end else begin
                out_u <= next_u;
                out_v <= next_v;
                if (in_eol) begin
                    next_u <= {COORD_WIDTH{1'b0}};
                    next_v <= next_v + {{(COORD_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    next_u <= next_u + {{(COORD_WIDTH-1){1'b0}}, 1'b1};
                    next_v <= next_v;
                end
            end
        end else begin
            out_u     <= {COORD_WIDTH{1'b0}};
            out_v     <= {COORD_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule
