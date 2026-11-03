`timescale 1ns / 1ps

// Serializes the fixed 65-byte Stage 8 response packet.
module stage8_pose_response_tx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         response_valid,
    input  wire [15:0]  response_sequence,
    input  wire [7:0]   response_status,
    input  wire [447:0] response_payload,
    output wire         tx
);
    reg busy;
    reg [6:0] byte_index;
    reg [15:0] seq_reg;
    reg [7:0] status_reg;
    reg [447:0] payload_reg;
    reg [15:0] crc_reg;
    wire uart_ready;
    reg [7:0] uart_data;
    wire uart_byte_valid = busy && uart_ready;

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
        if (byte_index == 0) uart_data = 8'hA5;
        else if (byte_index == 1) uart_data = 8'h5A;
        else if (byte_index == 2) uart_data = 8'h02;
        else if (byte_index == 3) uart_data = 8'h81;
        else if (byte_index == 4) uart_data = seq_reg[7:0];
        else if (byte_index == 5) uart_data = seq_reg[15:8];
        else if (byte_index == 6) uart_data = status_reg;
        // The 56-byte response payload occupies offsets 7 through 62.
        else if ((byte_index >= 7) && (byte_index <= 62))
            uart_data = payload_reg[(byte_index - 7) * 8 +: 8];
        else if (byte_index == 63) uart_data = crc_reg[15:8];
        else uart_data = crc_reg[7:0];
    end

    uart_tx_8n1 #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) uart_tx (
        .clk(clk), .rstn(rstn), .byte_valid(uart_byte_valid),
        .byte_data(uart_data), .byte_ready(uart_ready), .tx(tx)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            busy <= 1'b0;
            byte_index <= 0;
            seq_reg <= 0;
            status_reg <= 0;
            payload_reg <= 0;
            crc_reg <= 16'hFFFF;
        end else begin
            if (!busy && response_valid) begin
                busy <= 1'b1;
                byte_index <= 0;
                seq_reg <= response_sequence;
                status_reg <= response_status;
                payload_reg <= response_payload;
                crc_reg <= 16'hFFFF;
            end else if (busy && uart_ready) begin
                // CRC covers response bytes 2 through 62. Accumulate one
                // transmitted byte per handshake to avoid a long combinational
                // CRC chain across the entire response payload.
                if ((byte_index >= 7'd2) && (byte_index <= 7'd62))
                    crc_reg <= crc16_byte(crc_reg, uart_data);
                if (byte_index == 7'd64) begin
                    busy <= 1'b0;
                    byte_index <= 0;
                end else byte_index <= byte_index + 1'b1;
            end
        end
    end
endmodule
