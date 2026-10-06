`timescale 1ns/1ps

// Owns whole-frame ping-pong resources in the 100 MHz core clock domain.
// Capture itself remains continuous.  A completed input frame starts one
// correction job only when the preceding job has released its input/output
// ownership.  A completed output is announced to the video clock domain by
// a toggle; the video domain performs the actual frame-boundary swap.
module realtime_frame_scheduler (
    input  wire clk,
    input  wire rst_n,

    input  wire input_frame_done,
    input  wire input_frame_bank,
    input  wire algo_frame_done,
    input  wire output_frame_done,
    input  wire display_bank_core,

    output reg  process_start,
    output reg  process_input_bank,
    output reg  process_output_bank,
    output reg  process_active,
    output reg  output_ready_toggle,
    output reg  output_ready_bank,
    output reg  input_overrun
);
    reg algo_done_seen;
    reg output_done_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            process_start       <= 1'b0;
            process_input_bank  <= 1'b0;
            process_output_bank <= 1'b0;
            process_active      <= 1'b0;
            output_ready_toggle <= 1'b0;
            output_ready_bank   <= 1'b0;
            input_overrun       <= 1'b0;
            algo_done_seen      <= 1'b0;
            output_done_seen    <= 1'b0;
        end else begin
            process_start <= 1'b0;

            if (process_active) begin
                if (algo_frame_done)
                    algo_done_seen <= 1'b1;
                if (output_frame_done)
                    output_done_seen <= 1'b1;

                if ((algo_done_seen || algo_frame_done) &&
                    (output_done_seen || output_frame_done)) begin
                    process_active      <= 1'b0;
                    output_ready_bank   <= process_output_bank;
                    output_ready_toggle <= ~output_ready_toggle;
                    algo_done_seen      <= 1'b0;
                    output_done_seen    <= 1'b0;
                end

                // This is deliberately sticky.  Clearing it requires reset
                // so firmware/testbench cannot miss a dropped-frame hazard.
                if (input_frame_done)
                    input_overrun <= 1'b1;
            end else if (input_frame_done) begin
                process_start       <= 1'b1;
                process_active      <= 1'b1;
                process_input_bank  <= input_frame_bank;
                process_output_bank <= ~display_bank_core;
                algo_done_seen      <= 1'b0;
                output_done_seen    <= 1'b0;
            end
        end
    end
endmodule
