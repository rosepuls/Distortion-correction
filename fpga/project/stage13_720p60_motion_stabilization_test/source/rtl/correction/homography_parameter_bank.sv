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
    input  wire         cfg_pose_update,
    input  wire         cfg_pose_valid,
    input  wire [287:0] cfg_words,
    input  wire [15:0]  cfg_version,
    input  wire [2:0]   cfg_profile_id,
    input  wire         cfg_motion_enable,
    input  wire signed [31:0] cfg_motion_dx,
    input  wire signed [31:0] cfg_motion_dy,
    input  wire         frame_start,
    output reg  [287:0] active_words,
    output reg  [15:0]  active_version,
    output reg          active_pose_valid,
    output reg  [2:0]   active_profile_id,
    output reg          active_motion_enable,
    output reg signed [31:0] active_motion_dx,
    output reg signed [31:0] active_motion_dy,
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
    reg [2:0]   pending_profile_id;
    reg         pending_motion_enable;
    reg signed [31:0] pending_motion_dx;
    reg signed [31:0] pending_motion_dy;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active_words   <= IDENTITY_WORDS;
            active_version <= 16'd0;
            active_pose_valid <= 1'b0;
            active_profile_id <= 3'd0;
            active_motion_enable <= 1'b0;
            active_motion_dx <= 32'sd0;
            active_motion_dy <= 32'sd0;
            active_updated <= 1'b0;
            pending_words  <= IDENTITY_WORDS;
            pending_version <= 16'd0;
            pending_pose_valid <= 1'b0;
            pending_profile_id <= 3'd0;
            pending_motion_enable <= 1'b0;
            pending_motion_dx <= 32'sd0;
            pending_motion_dy <= 32'sd0;
            pending_valid  <= 1'b0;
        end else begin
            active_updated <= 1'b0;
            if (frame_start && pending_valid) begin
                active_words   <= pending_words;
                active_version <= pending_version;
                active_pose_valid <= pending_pose_valid;
                active_profile_id <= pending_profile_id;
                active_motion_enable <= pending_motion_enable;
                active_motion_dx <= pending_motion_dx;
                active_motion_dy <= pending_motion_dy;
                active_updated <= 1'b1;
                pending_valid  <= 1'b0;
            end
            // A coincident load becomes the pending set for the next frame;
            // this frame receives the previously complete pending set.
            if (cfg_valid) begin
                if (cfg_pose_update) begin
                    pending_words <= cfg_pose_valid ? cfg_words : IDENTITY_WORDS;
                    pending_pose_valid <= cfg_pose_valid;
                end else if (!pending_valid) begin
                    pending_words <= active_words;
                    pending_pose_valid <= active_pose_valid;
                end
                pending_version <= cfg_version;
                pending_profile_id <= cfg_profile_id;
                pending_motion_enable <= cfg_motion_enable;
                pending_motion_dx <= cfg_motion_enable ? cfg_motion_dx : 32'sd0;
                pending_motion_dy <= cfg_motion_enable ? cfg_motion_dy : 32'sd0;
                pending_valid   <= 1'b1;
            end
        end
    end
endmodule
