`timescale 1ns/1ps

// Streaming coordinate FIFO used to decouple the distortion scanner from
// Tile-cache misses.  The payload is kept together with frame and line marks.
module coordinate_fifo #(
    parameter integer DEPTH = 512,
    // Upstream pipelines without an output ready signal must stop before the
    // FIFO is physically full.  This margin reserves slots for their already
    // accepted transactions while the fetch side is stalled.
    parameter integer RESERVE_SLOTS = 0,
    parameter integer COORD_WIDTH = 12,
    parameter integer FRAC_WIDTH = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     in_valid,
    output wire                     in_ready,
    output wire                     reserve_ready,
    input  wire [COORD_WIDTH-1:0]   in_x0,
    input  wire [COORD_WIDTH-1:0]   in_y0,
    input  wire [FRAC_WIDTH-1:0]    in_fx,
    input  wire [FRAC_WIDTH-1:0]    in_fy,
    input  wire                     in_coord_valid,
    input  wire                     in_sof,
    input  wire                     in_eol,
    output wire                     out_valid,
    input  wire                     out_ready,
    output wire [COORD_WIDTH-1:0]   out_x0,
    output wire [COORD_WIDTH-1:0]   out_y0,
    output wire [FRAC_WIDTH-1:0]    out_fx,
    output wire [FRAC_WIDTH-1:0]    out_fy,
    output wire                     out_coord_valid,
    output wire                     out_sof,
    output wire                     out_eol
);
    localparam integer PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    reg [COORD_WIDTH-1:0] x0_mem [0:DEPTH-1];
    reg [COORD_WIDTH-1:0] y0_mem [0:DEPTH-1];
    reg [FRAC_WIDTH-1:0] fx_mem [0:DEPTH-1];
    reg [FRAC_WIDTH-1:0] fy_mem [0:DEPTH-1];
    reg coord_valid_mem [0:DEPTH-1];
    reg sof_mem [0:DEPTH-1];
    reg eol_mem [0:DEPTH-1];

    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [COUNT_WIDTH-1:0] item_count;

    wire fifo_empty = (item_count == 0);
    wire fifo_full = (item_count == DEPTH);
    wire dequeue = out_valid && out_ready;
    wire enqueue = in_valid && in_ready;

    // Permit a write on the same cycle as a dequeue when full.  This keeps
    // the scanner from losing one cycle at every cache-service boundary.
    assign in_ready = !fifo_full || (out_ready && out_valid);
    assign reserve_ready = !rst_n ? 1'b0
                         : (item_count < DEPTH - RESERVE_SLOTS)
                           || ((item_count == DEPTH - RESERVE_SLOTS)
                               && dequeue);
    assign out_valid = !fifo_empty;

    assign out_x0 = x0_mem[read_ptr];
    assign out_y0 = y0_mem[read_ptr];
    assign out_fx = fx_mem[read_ptr];
    assign out_fy = fy_mem[read_ptr];
    assign out_coord_valid = coord_valid_mem[read_ptr];
    assign out_sof = sof_mem[read_ptr];
    assign out_eol = eol_mem[read_ptr];

    function automatic [PTR_WIDTH-1:0] increment_ptr(
        input [PTR_WIDTH-1:0] pointer
    );
        begin
            if (pointer == DEPTH - 1)
                increment_ptr = {PTR_WIDTH{1'b0}};
            else
                increment_ptr = pointer + 1'b1;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= {PTR_WIDTH{1'b0}};
            read_ptr <= {PTR_WIDTH{1'b0}};
            item_count <= {COUNT_WIDTH{1'b0}};
        end else begin
            if (enqueue) begin
                x0_mem[write_ptr] <= in_x0;
                y0_mem[write_ptr] <= in_y0;
                fx_mem[write_ptr] <= in_fx;
                fy_mem[write_ptr] <= in_fy;
                coord_valid_mem[write_ptr] <= in_coord_valid;
                sof_mem[write_ptr] <= in_sof;
                eol_mem[write_ptr] <= in_eol;
                write_ptr <= increment_ptr(write_ptr);
            end

            if (dequeue)
                read_ptr <= increment_ptr(read_ptr);

            case ({enqueue, dequeue})
                2'b10: item_count <= item_count + 1'b1;
                2'b01: item_count <= item_count - 1'b1;
                default: item_count <= item_count;
            endcase
        end
    end
endmodule
