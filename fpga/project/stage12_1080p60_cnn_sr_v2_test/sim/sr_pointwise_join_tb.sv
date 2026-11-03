`timescale 1ns/1ps
module sr_pointwise_join_tb;
    localparam W=16,H=16,N=W*H;
    reg clk=0; always #5 clk=~clk;
    reg rstn=0,s_valid=0; wire pw_s_ready,join_s_ready;
    wire pw_input_valid=s_valid&&join_s_ready;
    wire join_input_valid=s_valid&&pw_s_ready;
    reg [63:0] s_features=0,s_skip=0;
    reg [10:0] s_x=0; reg [9:0] s_y=0; reg [20:0] s_pixel_id=0;
    reg [31:0] s_frame_id=32'h13572468;
    reg s_sof=0,s_eol=0,s_eof=0;
    wire pw_valid,join_valid; reg pw_ready=0,join_ready=0;
    wire [63:0] pw_features,join_features;
    wire [63:0] pw_skip;
    wire [10:0] pw_x,join_x; wire [9:0] pw_y,join_y;
    wire [20:0] pw_id,join_id; wire [31:0] pw_frame,join_frame;
    wire pw_sof,pw_eol,pw_eof,join_sof,join_eol,join_eof;
    reg [7:0] depthwise[0:8*N-1], stem[0:8*N-1], expected_pw[0:8*N-1], expected_join[0:8*N-1];
    integer accepted=0,produced_pw=0,produced_join=0,cycle=0,cc,index;
    sr_pointwise_conv pw(
      .clk(clk),.rstn(rstn),.s_valid(pw_input_valid),.s_ready(pw_s_ready),.s_features(s_features),.s_skip(s_skip),
      .s_x(s_x),.s_y(s_y),.s_pixel_id(s_pixel_id),.s_frame_id(s_frame_id),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),
      .m_valid(pw_valid),.m_ready(pw_ready),.m_features(pw_features),.m_skip(pw_skip),.m_x(pw_x),.m_y(pw_y),
      .m_pixel_id(pw_id),.m_frame_id(pw_frame),.m_sof(pw_sof),.m_eol(pw_eol),.m_eof(pw_eof));
    reg [63:0] join_branch;
    always @* for(integer c=0;c<8;c=c+1) join_branch[c*8 +: 8]=expected_pw[c*N+s_pixel_id];
    sr_residual_join #(.BLOCK_INDEX(0)) join_dut(
      .clk(clk),.rstn(rstn),.s_valid(join_input_valid),.s_ready(join_s_ready),.s_skip(s_skip),.s_branch(join_branch),
      .s_x(s_x),.s_y(s_y),.s_pixel_id(s_pixel_id),.s_frame_id(s_frame_id),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),
      .m_valid(join_valid),.m_ready(join_ready),.m_features(join_features),.m_x(join_x),.m_y(join_y),
      .m_pixel_id(join_id),.m_frame_id(join_frame),.m_sof(join_sof),.m_eol(join_eol),.m_eof(join_eof));
    initial begin
      $readmemh("../../../source/rtl/sr/weights/block1_depthwise_u8.hex",depthwise);
      $readmemh("../../../source/rtl/sr/weights/stem_u8.hex",stem);
      $readmemh("../../../source/rtl/sr/weights/block1_pointwise_u8.hex",expected_pw);
      $readmemh("../../../source/rtl/sr/weights/block1_output_u8.hex",expected_join);
      repeat(4) @(negedge clk); rstn=1;
      for(integer i=0;i<N;i=i+1) begin
        @(negedge clk); s_valid=1; s_x=i%W; s_y=i/W; s_pixel_id=i;
        s_sof=(i==0);s_eol=((i%W)==W-1);s_eof=(i==N-1);
        for(integer c=0;c<8;c=c+1) begin
          s_features[c*8 +: 8]=depthwise[c*N+i]; s_skip[c*8 +: 8]=stem[c*N+i];
        end
        do @(posedge clk); while(!(pw_s_ready&&join_s_ready)); accepted=accepted+1;
      end
      @(negedge clk);s_valid=0;
    end
    always @(negedge clk) begin cycle=cycle+1; pw_ready=(cycle%7!=0)&&(cycle%13!=0); join_ready=(cycle%5!=0)&&(cycle%11!=0); end
    always @(posedge clk) if(rstn) begin
      if(pw_valid&&pw_ready) begin
        if(pw_id!==produced_pw || pw_x!==(produced_pw%W) || pw_y!==(produced_pw/W) || pw_frame!==32'h13572468 ||
           pw_sof!==(produced_pw==0) || pw_eol!==((produced_pw%W)==W-1) || pw_eof!==(produced_pw==N-1))
          $fatal(1,"pointwise metadata mismatch index=%0d got id=%0d xy=%0d,%0d markers=%b%b%b",produced_pw,pw_id,pw_x,pw_y,pw_sof,pw_eol,pw_eof);
        for(cc=0;cc<8;cc=cc+1) if(pw_features[cc*8 +: 8]!==expected_pw[cc*N+produced_pw]) begin
          $fatal(1,"pointwise golden mismatch pixel=%0d channel=%0d got=%0d expected=%0d",produced_pw,cc,pw_features[cc*8 +: 8],expected_pw[cc*N+produced_pw]);
        end
        produced_pw=produced_pw+1;
      end
      if(join_valid&&join_ready) begin
        if(join_id!==produced_join || join_x!==(produced_join%W) || join_y!==(produced_join/W) || join_frame!==32'h13572468 ||
           join_sof!==(produced_join==0) || join_eol!==((produced_join%W)==W-1) || join_eof!==(produced_join==N-1))
          $fatal(1,"join metadata mismatch index=%0d",produced_join);
        for(cc=0;cc<8;cc=cc+1) if(join_features[cc*8 +: 8]!==expected_join[cc*N+produced_join])
          $fatal(1,"join golden mismatch pixel=%0d channel=%0d got=%0d expected=%0d",produced_join,cc,join_features[cc*8 +: 8],expected_join[cc*N+produced_join]);
        produced_join=produced_join+1;
      end
      if(cycle>10000) $fatal(1,"timeout accepted=%0d pw=%0d join=%0d",accepted,produced_pw,produced_join);
      if(produced_pw==N && produced_join==N) begin
        $display("PASS: block1 pointwise and residual join golden vectors, metadata, and backpressure"); $finish;
      end
    end
endmodule
