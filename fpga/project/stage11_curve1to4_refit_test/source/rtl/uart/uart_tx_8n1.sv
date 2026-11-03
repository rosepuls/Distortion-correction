`timescale 1ns / 1ps

// UART TX, 8 data bits, no parity, one stop bit, LSB first.
module uart_tx_8n1 #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       byte_valid,
    input  wire [7:0] byte_data,
    output wire       byte_ready,
    output reg        tx
);
    localparam integer CLKS_PER_BIT =
        (CLK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer COUNT_WIDTH = (CLKS_PER_BIT <= 2)
        ? 1 : $clog2(CLKS_PER_BIT);
    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;

    assign byte_ready = rstn && (state == IDLE);

    always @(posedge clk) begin
        if (!rstn) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            shift_data <= 0;
            tx <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    clk_count <= 0;
                    if (byte_valid) begin
                        shift_data <= byte_data;
                        state <= START;
                        tx <= 1'b0;
                    end
                end
                START: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        bit_index <= 0;
                        tx <= shift_data[0];
                        shift_data <= {1'b0, shift_data[7:1]};
                        state <= DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_index == 3'd7) begin
                            tx <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx <= shift_data[0];
                            shift_data <= {1'b0, shift_data[7:1]};
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= IDLE;
                        tx <= 1'b1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                default: begin
                    state <= IDLE;
                    clk_count <= 0;
                    tx <= 1'b1;
                end
            endcase
        end
    end
endmodule
