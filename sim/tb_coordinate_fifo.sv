`timescale 1ns/1ps

module tb_coordinate_fifo;
    // Match the only production instance.  In particular, DEPTH is not a
    // power of two and the scanner relies on the 32-slot reserve margin.
    localparam integer DEPTH = 544;
    localparam integer RESERVE_SLOTS = 32;
    localparam integer COORD_WIDTH = 12;
    localparam integer FRAC_WIDTH = 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;
    wire reserve_ready;
    reg [COORD_WIDTH-1:0] in_x0 = '0;
    reg [COORD_WIDTH-1:0] in_y0 = '0;
    reg [FRAC_WIDTH-1:0] in_fx = '0;
    reg [FRAC_WIDTH-1:0] in_fy = '0;
    reg in_coord_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;

    wire out_valid;
    reg out_ready = 1'b0;
    wire [COORD_WIDTH-1:0] out_x0;
    wire [COORD_WIDTH-1:0] out_y0;
    wire [FRAC_WIDTH-1:0] out_fx;
    wire [FRAC_WIDTH-1:0] out_fy;
    wire out_coord_valid;
    wire out_sof;
    wire out_eol;

    integer errors = 0;
    integer output_count = 0;
    integer drain_cycles = 0;
    integer i;
    reg stalled_payload_valid = 1'b0;
    reg [COORD_WIDTH-1:0] stalled_x0;
    reg [COORD_WIDTH-1:0] stalled_y0;
    reg [FRAC_WIDTH-1:0] stalled_fx;
    reg [FRAC_WIDTH-1:0] stalled_fy;
    reg stalled_coord_valid;
    reg stalled_sof;
    reg stalled_eol;

    always #5 clk = ~clk;

    coordinate_fifo #(
        .DEPTH(DEPTH),
        .RESERVE_SLOTS(RESERVE_SLOTS),
        .COORD_WIDTH(COORD_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .reserve_ready(reserve_ready),
        .in_x0(in_x0),
        .in_y0(in_y0),
        .in_fx(in_fx),
        .in_fy(in_fy),
        .in_coord_valid(in_coord_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_x0(out_x0),
        .out_y0(out_y0),
        .out_fx(out_fx),
        .out_fy(out_fy),
        .out_coord_valid(out_coord_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    always @(posedge clk) begin
        if (out_valid && !out_ready) begin
            if (stalled_payload_valid
                && (out_x0 !== stalled_x0
                    || out_y0 !== stalled_y0
                    || out_fx !== stalled_fx
                    || out_fy !== stalled_fy
                    || out_coord_valid !== stalled_coord_valid
                    || out_sof !== stalled_sof
                    || out_eol !== stalled_eol)) begin
                $display("FAIL: FIFO output changed while backpressured");
                errors = errors + 1;
            end
            stalled_payload_valid = 1'b1;
            stalled_x0 = out_x0;
            stalled_y0 = out_y0;
            stalled_fx = out_fx;
            stalled_fy = out_fy;
            stalled_coord_valid = out_coord_valid;
            stalled_sof = out_sof;
            stalled_eol = out_eol;
        end else begin
            stalled_payload_valid = 1'b0;
        end

        if (out_valid && out_ready) begin
            if (out_x0 !== output_count
                || out_y0 !== output_count + 100
                || out_fx !== output_count * 3 + 1
                || out_fy !== output_count * 5 + 2
                || out_coord_valid !== (output_count % 7 != 0)
                || out_sof !== (output_count == 0)
                || out_eol !== (output_count % 31 == 30)) begin
                $display("FAIL: payload mismatch at output %0d expected={%0d,%0d,%0d,%0d,%0d,%0d,%0d} actual={%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
                         output_count,
                         output_count, output_count + 100,
                         output_count * 3 + 1, output_count * 5 + 2,
                         (output_count % 7 != 0), (output_count == 0),
                         (output_count % 31 == 30),
                         out_x0, out_y0, out_fx, out_fy,
                         out_coord_valid, out_sof, out_eol);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // Fill the 512 scanner-visible slots while the consumer is stopped.
        // The remaining 32 entries are reserved for already accepted core
        // results that can arrive after scanner backpressure takes effect.
        for (i = 0; i < DEPTH - RESERVE_SLOTS; i = i + 1) begin
            @(negedge clk);
            in_valid <= 1'b1;
            in_x0 <= i;
            in_y0 <= i + 100;
            in_fx <= i * 3 + 1;
            in_fy <= i * 5 + 2;
            in_coord_valid <= (i % 7 != 0);
            in_sof <= (i == 0);
            in_eol <= (i % 31 == 30);
            @(posedge clk);
            if (!in_ready) begin
                $display("FAIL: FIFO became full before item %0d", i);
                errors = errors + 1;
            end
        end

        @(negedge clk);
        // Stop the source before observing the reserve boundary.  Leaving
        // valid asserted here would enqueue the final scanner item twice on
        // the following edge and invalidate the ordering scoreboard.
        in_valid <= 1'b0;
        if (reserve_ready) begin
            $display("FAIL: reserve_ready stayed high after %0d scanner-visible entries",
                     DEPTH - RESERVE_SLOTS);
            errors = errors + 1;
        end

        // A simultaneous dequeue at the reserve boundary must reopen the
        // reserve admission path; it must not lose either payload.
        @(negedge clk);
        in_valid <= 1'b1;
        in_x0 <= DEPTH - RESERVE_SLOTS;
        in_y0 <= DEPTH - RESERVE_SLOTS + 100;
        in_fx <= (DEPTH - RESERVE_SLOTS) * 3 + 1;
        in_fy <= (DEPTH - RESERVE_SLOTS) * 5 + 2;
        in_coord_valid <= ((DEPTH - RESERVE_SLOTS) % 7 != 0);
        in_sof <= 1'b0;
        in_eol <= ((DEPTH - RESERVE_SLOTS) % 31 == 30);
        out_ready = 1'b1;
        #1;
        if (!reserve_ready) begin
            $display("FAIL: reserve_ready did not reopen for a simultaneous dequeue");
            errors = errors + 1;
        end
        @(posedge clk);
        if (!in_ready) begin
            $display("FAIL: FIFO rejected reserve-boundary simultaneous dequeue/enqueue");
            errors = errors + 1;
        end
        @(negedge clk);
        out_ready <= 1'b0;
        in_valid <= 1'b0;

        // Emulate the 32 results already in flight in the fixed-latency
        // distortion core.  These must fit after reserve_ready deasserts.
        for (i = DEPTH - RESERVE_SLOTS + 1; i <= DEPTH; i = i + 1) begin
            @(negedge clk);
            in_valid <= 1'b1;
            in_x0 <= i;
            in_y0 <= i + 100;
            in_fx <= i * 3 + 1;
            in_fy <= i * 5 + 2;
            in_coord_valid <= (i % 7 != 0);
            in_sof <= 1'b0;
            in_eol <= (i % 31 == 30);
            #1;
            if (!in_ready) begin
                $display("FAIL: FIFO rejected protected in-flight item %0d", i);
                errors = errors + 1;
            end
            @(posedge clk);
        end

        // At the physical 544-entry limit, input must stop until a dequeue.
        @(negedge clk);
        in_valid <= 1'b1;
        in_x0 <= DEPTH + 1;
        in_y0 <= DEPTH + 101;
        in_fx <= (DEPTH + 1) * 3 + 1;
        in_fy <= (DEPTH + 1) * 5 + 2;
        in_coord_valid <= ((DEPTH + 1) % 7 != 0);
        in_sof <= 1'b0;
        in_eol <= ((DEPTH + 1) % 31 == 30);
        repeat (4) begin
            @(posedge clk);
            if (in_ready) begin
                $display("FAIL: FIFO accepted an item while physically full");
                errors = errors + 1;
            end
        end

        // A full FIFO must still accept an enqueue when that cycle dequeues.
        @(negedge clk);
        out_ready <= 1'b1;
        @(posedge clk);
        if (!in_ready) begin
            $display("FAIL: FIFO did not allow simultaneous dequeue/enqueue");
            errors = errors + 1;
        end
        @(negedge clk);
        in_valid <= 1'b0;

        // Periodic downstream backpressure verifies that the head payload is
        // stable and that the non-power-of-two read/write pointers wrap while
        // every accepted payload remains ordered.
        while (output_count < DEPTH + 2 && drain_cycles < (DEPTH * 3)) begin
            @(negedge clk);
            out_ready <= ((drain_cycles % 5) != 0);
            drain_cycles = drain_cycles + 1;
        end
        @(negedge clk);
        out_ready <= 1'b0;

        if (output_count != DEPTH + 2) begin
            $display("FAIL: expected %0d outputs, got %0d", DEPTH + 2, output_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: coordinate_fifo errors=%0d", errors);

        $display("TEST_PASS: coordinate_fifo");
        $finish;
    end
endmodule
