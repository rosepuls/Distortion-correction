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

    localparam integer PAYLOAD_WIDTH = (COORD_WIDTH * 2) + (FRAC_WIDTH * 2) + 3;

    // Keep the FIFO payload together so the PDS can infer one synchronous
    // storage resource instead of seven independent asynchronous LUTRAMs.
    // The first item is held in head_payload; payload_mem contains the
    // remaining queued items and is read only into that register.
    reg [PAYLOAD_WIDTH-1:0] payload_mem [0:DEPTH-1];
    reg [PAYLOAD_WIDTH-1:0] head_payload;
    reg head_valid;

    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [COUNT_WIDTH-1:0] item_count;

    wire fifo_full = (item_count == DEPTH);
    wire dequeue = head_valid && out_ready;
    wire enqueue = in_valid && in_ready;
    wire [PAYLOAD_WIDTH-1:0] in_payload = {
        in_eol,
        in_sof,
        in_coord_valid,
        in_fy,
        in_fx,
        in_y0,
        in_x0
    };

    // Permit a write on the same cycle as a dequeue when full.  This keeps
    // the scanner from losing one cycle at every cache-service boundary.
    assign in_ready = !fifo_full || (out_ready && out_valid);
    assign reserve_ready = !rst_n ? 1'b0
                         : (item_count < DEPTH - RESERVE_SLOTS)
                           || ((item_count == DEPTH - RESERVE_SLOTS)
                               && dequeue);
    assign out_valid = head_valid;

    assign out_x0 = head_payload[COORD_WIDTH-1:0];
    assign out_y0 = head_payload[(COORD_WIDTH * 2)-1:COORD_WIDTH];
    assign out_fx = head_payload[(COORD_WIDTH * 2) + FRAC_WIDTH - 1:
                                  COORD_WIDTH * 2];
    assign out_fy = head_payload[(COORD_WIDTH * 2) + (FRAC_WIDTH * 2) - 1:
                                  (COORD_WIDTH * 2) + FRAC_WIDTH];
    assign out_coord_valid = head_payload[(COORD_WIDTH * 2) + (FRAC_WIDTH * 2)];
    assign out_sof = head_payload[(COORD_WIDTH * 2) + (FRAC_WIDTH * 2) + 1];
    assign out_eol = head_payload[(COORD_WIDTH * 2) + (FRAC_WIDTH * 2) + 2];

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
            head_payload <= {PAYLOAD_WIDTH{1'b0}};
            head_valid <= 1'b0;
        end else begin
            // When the FIFO is empty, bypass the first write directly into
            // the output register.  This preserves fall-through behavior
            // while all subsequent reads use synchronous storage.
            if (enqueue && !head_valid && (item_count == 0)) begin
                head_payload <= in_payload;
                head_valid <= 1'b1;
            end else if (!head_valid && (item_count != 0)) begin
                // Defensive prefetch for any state in which queued storage
                // exists without a valid head.  This is a registered RAM
                // read and advances the storage read pointer exactly once.
                head_payload <= payload_mem[read_ptr];
                head_valid <= 1'b1;
                read_ptr <= increment_ptr(read_ptr);
            end else if (dequeue) begin
                if (item_count > 1) begin
                    // Registered synchronous read of the next queued item.
                    // The output remains valid, so a full-rate hit stream has
                    // no bubble at the head of the FIFO.
                    head_payload <= payload_mem[read_ptr];
                    head_valid <= 1'b1;
                    read_ptr <= increment_ptr(read_ptr);
                end else if (enqueue) begin
                    // One item is being consumed and one is arriving.  Keep
                    // the output register valid without a RAM round trip.
                    head_payload <= in_payload;
                    head_valid <= 1'b1;
                end else begin
                    head_valid <= 1'b0;
                end
            end

            // The first item is bypassed into head_payload and must not also
            // occupy a RAM slot.  Otherwise every later output is delayed by
            // one item because payload_mem[0] contains a duplicate of item 0.
            if (enqueue
                && !(item_count == 0 && !head_valid)
                && !(dequeue && (item_count == 1))) begin
                payload_mem[write_ptr] <= in_payload;
                write_ptr <= increment_ptr(write_ptr);
            end

            case ({enqueue, dequeue})
                2'b10: item_count <= item_count + 1'b1;
                2'b01: item_count <= item_count - 1'b1;
                default: item_count <= item_count;
            endcase
        end
    end
endmodule
