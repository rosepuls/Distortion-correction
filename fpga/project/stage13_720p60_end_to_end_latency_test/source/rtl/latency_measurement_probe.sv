`timescale 1ns/1ps
module video_center_transition_toggle (
    input wire pix_clk, input wire rstn, input wire vs, input wire de,
    input wire [23:0] rgb, output reg event_toggle
);
    reg vs_d, de_d, was_white;
    reg [11:0] x, y;
    wire frame_start = vs && !vs_d;
    wire line_start = de && !de_d;
    wire center_sample = de && (x == 12'd640) && (y == 12'd360);
    wire is_white = (rgb[23:16] >= 8'hc0) &&
                    (rgb[15:8] >= 8'hc0) && (rgb[7:0] >= 8'hc0);

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            vs_d <= 1'b0; de_d <= 1'b0; x <= 12'd0; y <= 12'd0;
            was_white <= 1'b0; event_toggle <= 1'b0;
        end else begin
            vs_d <= vs; de_d <= de;
            if (frame_start) begin x <= 12'd0; y <= 12'hfff; end
            else if (line_start) begin x <= 12'd0; y <= y + 1'b1; end
            else if (de) x <= x + 1'b1;
            if (center_sample && (is_white != was_white)) begin
                was_white <= is_white;
                event_toggle <= ~event_toggle;
            end
        end
    end
endmodule

module latency_timestamp_probe (
    input wire clk, input wire rstn,
    input wire input_event_toggle, input wire output_event_toggle,
    output reg [31:0] latency_cycles, output reg [15:0] sample_count,
    output reg latency_valid
);
    reg [31:0] timer;
    reg [31:0] input_timestamp;
    reg input_pending;
    reg input_meta, input_sync, input_seen;
    reg output_meta, output_sync, output_seen;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            timer <= 32'd0; input_timestamp <= 32'd0; input_pending <= 1'b0;
            input_meta <= 1'b0; input_sync <= 1'b0; input_seen <= 1'b0;
            output_meta <= 1'b0; output_sync <= 1'b0; output_seen <= 1'b0;
            latency_cycles <= 32'd0; sample_count <= 16'd0; latency_valid <= 1'b0;
        end else begin
            timer <= timer + 1'b1;
            input_meta <= input_event_toggle; input_sync <= input_meta;
            output_meta <= output_event_toggle; output_sync <= output_meta;
            if (input_sync != input_seen) begin
                input_seen <= input_sync; input_timestamp <= timer; input_pending <= 1'b1;
            end
            if (output_sync != output_seen) begin
                output_seen <= output_sync;
                if (input_pending) begin
                    latency_cycles <= timer - input_timestamp;
                    if (sample_count != 16'hffff) sample_count <= sample_count + 1'b1;
                    latency_valid <= 1'b1; input_pending <= 1'b0;
                end
            end
        end
    end
endmodule
