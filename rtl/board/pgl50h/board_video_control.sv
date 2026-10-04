`timescale 1ns/1ps

// One-shot board bring-up controller: capture one HDMI frame, process it, then
// continuously display the completed corrected frame until reset.
module board_video_control (
    input  wire clk,
    input  wire rst_n,
    input  wire ddr_init_done,
    input  wire hdmi_init_done,
    input  wire input_frame_complete,
    input  wire algo_frame_done,
    input  wire output_frame_complete,
    output wire capture_enable,
    output wire process_enable,
    output wire display_enable,
    output reg  algo_frame_start
);
    localparam [1:0] STATE_WAIT_READY = 2'd0;
    localparam [1:0] STATE_CAPTURE = 2'd1;
    localparam [1:0] STATE_PROCESS = 2'd2;
    localparam [1:0] STATE_DISPLAY = 2'd3;

    reg [1:0] state;
    reg algo_done_seen;
    reg output_done_seen;

    assign capture_enable = (state == STATE_CAPTURE);
    assign process_enable = (state == STATE_PROCESS);
    assign display_enable = (state == STATE_DISPLAY);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_WAIT_READY;
            algo_frame_start <= 1'b0;
            algo_done_seen <= 1'b0;
            output_done_seen <= 1'b0;
        end else begin
            algo_frame_start <= 1'b0;

            case (state)
                STATE_WAIT_READY: begin
                    if (ddr_init_done && hdmi_init_done)
                        state <= STATE_CAPTURE;
                end

                STATE_CAPTURE: begin
                    if (input_frame_complete) begin
                        algo_frame_start <= 1'b1;
                        algo_done_seen <= 1'b0;
                        output_done_seen <= 1'b0;
                        state <= STATE_PROCESS;
                    end
                end

                STATE_PROCESS: begin
                    if (algo_frame_done)
                        algo_done_seen <= 1'b1;
                    if (output_frame_complete)
                        output_done_seen <= 1'b1;

                    if ((algo_done_seen || algo_frame_done) &&
                        (output_done_seen || output_frame_complete)) begin
                        state <= STATE_DISPLAY;
                    end
                end

                default: begin
                    state <= STATE_DISPLAY;
                end
            endcase
        end
    end
endmodule
