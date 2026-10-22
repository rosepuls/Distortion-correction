`timescale 1ns / 1ps

module stage4_demo_pipeline_tb;
    reg clk=0; always #4 clk=~clk;
    reg rstn=0;
    reg s_valid=0; wire s_ready;
    reg [10:0] s_u=0; reg [9:0] s_v=0;
    reg [19:0] s_pixel_id=0; reg [31:0] s_frame_id=32'h44556677;
    reg [15:0] s_param_version=16'hd004;
    reg s_sof=0,s_eol=0,s_eof=0;
    wire m_valid; reg m_ready=0; wire [31:0] m_pixel;
    wire m_geometry_valid; wire [19:0] m_pixel_id; wire [31:0] m_frame_id;
    wire [15:0] m_param_version; wire m_sof,m_eol,m_eof;
    wire [3:0] fifo_level;

    stage4_demo_pipeline #(.FIFO_DEPTH(8),.LEVEL_WIDTH(4)) dut (
        .clk(clk),.rstn(rstn),.s_valid(s_valid),.s_ready(s_ready),
        .s_u(s_u),.s_v(s_v),.s_pixel_id(s_pixel_id),.s_frame_id(s_frame_id),
        .s_param_version(s_param_version),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),
        .m_valid(m_valid),.m_ready(m_ready),.m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid),.m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id),.m_param_version(m_param_version),
        .m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.fifo_level(fifo_level)
    );

    task automatic check;
        input condition; input [8*120-1:0] message;
        begin if(condition!==1'b1) begin $display("FAIL at %0t: %0s",$time,message); $fatal(1); end end
    endtask

    task automatic set_input;
        input integer index;
        begin
            s_valid=1; s_pixel_id=index; s_sof=(index==0); s_eol=0; s_eof=(index==4);
            case(index)
                0: begin s_u=640;  s_v=360; end
                1: begin s_u=641;  s_v=361; end
                2: begin s_u=1240; s_v=360; end
                3: begin s_u=1000; s_v=500; end
                default: begin s_u=1279; s_v=719; end
            endcase
        end
    endtask

    task automatic check_output;
        input integer index;
        begin
            check(m_pixel_id===index, "pixel order preserved through complete pipeline");
            case(index)
                0: check(m_pixel===32'hffffff00, "radial center grid pixel");
                1: check(m_pixel===32'h8169e800, "near-center gradient pixel");
                2: check(m_pixel===32'hf2689a00, "fractional horizontal interpolation");
                3: check(m_pixel===32'heef61800, "fractional two-dimensional interpolation");
                4: check(m_pixel===32'h00000000, "radial corner becomes black border");
            endcase
            check(m_geometry_valid, "radial coordinates remain geometrically defined");
            check(m_frame_id===32'h44556677 && m_param_version===16'hd004,
                  "frame and parameter metadata preserved");
            check(m_sof===(index==0) && m_eof===(index==4),
                  "frame boundary metadata preserved");
        end
    endtask

    integer send_count=0, receive_count=0, cycle_count=0;
    reg accepted_input;
    initial begin
        repeat(2) @(posedge clk);
        @(negedge clk); rstn=1;
        while(receive_count<5 && cycle_count<100) begin
            // Periodic output stalls exercise every ready path and FIFO storage.
            m_ready=(cycle_count%5)!=3;
            if(send_count<5) set_input(send_count); else s_valid=0;
            #1;
            accepted_input=s_valid&&s_ready;
            if(m_valid&&m_ready) begin
                check_output(receive_count);
                receive_count=receive_count+1;
            end
            @(posedge clk); #1;
            if(accepted_input) send_count=send_count+1;
            cycle_count=cycle_count+1;
        end
        check(send_count==5,"all inputs accepted");
        check(receive_count==5,"all outputs received");
        @(negedge clk); rstn=0; s_valid=0; m_ready=0;
        @(posedge clk); #1;
        check(!m_valid&&!s_ready&&fifo_level==0,"reset flushes complete pipeline");
        $display("PASS: stage4_demo_pipeline radial map through RGBX interpolation test");
        $finish;
    end
endmodule
