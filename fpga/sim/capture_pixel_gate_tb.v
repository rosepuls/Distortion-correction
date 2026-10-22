`timescale 1ns / 1ps

module capture_pixel_gate_tb;
    reg pix_clk = 1'b0;
    always #7 pix_clk = ~pix_clk;
    reg rstn = 1'b0;
    reg vs_in = 1'b0;
    reg de_in = 1'b0;
    reg allow_capture_ddr = 1'b0;
    wire wr_en;
    wire frame_admitted;

    capture_pixel_gate dut (
        .pix_clk(pix_clk), .rstn(rstn), .vs_in(vs_in), .de_in(de_in),
        .allow_capture_ddr(allow_capture_ddr), .wr_en(wr_en),
        .frame_admitted(frame_admitted)
    );

    task tick;
        begin @(posedge pix_clk); #1; end
    endtask
    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    initial begin
        tick(); tick();
        @(negedge pix_clk);
        rstn = 1'b1;
        allow_capture_ddr = 1'b1;
        de_in = 1'b1;
        repeat (4) tick();
        check(!wr_en, "no capture before first VS");

        @(negedge pix_clk);
        de_in = 1'b0;
        vs_in = 1'b1;
        tick();
        @(negedge pix_clk);
        vs_in = 1'b0;
        repeat (3) tick();
        @(negedge pix_clk);
        de_in = 1'b1;
        #1;
        check(wr_en, "first pixel admitted after blanking");
        tick();
        check(frame_admitted && wr_en, "permission latched for frame");

        @(negedge pix_clk);
        allow_capture_ddr = 1'b0;
        repeat (4) tick();
        check(wr_en, "mid-frame permission withdrawal waits for VS");
        @(negedge pix_clk);
        de_in = 1'b0;
        vs_in = 1'b1;
        tick();
        check(!wr_en && !frame_admitted, "VS closes preceding frame");
        @(negedge pix_clk);
        vs_in = 1'b0;
        repeat (3) tick();
        @(negedge pix_clk);
        de_in = 1'b1;
        #1;
        check(!wr_en, "rejected frame has no first pixel");
        tick();
        check(!frame_admitted && !wr_en, "rejected frame stays rejected");

        @(negedge pix_clk);
        allow_capture_ddr = 1'b1;
        repeat (4) tick();
        check(!wr_en, "mid-frame permission cannot create partial frame");
        @(negedge pix_clk);
        de_in = 1'b0;
        vs_in = 1'b1;
        tick();
        @(negedge pix_clk);
        vs_in = 1'b0;
        repeat (3) tick();
        @(negedge pix_clk);
        de_in = 1'b1;
        #1;
        check(wr_en, "next complete frame is admitted");

        $display("PASS: capture_pixel_gate whole-frame gating test");
        $finish;
    end
endmodule
