`timescale 1ns / 1ps

// Frame-atomic storage for a complete planar homography coefficient set.
// cfg_valid means that the entire nine-word packet has already passed the
// UART/CRC/range checks in this clock domain. An invalid pose packet stages
// identity coefficients and clears pose_valid at the next frame boundary.
// Word i occupies bits i*32+31:i*32:
// h00,h01,h02,h10,h11,h12,h20,h21,h22. The first two rows are signed Q16.16;
// the final row is signed Q2.30. frame_start must pulse on an accepted new
// output frame, before its first coordinate request.
module homography_parameter_bank (
    input  wire         clk,
    input  wire         rstn,
    input  wire         cfg_valid,
    input  wire         cfg_pose_valid,
    input  wire [287:0] cfg_words,
    input  wire [15:0]  cfg_version,
    input  wire         frame_start,
    output reg  [287:0] active_words,
    output reg  [15:0]  active_version,
    output reg          active_pose_valid,
    output reg          active_updated,
    output reg          pending_valid,
    output reg  [15:0]  pending_version
);
    localparam [287:0] IDENTITY_WORDS = {
        32'h40000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00010000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00010000
    };

    reg [287:0] pending_words;
    reg         pending_pose_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active_words   <= IDENTITY_WORDS;
            active_version <= 16'd0;
            active_pose_valid <= 1'b0;
            active_updated <= 1'b0;
            pending_words  <= IDENTITY_WORDS;
            pending_version <= 16'd0;
            pending_pose_valid <= 1'b0;
            pending_valid  <= 1'b0;
        end else begin
            active_updated <= 1'b0;
            if (frame_start && pending_valid) begin
                active_words   <= pending_words;
                active_version <= pending_version;
                active_pose_valid <= pending_pose_valid;
                active_updated <= 1'b1;
                pending_valid  <= 1'b0;
            end
            // A coincident load becomes the pending set for the next frame;
            // this frame receives the previously complete pending set.
            if (cfg_valid) begin
                pending_words   <= cfg_pose_valid ? cfg_words : IDENTITY_WORDS;
                pending_version <= cfg_version;
                pending_pose_valid <= cfg_pose_valid;
                pending_valid   <= 1'b1;
            end
        end
    end
endmodule
