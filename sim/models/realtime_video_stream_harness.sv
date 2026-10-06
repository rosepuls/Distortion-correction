`timescale 1ns/1ps

// Simulation-only DDR model.  A request owns the model until its fixed
// latency expires; ddr_stall freezes progress without losing the request.
module realtime_ddr_model #(
    parameter integer READ_LATENCY = 8,
    parameter integer WRITE_LATENCY = 6
) (
    input wire clk, input wire rst_n, input wire ddr_stall,
    input wire read_req, output reg read_done,
    input wire write_req, output reg write_done,
    output reg stall_seen
);
    reg read_active, write_active;
    integer read_remaining, write_remaining;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_done <= 1'b0; write_done <= 1'b0; stall_seen <= 1'b0;
            read_active <= 1'b0; write_active <= 1'b0;
            read_remaining <= 0; write_remaining <= 0;
        end else begin
            read_done <= 1'b0;
            write_done <= 1'b0;
            if (ddr_stall && (read_active || write_active))
                stall_seen <= 1'b1;
            if (!read_active && read_req) begin
                read_active <= 1'b1;
                read_remaining <= READ_LATENCY;
            end else if (read_active && !ddr_stall) begin
                if (read_remaining == 0) begin
                    read_active <= 1'b0;
                    read_done <= 1'b1;
                end else begin
                    read_remaining <= read_remaining - 1;
                end
            end
            if (!write_active && write_req) begin
                write_active <= 1'b1;
                write_remaining <= WRITE_LATENCY;
            end else if (write_active && !ddr_stall) begin
                if (write_remaining == 0) begin
                    write_active <= 1'b0;
                    write_done <= 1'b1;
                end else begin
                    write_remaining <= write_remaining - 1;
                end
            end
        end
    end
endmodule

// A frame-level behavioural wrapper around the real scheduler.  It replaces
// the physical HDMI/DDR endpoints only; frame ownership, completion handoff
// and display-bank selection use the same RTL scheduler as the board top.
module realtime_video_stream_harness #(
    parameter integer ALGORITHM_CYCLES = 40,
    parameter integer OUTPUT_WRITE_CYCLES = 24
) (
    input wire clk, input wire rst_n,
    input wire input_frame_done, input wire input_frame_bank,
    input wire [23:0] input_frame_tag,
    input wire display_frame_start, input wire ddr_stall,
    output wire capture_streaming,
    output wire process_active, output wire process_input_bank,
    output wire process_output_bank, output wire display_active,
    output reg display_bank, output reg display_tag_valid,
    output reg [23:0] display_tag, output wire input_overrun,
    output wire ddr_stall_seen, output reg [31:0] completed_frames
);
    reg [23:0] input_tags [0:1];
    reg [23:0] output_tags [0:1];
    reg [23:0] working_tag;
    reg working_output_bank;
    reg read_req, write_req;
    wire read_done, write_done;
    reg algorithm_active;
    integer algorithm_remaining;
    reg algo_frame_done, output_frame_done;
    wire process_start;
    wire output_ready_toggle;
    wire output_ready_bank;
    reg output_ready_seen;
    reg display_pending;
    reg display_pending_bank;

    realtime_frame_scheduler scheduler (
        .clk(clk), .rst_n(rst_n),
        .input_frame_done(input_frame_done), .input_frame_bank(input_frame_bank),
        .algo_frame_done(algo_frame_done), .output_frame_done(output_frame_done),
        .display_bank_core(display_bank), .process_start(process_start),
        .process_input_bank(process_input_bank), .process_output_bank(process_output_bank),
        .process_active(process_active), .output_ready_toggle(output_ready_toggle),
        .output_ready_bank(output_ready_bank), .input_overrun(input_overrun)
    );

    realtime_ddr_model #(
        .READ_LATENCY(8), .WRITE_LATENCY(OUTPUT_WRITE_CYCLES)
    ) ddr_model (
        .clk(clk), .rst_n(rst_n), .ddr_stall(ddr_stall),
        .read_req(read_req), .read_done(read_done),
        .write_req(write_req), .write_done(write_done), .stall_seen(ddr_stall_seen)
    );

    assign capture_streaming = rst_n;
    assign display_active = display_tag_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_tags[0] <= 24'd0; input_tags[1] <= 24'd0;
            output_tags[0] <= 24'd0; output_tags[1] <= 24'd0;
            working_tag <= 24'd0; working_output_bank <= 1'b0;
            read_req <= 1'b0; write_req <= 1'b0;
            algorithm_active <= 1'b0; algorithm_remaining <= 0;
            algo_frame_done <= 1'b0; output_frame_done <= 1'b0;
            completed_frames <= 32'd0;
            output_ready_seen <= 1'b0; display_pending <= 1'b0;
            display_pending_bank <= 1'b0; display_bank <= 1'b0;
            display_tag_valid <= 1'b0; display_tag <= 24'd0;
        end else begin
            algo_frame_done <= 1'b0;
            output_frame_done <= 1'b0;
            if (input_frame_done)
                input_tags[input_frame_bank] <= input_frame_tag;

            if (process_start) begin
                working_tag <= input_tags[process_input_bank];
                working_output_bank <= process_output_bank;
                read_req <= 1'b1;
            end else if (read_req) begin
                read_req <= 1'b0;
            end

            if (read_done) begin
                algorithm_active <= 1'b1;
                algorithm_remaining <= ALGORITHM_CYCLES;
            end
            if (algorithm_active && !ddr_stall) begin
                if (algorithm_remaining == 0) begin
                    algorithm_active <= 1'b0;
                    algo_frame_done <= 1'b1;
                    write_req <= 1'b1;
                end else begin
                    algorithm_remaining <= algorithm_remaining - 1;
                end
            end else if (write_req) begin
                write_req <= 1'b0;
            end

            if (write_done) begin
                output_tags[working_output_bank] <= working_tag;
                output_frame_done <= 1'b1;
                completed_frames <= completed_frames + 1'b1;
            end

            if (output_ready_seen != output_ready_toggle) begin
                output_ready_seen <= output_ready_toggle;
                display_pending <= 1'b1;
                display_pending_bank <= output_ready_bank;
            end
            if (display_frame_start && display_pending) begin
                display_bank <= display_pending_bank;
                display_tag <= output_tags[display_pending_bank];
                display_tag_valid <= 1'b1;
                display_pending <= 1'b0;
            end
        end
    end
endmodule
