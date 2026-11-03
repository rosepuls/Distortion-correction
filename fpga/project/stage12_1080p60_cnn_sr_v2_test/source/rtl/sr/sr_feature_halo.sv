`timescale 1ns / 1ps

// Inserts a one-pixel, eight-channel zero border around a row-major feature
// stream. The source must provide exactly IMAGE_WIDTH*IMAGE_HEIGHT pixels.
module sr_feature_halo #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer PADDED_WIDTH = IMAGE_WIDTH + 2,
    parameter integer PADDED_HEIGHT = IMAGE_HEIGHT + 2,
    parameter integer X_WIDTH = (PADDED_WIDTH <= 1) ? 1 : $clog2(PADDED_WIDTH),
    parameter integer Y_WIDTH = (PADDED_HEIGHT <= 1) ? 1 : $clog2(PADDED_HEIGHT)
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [63:0]               s_features,
    input  wire [31:0]               s_frame_id,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [63:0]               m_features,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [31:0]               m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    localparam [2:0] ST_WAIT_FIRST = 3'd0;
    localparam [2:0] ST_TOP = 3'd1;
    localparam [2:0] ST_LEFT = 3'd2;
    localparam [2:0] ST_PIXELS = 3'd3;
    localparam [2:0] ST_RIGHT = 3'd4;
    localparam [2:0] ST_BOTTOM = 3'd5;

    reg [2:0] state;
    reg [X_WIDTH-1:0] out_x;
    reg [Y_WIDTH-1:0] out_y;
    reg [X_WIDTH-1:0] bottom_x;
    reg [10:0] image_x;
    reg [9:0] image_y;
    reg [31:0] active_frame_id;
    reg [63:0] first_pixel_features;
    reg first_pixel_pending;
    reg [63:0] output_features;
    reg [31:0] output_frame_id;
    reg output_valid;

    wire output_ready = !output_valid || m_ready;
    assign s_ready = rstn && output_ready &&
                   ((state == ST_WAIT_FIRST) ||
                    ((state == ST_PIXELS) && !first_pixel_pending));
    assign m_valid = rstn && output_valid;
    assign m_features = output_features;
    assign m_x = out_x;
    assign m_y = out_y;
    assign m_frame_id = output_frame_id;
    assign m_sof = output_valid && (out_x == 0) && (out_y == 0);
    assign m_eol = output_valid && (out_x == PADDED_WIDTH-1);
    assign m_eof = output_valid && (out_x == PADDED_WIDTH-1) &&
                   (out_y == PADDED_HEIGHT-1);

    always @(posedge clk) begin
        if (!rstn) begin
            state <= ST_WAIT_FIRST;
            out_x <= {X_WIDTH{1'b0}};
            out_y <= {Y_WIDTH{1'b0}};
            bottom_x <= {X_WIDTH{1'b0}};
            image_x <= 11'd0;
            image_y <= 10'd0;
            active_frame_id <= 32'd0;
            first_pixel_pending <= 1'b0;
            output_valid <= 1'b0;
        end else if (output_ready) begin
            output_valid <= 1'b0;
            case (state)
                ST_WAIT_FIRST: begin
                    if (s_valid) begin
                        first_pixel_features <= s_features;
                        active_frame_id <= s_frame_id;
                        first_pixel_pending <= 1'b1;
                        image_x <= 11'd0;
                        image_y <= 10'd0;
                        bottom_x <= {X_WIDTH{1'b0}};
                        state <= ST_TOP;
                    end
                end

                ST_TOP: begin
                    output_valid <= 1'b1;
                    output_features <= 64'd0;
                    output_frame_id <= active_frame_id;
                    out_x <= bottom_x;
                    out_y <= {Y_WIDTH{1'b0}};
                    if (bottom_x == PADDED_WIDTH-1) begin
                        bottom_x <= {X_WIDTH{1'b0}};
                        state <= ST_LEFT;
                    end else bottom_x <= bottom_x + 1'b1;
                end

                ST_LEFT: begin
                    output_valid <= 1'b1;
                    output_features <= 64'd0;
                    output_frame_id <= active_frame_id;
                    out_x <= {X_WIDTH{1'b0}};
                    out_y <= image_y + 1'b1;
                    image_x <= 11'd0;
                    state <= ST_PIXELS;
                end

                ST_PIXELS: begin
                    if (first_pixel_pending) begin
                        output_valid <= 1'b1;
                        output_features <= first_pixel_features;
                        output_frame_id <= active_frame_id;
                        out_x <= {{(X_WIDTH-1){1'b0}}, 1'b1};
                        out_y <= {{(Y_WIDTH-1){1'b0}}, 1'b1};
                        first_pixel_pending <= 1'b0;
                        if (IMAGE_WIDTH == 1) state <= ST_RIGHT;
                        else image_x <= 11'd1;
                    end else if (s_valid) begin
                        output_valid <= 1'b1;
                        output_features <= s_features;
                        output_frame_id <= s_frame_id;
                        out_x <= image_x + 1'b1;
                        out_y <= image_y + 1'b1;
                        if ((image_x == 0) && (image_y == 0))
                            active_frame_id <= s_frame_id;
                        if (image_x == IMAGE_WIDTH-1) state <= ST_RIGHT;
                        else image_x <= image_x + 1'b1;
                    end
                end

                ST_RIGHT: begin
                    output_valid <= 1'b1;
                    output_features <= 64'd0;
                    output_frame_id <= active_frame_id;
                    out_x <= PADDED_WIDTH-1;
                    out_y <= image_y + 1'b1;
                    if (image_y == IMAGE_HEIGHT-1) begin
                        bottom_x <= {X_WIDTH{1'b0}};
                        state <= ST_BOTTOM;
                    end else begin
                        image_y <= image_y + 1'b1;
                        state <= ST_LEFT;
                    end
                end

                ST_BOTTOM: begin
                    output_valid <= 1'b1;
                    output_features <= 64'd0;
                    output_frame_id <= active_frame_id;
                    out_x <= bottom_x;
                    out_y <= PADDED_HEIGHT-1;
                    if (bottom_x == PADDED_WIDTH-1) begin
                        bottom_x <= {X_WIDTH{1'b0}};
                        image_x <= 11'd0;
                        image_y <= 10'd0;
                        state <= ST_WAIT_FIRST;
                    end else bottom_x <= bottom_x + 1'b1;
                end

                default: begin
                    output_valid <= 1'b0;
                    state <= ST_WAIT_FIRST;
                end
            endcase
        end
    end
endmodule
