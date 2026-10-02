`timescale 1ns/1ps

// Vendor-neutral, one-entry logical RGB888 memory model.
// A request is accepted only on req_valid && req_ready.  Responses are
// returned in acceptance order and remain stable until rsp_valid && rsp_ready.
module ddr_behavior_model #(
    parameter integer ADDR_WIDTH    = 32,
    parameter integer PIXEL_WIDTH   = 24,
    parameter integer MEMORY_WORDS  = 1024,
    parameter integer FIXED_LATENCY = 2,
    parameter integer MAX_LATENCY   = 2,
    parameter integer READY_STALL_PERIOD = 0,
    parameter string  INIT_FILE     = ""
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   req_valid,
    output wire                   req_ready,
    input  wire [ADDR_WIDTH-1:0]  req_addr,
    output reg                    rsp_valid,
    input  wire                   rsp_ready,
    output reg  [PIXEL_WIDTH-1:0] rsp_data
);

    reg [PIXEL_WIDTH-1:0] memory [0:MEMORY_WORDS-1];
    reg                    pending;
    reg [ADDR_WIDTH-1:0]   pending_addr;
    integer                latency_count;
    integer                latency_seed;
    integer                selected_latency;
    integer                init_index;
    integer                ready_phase;

    wire periodic_request_stall =
        (READY_STALL_PERIOD > 1) && (ready_phase != 0);
    assign req_ready = rst_n && !pending && !rsp_valid && !periodic_request_stall;

    initial begin
        if (MEMORY_WORDS <= 0) begin
            $fatal(1, "MEMORY_WORDS must be positive");
        end
        if (FIXED_LATENCY < 0 || MAX_LATENCY < 0) begin
            $fatal(1, "latencies must be non-negative");
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end else begin
            for (init_index = 0; init_index < MEMORY_WORDS; init_index = init_index + 1) begin
                memory[init_index] = init_index;
            end
        end
    end

    function [PIXEL_WIDTH-1:0] read_pixel(input [ADDR_WIDTH-1:0] address);
        integer index;
        begin
            index = address;
            if (index >= 0 && index < MEMORY_WORDS) begin
                read_pixel = memory[index];
            end else begin
                read_pixel = {PIXEL_WIDTH{1'b0}};
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 1'b0;
            pending_addr <= '0;
            latency_count <= 0;
            latency_seed <= 1;
            ready_phase <= 0;
            rsp_valid <= 1'b0;
            rsp_data <= '0;
        end else begin
            if (READY_STALL_PERIOD > 1) begin
                if (ready_phase >= READY_STALL_PERIOD - 1)
                    ready_phase <= 0;
                else
                    ready_phase <= ready_phase + 1;
            end else begin
                ready_phase <= 0;
            end

            if (rsp_valid && rsp_ready) begin
                rsp_valid <= 1'b0;
            end

            if (pending) begin
                if (latency_count <= 1) begin
                    rsp_data <= read_pixel(pending_addr);
                    rsp_valid <= 1'b1;
                    pending <= 1'b0;
                    latency_count <= 0;
                end else begin
                    latency_count <= latency_count - 1;
                end
            end

            if (req_valid && req_ready) begin
                pending <= 1'b1;
                pending_addr <= req_addr;
                if (MAX_LATENCY > FIXED_LATENCY) begin
                    selected_latency = latency_seed;
                    if (latency_seed >= MAX_LATENCY) begin
                        latency_seed <= 1;
                    end else begin
                        latency_seed <= latency_seed + 1;
                    end
                end else begin
                    selected_latency = FIXED_LATENCY;
                end
                if (selected_latency < 1) begin
                    selected_latency = 1;
                end
                latency_count <= selected_latency;
            end
        end
    end
endmodule
