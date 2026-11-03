`timescale 1ns / 1ps

// Fixed 65-byte Stage 8 homography request parser. CRC is accumulated as
// bytes arrive; each image corner is range-checked over separate clock stages
// so packet validation does not create a long path in the video clock domain.
module stage8_pose_packet #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer INTERBYTE_TIMEOUT_CYCLES = 125000
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         byte_valid,
    input  wire [7:0]   byte_data,
    output reg          cfg_valid,
    output reg          cfg_pose_valid,
    output reg  [287:0] cfg_words,
    output reg  [15:0]  cfg_version,
    output reg          response_valid,
    output reg  [15:0]  response_sequence,
    output reg  [7:0]   response_status,
    output reg  [447:0] response_payload
);
    localparam [2:0] SEARCH_A5 = 3'd0, SEARCH_5A = 3'd1,
                     COLLECT = 3'd2, CHECK = 3'd3,
                     RANGE_X = 3'd4, RANGE_Y = 3'd5, RANGE_SUM = 3'd6;
    localparam [7:0] STATUS_ACCEPTED = 8'd0, STATUS_BAD_VERSION = 8'd1,
                     STATUS_BAD_TYPE = 8'd2, STATUS_BAD_FLAGS = 8'd3,
                     STATUS_BAD_CRC = 8'd4, STATUS_BAD_RANGE = 8'd5,
                     STATUS_BAD_EXTENSION = 8'd6;
    localparam signed [45:0] NUM_LIMIT = 46'sd1073741824;
    localparam signed [45:0] DEN_MIN = 46'sd536870912;
    localparam signed [45:0] DEN_MAX = 46'sd2147483648;

    reg [2:0] state;
    reg [7:0] frame [0:64];
    reg [5:0] frame_index;
    reg [31:0] interbyte_count;
    reg [15:0] crc_accum;
    reg [1:0] range_corner;
    reg range_valid;
    reg signed [45:0] nx_x, ny_x, d_x;
    reg signed [45:0] nx_y, ny_y, d_y;
    reg [287:0] parsed_words;
    reg [447:0] parsed_payload;
    reg [287:0] identity_words;
    reg [7:0] header_status;
    reg extension_is_zero;
    reg [10:0] corner_x;
    reg [9:0] corner_y;
    integer i;
    integer j;

    function automatic [15:0] crc16_byte(input [15:0] crc_in, input [7:0] data);
        reg [15:0] crc;
        integer b;
        begin
            crc = crc_in ^ {data, 8'h00};
            for (b = 0; b < 8; b = b + 1)
                crc = crc[15] ? ((crc << 1) ^ 16'h1021) : (crc << 1);
            crc16_byte = crc;
        end
    endfunction

    always @* begin
        parsed_words = 288'd0;
        for (i = 0; i < 36; i = i + 1)
            parsed_words[(i/4)*32 + (i%4)*8 +: 8] = frame[7+i];

        parsed_payload = 448'd0;
        for (j = 0; j < 56; j = j + 1)
            parsed_payload[j*8 +: 8] = frame[7+j];

        extension_is_zero = 1'b1;
        for (j = 36; j < 56; j = j + 1)
            if (frame[7+j] != 8'h00) extension_is_zero = 1'b0;

        case (range_corner)
            2'd0: begin corner_x = 0; corner_y = 0; end
            2'd1: begin corner_x = IMAGE_WIDTH - 1; corner_y = 0; end
            2'd2: begin corner_x = 0; corner_y = IMAGE_HEIGHT - 1; end
            default: begin corner_x = IMAGE_WIDTH - 1; corner_y = IMAGE_HEIGHT - 1; end
        endcase

        header_status = STATUS_ACCEPTED;
        if (frame[2] != 8'h02) header_status = STATUS_BAD_VERSION;
        else if (frame[3] != 8'h01) header_status = STATUS_BAD_TYPE;
        else if (frame[6][7:1] != 7'd0) header_status = STATUS_BAD_FLAGS;
        else if ({frame[63], frame[64]} != crc_accum) header_status = STATUS_BAD_CRC;
        else if (!extension_is_zero) header_status = STATUS_BAD_EXTENSION;
        else if (frame[6][0] && parsed_words[8*32 +: 32] != 32'h40000000)
            header_status = STATUS_BAD_RANGE;
    end

    wire signed [31:0] h00 = parsed_words[0*32 +: 32];
    wire signed [31:0] h01 = parsed_words[1*32 +: 32];
    wire signed [31:0] h02 = parsed_words[2*32 +: 32];
    wire signed [31:0] h10 = parsed_words[3*32 +: 32];
    wire signed [31:0] h11 = parsed_words[4*32 +: 32];
    wire signed [31:0] h12 = parsed_words[5*32 +: 32];
    wire signed [31:0] h20 = parsed_words[6*32 +: 32];
    wire signed [31:0] h21 = parsed_words[7*32 +: 32];
    wire signed [45:0] nx_final = nx_x + nx_y + {{14{h02[31]}}, h02};
    wire signed [45:0] ny_final = ny_x + ny_y + {{14{h12[31]}}, h12};
    wire signed [45:0] d_final  = d_x  + d_y  + 46'sd1073741824;
    wire corner_in_range = (d_final >= DEN_MIN) && (d_final < DEN_MAX) &&
        (nx_final >= -NUM_LIMIT) && (nx_final <= NUM_LIMIT) &&
        (ny_final >= -NUM_LIMIT) && (ny_final <= NUM_LIMIT);

    always @(posedge clk) begin
        if (!rstn) begin
            state <= SEARCH_A5;
            frame_index <= 0;
            interbyte_count <= 0;
            crc_accum <= 16'hFFFF;
            range_corner <= 0;
            range_valid <= 1'b1;
            nx_x <= 0; ny_x <= 0; d_x <= 0;
            nx_y <= 0; ny_y <= 0; d_y <= 0;
            cfg_valid <= 0;
            cfg_pose_valid <= 0;
            cfg_words <= 0;
            cfg_version <= 0;
            response_valid <= 0;
            response_sequence <= 0;
            response_status <= 0;
            response_payload <= 0;
            identity_words <= {
                32'h40000000, 32'h00000000, 32'h00000000,
                32'h00000000, 32'h00010000, 32'h00000000,
                32'h00000000, 32'h00000000, 32'h00010000
            };
        end else begin
            cfg_valid <= 1'b0;
            response_valid <= 1'b0;

            if (state == COLLECT && INTERBYTE_TIMEOUT_CYCLES > 0) begin
                if (interbyte_count >= INTERBYTE_TIMEOUT_CYCLES - 1) begin
                    state <= SEARCH_A5;
                    frame_index <= 0;
                    interbyte_count <= 0;
                    crc_accum <= 16'hFFFF;
                end else if (!byte_valid) begin
                    interbyte_count <= interbyte_count + 1'b1;
                end
            end

            case (state)
                CHECK: begin
                    response_sequence <= {frame[5], frame[4]};
                    response_payload <= parsed_payload;
                    if (header_status != STATUS_ACCEPTED) begin
                        response_status <= header_status;
                        response_valid <= 1'b1;
                        state <= SEARCH_A5;
                    end else if (frame[6][0]) begin
                        range_corner <= 0;
                        range_valid <= 1'b1;
                        state <= RANGE_X;
                    end else begin
                        cfg_valid <= 1'b1;
                        cfg_pose_valid <= 1'b0;
                        cfg_words <= identity_words;
                        cfg_version <= {frame[5], frame[4]};
                        response_status <= STATUS_ACCEPTED;
                        response_valid <= 1'b1;
                        state <= SEARCH_A5;
                    end
                    frame_index <= 0;
                end
                RANGE_X: begin
                    nx_x <= $signed(h00) * $signed({1'b0, corner_x});
                    ny_x <= $signed(h10) * $signed({1'b0, corner_x});
                    d_x  <= $signed(h20) * $signed({1'b0, corner_x});
                    state <= RANGE_Y;
                end
                RANGE_Y: begin
                    nx_y <= $signed(h01) * $signed({1'b0, corner_y});
                    ny_y <= $signed(h11) * $signed({1'b0, corner_y});
                    d_y  <= $signed(h21) * $signed({1'b0, corner_y});
                    state <= RANGE_SUM;
                end
                RANGE_SUM: begin
                    if (!corner_in_range) range_valid <= 1'b0;
                    if (range_corner == 2'd3) begin
                        if (range_valid && corner_in_range) begin
                            cfg_valid <= 1'b1;
                            cfg_pose_valid <= 1'b1;
                            cfg_words <= parsed_words;
                            cfg_version <= {frame[5], frame[4]};
                            response_status <= STATUS_ACCEPTED;
                        end else begin
                            response_status <= STATUS_BAD_RANGE;
                        end
                        response_valid <= 1'b1;
                        state <= SEARCH_A5;
                    end else begin
                        range_corner <= range_corner + 1'b1;
                        state <= RANGE_X;
                    end
                end
                default: begin
                    if (byte_valid && state != CHECK) begin
                        interbyte_count <= 0;
                        case (state)
                            SEARCH_A5: begin
                                if (byte_data == 8'hA5) state <= SEARCH_5A;
                            end
                            SEARCH_5A: begin
                                if (byte_data == 8'h5A) begin
                                    frame[0] <= 8'hA5;
                                    frame[1] <= 8'h5A;
                                    frame_index <= 0;
                                    crc_accum <= 16'hFFFF;
                                    state <= COLLECT;
                                end else if (byte_data != 8'hA5) state <= SEARCH_A5;
                            end
                            COLLECT: begin
                                frame[frame_index + 2] <= byte_data;
                                if (frame_index <= 6'd60)
                                    crc_accum <= crc16_byte(crc_accum, byte_data);
                                if (frame_index == 6'd62) begin
                                    state <= CHECK;
                                    frame_index <= 0;
                                end else frame_index <= frame_index + 1'b1;
                            end
                            default: state <= SEARCH_A5;
                        endcase
                    end
                end
            endcase
        end
    end
endmodule
