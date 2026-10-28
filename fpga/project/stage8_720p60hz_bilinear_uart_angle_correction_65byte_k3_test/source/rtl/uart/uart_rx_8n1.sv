`timescale 1ns / 1ps

// Asynchronous UART RX, 8 data bits, no parity, one stop bit.
// byte_valid and frame_error are one-cycle pulses in clk domain.
module uart_rx_8n1 #(
    parameter integer CLK_HZ = 125000000,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       rx,
    output reg [7:0]  byte_data,
    output reg        byte_valid,
    output reg        frame_error
);
    localparam integer CLKS_PER_BIT =
        (CLK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_BIT_TICKS = CLKS_PER_BIT / 2;
    localparam integer COUNT_WIDTH = (CLKS_PER_BIT <= 2)
        ? 1 : $clog2(CLKS_PER_BIT);

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;

    // Synchronize the asynchronous board pin before edge detection/sampling.
    always @(posedge clk) begin
        if (!rstn) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state       <= IDLE;
            clk_count   <= {COUNT_WIDTH{1'b0}};
            bit_index   <= 3'd0;
            shift_data  <= 8'd0;
            byte_data   <= 8'd0;
            byte_valid  <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            byte_valid  <= 1'b0;
            frame_error <= 1'b0;

            case (state)
                IDLE: begin
                    clk_count <= {COUNT_WIDTH{1'b0}};
                    if (!rx_sync) begin
                        state <= START;
                    end
                end

                START: begin
                    if (clk_count == HALF_BIT_TICKS - 1) begin
                        clk_count <= {COUNT_WIDTH{1'b0}};
                        if (!rx_sync) begin
                            bit_index <= 3'd0;
                            state <= DATA;
                        end else begin
                            // A short low pulse was not a valid start bit.
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= {COUNT_WIDTH{1'b0}};
                        shift_data[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= {COUNT_WIDTH{1'b0}};
                        state <= IDLE;
                        if (rx_sync) begin
                            byte_data <= shift_data;
                            byte_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    clk_count <= {COUNT_WIDTH{1'b0}};
                    bit_index <= 3'd0;
                end
            endcase
        end
    end
endmodule
