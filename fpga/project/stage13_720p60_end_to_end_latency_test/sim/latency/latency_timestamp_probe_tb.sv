`timescale 1ns/1ps
module latency_timestamp_probe_tb;
    reg clk = 0;
    reg rstn = 0;
    reg input_event_toggle = 0;
    reg output_event_toggle = 0;
    wire [31:0] latency_cycles;
    wire [15:0] sample_count;
    wire latency_valid;
    integer cycle = 0;

    always #4 clk = ~clk;

    latency_timestamp_probe dut (
        .clk(clk), .rstn(rstn),
        .input_event_toggle(input_event_toggle),
        .output_event_toggle(output_event_toggle),
        .latency_cycles(latency_cycles),
        .sample_count(sample_count), .latency_valid(latency_valid)
    );

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (cycle == 10) input_event_toggle <= ~input_event_toggle;
        if (cycle == 110) output_event_toggle <= ~output_event_toggle;
        if (cycle == 150) begin
            if (!latency_valid || sample_count != 1 || latency_cycles != 100)
                $fatal(1, "expected one 100-cycle sample; got valid=%0d count=%0d cycles=%0d", latency_valid, sample_count, latency_cycles);
            $display("PASS latency_cycles=%0d", latency_cycles);
            $finish;
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        rstn <= 1;
    end
endmodule
