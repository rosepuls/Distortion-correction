`timescale 1ns / 1ps

module stage4_demo_full_frame_tb;
    localparam W=1280; localparam H=720; localparam CENTER_ID=360*1280+640;
    reg clk=0; always #4 clk=~clk;
    reg rstn=0,frame_sync=0,active=0;
    wire pixel_valid; wire [31:0] pixel; wire [19:0] pixel_id;
    wire frame_complete,input_stall,sequence_error;
    stage4_demo_frame_source dut(
        .clk(clk),.rstn(rstn),.frame_sync(frame_sync),.active_video(active),
        .pixel_valid(pixel_valid),.pixel(pixel),.pixel_id(pixel_id),
        .frame_complete(frame_complete),.input_stall(input_stall),.sequence_error(sequence_error)
    );
    task automatic check;
        input condition; input [8*120-1:0] message;
        begin if(condition!==1'b1) begin $display("FAIL at %0t: %0s",$time,message); $fatal(1); end end
    endtask
    integer row,col,received=0,complete_count=0,timeout=0;
    always @(posedge clk) begin
        #1;
        if(pixel_valid) begin
            check(pixel_id===received,"720p output pixel IDs stay contiguous");
            if(received==0) check(pixel===32'h00000000,"top-left radial sample is black");
            if(received==CENTER_ID) check(pixel===32'hffffff00,"optical center is white grid crossing");
            if(received==W*H-1) check(pixel===32'h00000000,"bottom-right radial sample is black");
            received=received+1;
        end
        if(frame_complete) complete_count=complete_count+1;
    end
    initial begin
        repeat(2) @(posedge clk);
        @(negedge clk); rstn=1; frame_sync=1;
        @(posedge clk); @(negedge clk); frame_sync=0;
        for(row=0;row<H;row=row+1) begin
            active=1;
            for(col=0;col<W;col=col+1) @(posedge clk);
            @(negedge clk); active=0;
            repeat(8) @(posedge clk);
            @(negedge clk);
        end
        while(received<W*H&&timeout<100) begin @(posedge clk); timeout=timeout+1; end
        #2;
        check(received==W*H,"all 921600 output pixels produced");
        check(complete_count==1,"one 720p frame completion produced");
        check(!input_stall&&!sequence_error,"full frame has no stall or ordering error");
        $display("PASS: stage4 demo full 1280x720 frame produced 921600 ordered pixels");
        $finish;
    end
endmodule
