`timescale 1ns/1ps

// One DDR write-command/data channel shared by two independent producers.
// A grant is made only when the controller accepts a command, then ownership
// remains fixed until ctrl_done.  This prevents a later request from stealing
// write-data handshakes or completion from the active transaction.
module ddr_two_client_arbiter #(
    parameter integer ADDR_WIDTH = 28
) (
    input wire clk, input wire rst_n,

    input wire c0_cmd_valid,
    input wire [ADDR_WIDTH-1:0] c0_cmd_addr,
    input wire [31:0] c0_cmd_len,
    input wire [255:0] c0_data,
    output wire c0_cmd_ready,
    output wire c0_done, output wire c0_bac, output wire c0_data_re,

    input wire c1_cmd_valid,
    input wire [ADDR_WIDTH-1:0] c1_cmd_addr,
    input wire [31:0] c1_cmd_len,
    input wire [255:0] c1_data,
    output wire c1_cmd_ready,
    output wire c1_done, output wire c1_bac, output wire c1_data_re,

    output wire ctrl_cmd_valid,
    output wire [ADDR_WIDTH-1:0] ctrl_cmd_addr,
    output wire [31:0] ctrl_cmd_len,
    input wire ctrl_cmd_ready,
    input wire ctrl_done, input wire ctrl_bac, input wire ctrl_data_re,
    output wire [255:0] ctrl_data
);
    reg transaction_active;
    reg owner;
    // The client selected next when both have work.  Toggle only after a
    // completed transaction, which gives starvation-free write arbitration.
    reg next_grant;
    wire grant = c1_cmd_valid && (!c0_cmd_valid || next_grant);
    wire selected_valid = grant ? c1_cmd_valid : c0_cmd_valid;
    wire command_fire = !transaction_active && selected_valid && ctrl_cmd_ready;

    assign ctrl_cmd_valid = rst_n && !transaction_active && selected_valid;
    assign ctrl_cmd_addr = grant ? c1_cmd_addr : c0_cmd_addr;
    assign ctrl_cmd_len = grant ? c1_cmd_len : c0_cmd_len;
    assign c0_cmd_ready = rst_n && !transaction_active && !grant && ctrl_cmd_ready;
    assign c1_cmd_ready = rst_n && !transaction_active && grant && ctrl_cmd_ready;

    assign ctrl_data = owner ? c1_data : c0_data;
    assign c0_done = transaction_active && !owner && ctrl_done;
    assign c1_done = transaction_active && owner && ctrl_done;
    assign c0_bac = transaction_active && !owner && ctrl_bac;
    assign c1_bac = transaction_active && owner && ctrl_bac;
    assign c0_data_re = transaction_active && !owner && ctrl_data_re;
    assign c1_data_re = transaction_active && owner && ctrl_data_re;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            transaction_active <= 1'b0;
            owner <= 1'b0;
            next_grant <= 1'b0;
        end else begin
            if (!transaction_active && command_fire) begin
                transaction_active <= 1'b1;
                owner <= grant;
            end else if (transaction_active && ctrl_done) begin
                transaction_active <= 1'b0;
                next_grant <= ~owner;
            end
        end
    end
endmodule

// One DDR read-command/data channel shared by cache fetches (client 0) and
// display prefetches (client 1).  Client 1 has idle-cycle priority so HDMI
// prefetch cannot be delayed behind a newly-arriving cache request.  Once a
// command is accepted, every data beat, ready and completion signal remains
// owned by that client until ctrl_done.
module ddr_two_client_read_arbiter #(
    parameter integer ADDR_WIDTH = 28
) (
    input wire clk, input wire rst_n,

    input wire c0_cmd_valid,
    input wire [ADDR_WIDTH-1:0] c0_cmd_addr,
    input wire [31:0] c0_cmd_len,
    output wire c0_cmd_ready,
    input wire c0_data_ready,
    output wire c0_data_valid, output wire [255:0] c0_data,
    output wire c0_done,

    input wire c1_cmd_valid,
    input wire [ADDR_WIDTH-1:0] c1_cmd_addr,
    input wire [31:0] c1_cmd_len,
    output wire c1_cmd_ready,
    input wire c1_data_ready,
    output wire c1_data_valid, output wire [255:0] c1_data,
    output wire c1_done,

    output wire ctrl_cmd_valid,
    output wire [ADDR_WIDTH-1:0] ctrl_cmd_addr,
    output wire [31:0] ctrl_cmd_len,
    input wire ctrl_cmd_ready,
    output wire ctrl_data_ready,
    input wire ctrl_data_valid, input wire [255:0] ctrl_data,
    input wire ctrl_done
);
    reg transaction_active;
    reg owner;
    // Display read priority only applies while no command owns the channel.
    wire grant = c1_cmd_valid;
    wire selected_valid = grant ? c1_cmd_valid : c0_cmd_valid;
    wire command_fire = !transaction_active && selected_valid && ctrl_cmd_ready;

    assign ctrl_cmd_valid = rst_n && !transaction_active && selected_valid;
    assign ctrl_cmd_addr = grant ? c1_cmd_addr : c0_cmd_addr;
    assign ctrl_cmd_len = grant ? c1_cmd_len : c0_cmd_len;
    assign c0_cmd_ready = rst_n && !transaction_active && !grant && ctrl_cmd_ready;
    assign c1_cmd_ready = rst_n && !transaction_active && grant && ctrl_cmd_ready;

    assign ctrl_data_ready = transaction_active &&
                             (owner ? c1_data_ready : c0_data_ready);
    assign c0_data_valid = transaction_active && !owner && ctrl_data_valid;
    assign c1_data_valid = transaction_active && owner && ctrl_data_valid;
    assign c0_data = ctrl_data;
    assign c1_data = ctrl_data;
    assign c0_done = transaction_active && !owner && ctrl_done;
    assign c1_done = transaction_active && owner && ctrl_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            transaction_active <= 1'b0;
            owner <= 1'b0;
        end else begin
            if (!transaction_active && command_fire) begin
                transaction_active <= 1'b1;
                owner <= grant;
            end else if (transaction_active && ctrl_done) begin
                transaction_active <= 1'b0;
            end
        end
    end
endmodule
