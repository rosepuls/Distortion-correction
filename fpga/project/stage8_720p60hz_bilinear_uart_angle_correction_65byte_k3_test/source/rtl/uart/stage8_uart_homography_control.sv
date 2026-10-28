`timescale 1ns / 1ps

// UART packet endpoint used by the Stage 8 video test top.
// The decoded configuration is consumed by fram_buf's existing frame-atomic bank.
module stage8_uart_homography_control #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         uart_rx,
    output wire         uart_tx,
    output wire         cfg_valid,
    output wire         cfg_pose_valid,
    output wire [287:0] cfg_words,
    output wire [15:0]  cfg_version,
    output wire         packet_event,
    output wire [7:0]   packet_status
);
    wire [7:0] rx_byte_data;
    wire rx_byte_valid;
    wire rx_frame_error;
    wire [15:0] response_sequence;
    wire [447:0] response_payload;

    uart_rx_8n1 #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) uart_rx_inst (
        .clk(clk), .rstn(rstn), .rx(uart_rx),
        .byte_data(rx_byte_data), .byte_valid(rx_byte_valid), .frame_error(rx_frame_error)
    );

    stage8_pose_packet #(
        .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720),
        .INTERBYTE_TIMEOUT_CYCLES(CLK_HZ / 1000)
    ) packet_parser (
        .clk(clk), .rstn(rstn), .byte_valid(rx_byte_valid), .byte_data(rx_byte_data),
        .cfg_valid(cfg_valid), .cfg_pose_valid(cfg_pose_valid),
        .cfg_words(cfg_words), .cfg_version(cfg_version),
        .response_valid(packet_event), .response_sequence(response_sequence),
        .response_status(packet_status), .response_payload(response_payload)
    );

    stage8_pose_response_tx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) response_sender (
        .clk(clk), .rstn(rstn), .response_valid(packet_event),
        .response_sequence(response_sequence), .response_status(packet_status),
        .response_payload(response_payload), .tx(uart_tx)
    );
endmodule
