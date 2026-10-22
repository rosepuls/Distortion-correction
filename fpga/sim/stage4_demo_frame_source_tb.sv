`timescale 1ns / 1ps

module stage4_demo_frame_source_tb;
    localparam W=8; localparam H=4;
    reg clk=0; always #4 clk=~clk;
    reg rstn=0, frame_sync=0, active=0;
    wire pixel_valid; wire [31:0] pixel; wire [19:0] pixel_id;
    wire frame_complete, input_stall, sequence_error;

    stage4_demo_frame_source #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.FIFO_DEPTH(4)) dut (
        .clk(clk),.rstn(rstn),.frame_sync(frame_sync),.active_video(active),
        .pixel_valid(pixel_valid),.pixel(pixel),.pixel_id(pixel_id),
        .frame_complete(frame_complete),.input_stall(input_stall),.sequence_error(sequence_error)
    );

    task automatic check;
        input condition; input [8*120-1:0] message;
        begin if(condition!==1'b1) begin $display("FAIL at %0t: %0s",$time,message); $fatal(1); end end
    endtask

    integer row,col,received=0,frame_done_count=0,cycles=0;
    initial begin
        repeat(2) @(posedge clk);
        @(negedge clk); rstn=1; frame_sync=1;
        @(posedge clk); @(negedge clk); frame_sync=0;
        for(row=0;row<H;row=row+1) begin
            active=1;
            for(col=0;col<W;col=col+1) @(posedge clk);
            @(negedge clk); active=0;
            repeat(3) @(posedge clk);
            @(negedge clk);
        end
        active=0;
        while(received<W*H && cycles<80) begin
            @(posedge clk); #2; cycles=cycles+1;
        end
        check(received==W*H,"all active input pixels produced outputs");
        check(frame_done_count==1,"exactly one frame-complete pulse produced");
        check(!input_stall,"one-pixel-per-clock input never stalled");
        check(!sequence_error,"output sequence stayed ordered");
        @(negedge clk); rstn=0;
        @(posedge clk); #1;
        check(!pixel_valid,"reset flushes frame source pipeline");
        $display("PASS: stage4_demo_frame_source complete raster timing test");
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if(pixel_valid) begin
            check(pixel_id===received,"live output pixel ID matches raster order");
            received=received+1;
        end
        if(frame_complete) frame_done_count=frame_done_count+1;
    end
endmodule
