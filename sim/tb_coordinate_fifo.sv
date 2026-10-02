`timescale 1ns/1ps

module tb_coordinate_fifo;
    localparam integer DEPTH = 512;
    localparam integer COORD_WIDTH = 12;
    localparam integer FRAC_WIDTH = 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;
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
    integer i;

    always #5 clk = ~clk;

    coordinate_fifo #(
        .DEPTH(DEPTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
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
        if (out_valid && out_ready) begin
            if (out_x0 !== output_count
                || out_y0 !== output_count + 100
                || out_fx !== output_count * 3 + 1
                || out_fy !== output_count * 5 + 2
                || out_coord_valid !== (output_count % 7 != 0)
                || out_sof !== (output_count == 0)
                || out_eol !== (output_count % 31 == 30)) begin
                $display("FAIL: payload mismatch at output %0d", output_count);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // Fill all 512 entries while the consumer is stopped.
        for (i = 0; i < DEPTH; i = i + 1) begin
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

        // The 513th item must be backpressured while the output is held low.
        @(negedge clk);
        in_valid <= 1'b1;
        in_x0 <= DEPTH;
        in_y0 <= DEPTH + 100;
        in_fx <= DEPTH * 3 + 1;
        in_fy <= DEPTH * 5 + 2;
        in_coord_valid <= (DEPTH % 7 != 0);
        in_sof <= 1'b0;
        in_eol <= (DEPTH % 31 == 30);
        repeat (17) begin
            @(posedge clk);
            if (in_ready) begin
                $display("FAIL: FIFO accepted item 513 while output was stalled");
                errors = errors + 1;
            end
        end

        // A simultaneous dequeue must make room for the 513th item.
        @(negedge clk);
        out_ready <= 1'b1;
        @(posedge clk);
        if (!in_ready) begin
            $display("FAIL: FIFO did not allow simultaneous dequeue/enqueue");
            errors = errors + 1;
        end
        @(negedge clk);
        in_valid <= 1'b0;

        repeat (DEPTH + 4) @(posedge clk);

        if (output_count != DEPTH + 1) begin
            $display("FAIL: expected %0d outputs, got %0d", DEPTH + 1, output_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: coordinate_fifo errors=%0d", errors);

        $display("TEST_PASS: coordinate_fifo");
        $finish;
    end
endmodule
