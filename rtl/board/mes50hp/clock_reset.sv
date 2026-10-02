`timescale 1ns/1ps

// Asynchronous assertion and two-clock synchronous release for one clock domain.
module mes50hp_reset_sync (
    input  wire clk,
    input  wire reset_n,
    output wire rst_n
);
    reg [1:0] reset_release;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end

    assign rst_n = reset_release[1];
endmodule
