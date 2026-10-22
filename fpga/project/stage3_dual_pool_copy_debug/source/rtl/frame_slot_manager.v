`timescale 1ns / 1ps

// All inputs and outputs are in the DDR controller clock domain. A slot is
// published only after every line write has completed. The display slot is
// held for an entire output frame, including its vertical blanking interval.
module frame_slot_manager (
    input  wire        clk,
    input  wire        rstn,
    input  wire        input_vsync,
    input  wire        input_complete,
    input  wire        output_vsync,
    input  wire        output_complete,
    input  wire        write_busy_line,
    input  wire        read_busy_line,
    output reg  [1:0]  write_slot,
    output reg  [1:0]  display_slot,
    output reg         display_valid,
    output reg  [31:0] published_sequence ,
    output reg  [31:0] displayed_sequence ,
    output reg  [15:0] incomplete_input_count,
    output reg  [15:0] repeated_output_count ,
    output reg  [15:0] incomplete_output_count,
    output reg  [15:0] write_busy_count,
    output reg  [15:0] read_busy_count
);
    reg [1:0] latest_slot;
    reg       latest_valid;
    reg       seen_input_vsync;
    reg       seen_output_vsync;

    // The old latest frame is selected at this VS even when both VS pulses
    // coincide. A newly published frame is therefore displayed next time.
    wire can_switch_display = !display_valid || output_complete;
    wire [1:0] next_display_slot =
        (output_vsync && latest_valid && can_switch_display)
            ? latest_slot : display_slot;
    wire next_display_valid = display_valid ||
        (output_vsync && latest_valid && can_switch_display);

    // Following publication, reserve both the displayed and newest complete
    // slots. Exactly one of three slots remains free for the next writer.
    wire [1:0] free_slot =
        ((!next_display_valid || next_display_slot != 2'd0) && write_slot != 2'd0)
            ? 2'd0 :
        ((!next_display_valid || next_display_slot != 2'd1) && write_slot != 2'd1)
            ? 2'd1 : 2'd2;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            write_slot              <= 2'd0;
            display_slot            <= 2'd0;
            display_valid           <= 1'b0;
            latest_slot             <= 2'd0;
            latest_valid            <= 1'b0;
            seen_input_vsync        <= 1'b0;
            seen_output_vsync       <= 1'b0;
            published_sequence      <= 32'd0;
            displayed_sequence      <= 32'd0;
            incomplete_input_count  <= 16'd0;
            repeated_output_count   <= 16'd0;
            incomplete_output_count <= 16'd0;
            write_busy_count        <= 16'd0;
            read_busy_count         <= 16'd0;
        end else begin
            if (write_busy_line && write_busy_count != 16'hffff)
                write_busy_count <= write_busy_count + 16'd1;
            if (read_busy_line && read_busy_count != 16'hffff)
                read_busy_count <= read_busy_count + 16'd1;

            if (output_vsync) begin
                seen_output_vsync <= 1'b1;
                if (seen_output_vsync && display_valid && !output_complete &&
                    incomplete_output_count != 16'hffff)
                    incomplete_output_count <= incomplete_output_count + 16'd1;

                if (latest_valid && can_switch_display &&
                    (!display_valid || latest_slot != display_slot)) begin
                    display_slot <= latest_slot;
                    display_valid <= 1'b1;
                    displayed_sequence <= published_sequence;
                end else if (seen_output_vsync && display_valid &&
                             repeated_output_count != 16'hffff) begin
                    repeated_output_count <= repeated_output_count + 16'd1;
                end
            end

            if (input_vsync) begin
                seen_input_vsync <= 1'b1;
                if (seen_input_vsync) begin
                    if (input_complete) begin
                        latest_slot <= write_slot;
                        latest_valid <= 1'b1;
                        published_sequence <= published_sequence + 32'd1;
                        write_slot <= free_slot;
                    end else if (incomplete_input_count != 16'hffff) begin
                        incomplete_input_count <= incomplete_input_count + 16'd1;
                    end
                end
            end
        end
    end
endmodule
