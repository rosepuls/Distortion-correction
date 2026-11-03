`timescale 1ns / 1ps

// Raw RGBX8888 copy in 16 x 256-bit bursts. Addresses count 32-bit words.
// Input slots are physical 0..2; output slots are physical 3..5. A burst is
// fully read into local RAM before its matching write AW is issued, so the
// read client can always reserve all 16 beats without DDR RREADY.
module frame_copy_engine #(
    parameter integer BURSTS_PER_FRAME = 7200,
    parameter integer STALL_LIMIT = 24'hffffff
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         start,
    output wire         start_ready,
    input  wire [1:0]   input_slot,
    input  wire [1:0]   output_slot,
    input  wire [31:0]  input_sequence,
    output reg          copy_done,
    output reg          copy_error,
    output wire         active,
    output reg          fatal_fault,
    output reg  [31:0]  completed_sequence,
    output wire         read_valid,
    output wire [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         write_awvalid,
    output wire [27:0]  write_awaddr,
    output wire [3:0]   write_awlen,
    input  wire         write_awready,
    output wire         write_wvalid,
    output wire [255:0] write_wdata,
    output wire [31:0]  write_wstrb,
    input  wire         write_wready,
    input  wire         write_wlast,
    output wire         write_source_busy,
    input  wire         copy_write_idle,
    input  wire         read_fault,
    input  wire         write_fault
);
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] READ_AR = 3'd1;
    localparam [2:0] READ_DATA = 3'd2;
    localparam [2:0] WRITE_AW = 3'd3;
    localparam [2:0] WRITE_DATA = 3'd4;
    localparam [2:0] WAIT_DRAIN = 3'd5;
    localparam [2:0] ERROR_READ_DRAIN = 3'd6;
    localparam [2:0] ERROR_DRAIN = 3'd7;
    localparam [12:0] LAST_BURST = BURSTS_PER_FRAME - 1;
    reg [2:0] state;
    reg [1:0] source_slot, destination_slot;
    reg [12:0] burst_index;
    reg [4:0] read_index, write_index;
    reg [255:0] burst_data [0:15];
    reg [31:0] stall_count;

    wire [2:0] destination_physical = {1'b0, destination_slot} + 3'd3;
    wire [21:0] word_offset = {2'b00, burst_index, 7'b0000000};
    wire progress = ((state == READ_AR) && read_valid && read_ready) ||
                    ((state == READ_DATA) && read_rvalid) ||
                    ((state == WRITE_AW) && write_awvalid && write_awready) ||
                    ((state == WRITE_DATA) && write_wvalid && write_wready) ||
                    ((state == WAIT_DRAIN || state == ERROR_DRAIN) && copy_write_idle);
    wire timed_out = (stall_count >= STALL_LIMIT);

    assign start_ready = rstn && state == IDLE && !fatal_fault;
    assign active = state != IDLE;
    assign read_valid = rstn && state == READ_AR && !fatal_fault;
    assign read_addr = {3'b000, 1'b0, source_slot, word_offset};
    assign read_len = 4'd15;
    assign read_reserve = read_valid;
    assign write_awvalid = rstn && state == WRITE_AW && !fatal_fault;
    assign write_awaddr = {3'b000, destination_physical, word_offset};
    assign write_awlen = 4'd15;
    assign write_wvalid = rstn && state == WRITE_DATA;
    assign write_wdata = (write_index < 5'd16) ?
                         burst_data[write_index[3:0]] : 256'd0;
    assign write_wstrb = (write_index < 5'd16) ? 32'hffffffff : 32'd0;
    assign write_source_busy = state == WRITE_AW || state == WRITE_DATA;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            source_slot <= 2'd0;
            destination_slot <= 2'd0;
            burst_index <= 13'd0;
            read_index <= 5'd0;
            write_index <= 5'd0;
            stall_count <= 32'd0;
            copy_done <= 1'b0;
            copy_error <= 1'b0;
            fatal_fault <= 1'b0;
            completed_sequence <= 32'd0;
        end else begin
            copy_done <= 1'b0;
            copy_error <= 1'b0;
            if (state == IDLE || progress)
                stall_count <= 32'd0;
            else if (stall_count != 32'hffff_ffff)
                stall_count <= stall_count + 1'b1;

            if (read_fault || write_fault) begin
                fatal_fault <= 1'b1;
                if (state == READ_DATA && !read_rlast)
                    state <= ERROR_READ_DRAIN;
                else if (state != WRITE_DATA && state != IDLE)
                    state <= ERROR_DRAIN;
            end else if (timed_out && state != IDLE) begin
                fatal_fault <= 1'b1;
                if (state == READ_DATA)
                    state <= ERROR_READ_DRAIN;
                else if (state != WRITE_DATA)
                    state <= ERROR_DRAIN;
            end else begin
                case (state)
                    IDLE: if (start && start_ready) begin
                        source_slot <= input_slot;
                        destination_slot <= output_slot;
                        completed_sequence <= input_sequence;
                        burst_index <= 13'd0;
                        read_index <= 5'd0;
                        write_index <= 5'd0;
                        if (input_slot < 2'd3 && output_slot < 2'd3)
                            state <= READ_AR;
                        else begin
                            fatal_fault <= 1'b1;
                            copy_error <= 1'b1;
                        end
                    end
                    READ_AR: if (read_valid && read_ready) begin
                        read_index <= 5'd0;
                        state <= READ_DATA;
                    end
                    READ_DATA: if (read_rvalid) begin
                        if (read_index < 5'd16)
                            burst_data[read_index[3:0]] <= read_rdata;
                        if (read_rlast != (read_index == 5'd15)) begin
                            fatal_fault <= 1'b1;
                            state <= read_rlast ? ERROR_DRAIN : ERROR_READ_DRAIN;
                        end else if (read_rlast) begin
                            state <= WRITE_AW;
                        end else read_index <= read_index + 1'b1;
                    end
                    WRITE_AW: if (write_awvalid && write_awready) begin
                        write_index <= 5'd0;
                        state <= WRITE_DATA;
                    end
                    WRITE_DATA: if (write_wvalid && write_wready) begin
                        if (write_wlast) begin
                            if (write_index != 5'd15 || fatal_fault) begin
                                fatal_fault <= 1'b1;
                                state <= ERROR_DRAIN;
                            end else if (burst_index == LAST_BURST) begin
                                state <= WAIT_DRAIN;
                            end else begin
                                burst_index <= burst_index + 1'b1;
                                state <= READ_AR;
                            end
                        end else if (write_index < 5'd31) begin
                            if (write_index == 5'd15)
                                fatal_fault <= 1'b1;
                            write_index <= write_index + 1'b1;
                        end
                    end
                    WAIT_DRAIN: if (copy_write_idle) begin
                        copy_done <= 1'b1;
                        state <= IDLE;
                    end
                    ERROR_READ_DRAIN: if (read_rvalid && read_rlast)
                        state <= ERROR_DRAIN;
                    ERROR_DRAIN: if (copy_write_idle) begin
                        copy_error <= 1'b1;
                        state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
