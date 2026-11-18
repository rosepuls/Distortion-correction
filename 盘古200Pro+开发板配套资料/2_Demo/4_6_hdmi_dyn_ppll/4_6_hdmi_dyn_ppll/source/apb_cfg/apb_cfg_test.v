//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: apb_cfg
// Project Name: hdmi_dyn_ppll
// Target Devices: Pango PG2L100H-6FBG676
// Tool Versions: PDS 2022.2-SP6.4
// Description: Dynamically control the resolution of HDMI 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
module apb_cfg(
input			  clk				 ,
input			  rst_n				 ,
input			  cfg_en			 ,
input    [7:0]    key_cnt,
input             apb_rdy            ,
input   [15:0]    apb_rdata       /* synthesis syn_preserve = 1 */   ,  
output  [4:0]     apb_addr           ,
output            apb_sel            , 
output            apb_en             , 
output            apb_write          ,
output  [15:0]    apb_wdata          ,
output            abp_cfg_rst        ,
output            cfg_start          ,
output            cfg_done           ,
output  reg[4:0]     cstate             , 
output  reg[4:0]     nstate             

);
//-------------------------------------------------------------------------------------
//参数配置参考时钟UG章节GPLL使用说明中GTP_GPLL APB接口配置小节详细功能说明
//
// case0：clkout0 Fre:80Mhz;duty:60% Phase:45
reg [7:0]odiv_ratio/* synthesis syn_preserve = 1 */ ;
reg [7:0]odiv_duty/* synthesis syn_preserve = 1 */ ;
reg [2:0]odiv_fracdiv_ratio/* synthesis syn_preserve = 1 */ ;

reg [7:0]fdiv_ratio/* synthesis syn_preserve = 1 */ ;
reg [7:0]fdiv_duty/* synthesis syn_preserve = 1 */ ;
reg [2:0]fdiv_fracdiv_ratio/* synthesis syn_preserve = 1 */ ;
reg [7:0]idiv;
reg [7:0]mdiv;
reg [2:0]fdiv_fracdiv_psoffset;
always @ (posedge clk )
begin
    case(key_cnt)
    8'd1://1280*800P60    pixclk=83.5M//88.8
    begin
        odiv_ratio         <= 8'd22;
        odiv_duty          <= 8'd22;


        fdiv_ratio         <= 8'd34;
        fdiv_duty          <= 8'd34;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd2://1360*768P60	    pixclk=85.5M
    begin
        odiv_ratio         <= 8'd24;
        odiv_duty          <= 8'd24;


        fdiv_ratio         <= 8'd38;
        fdiv_duty          <= 8'd38;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd3://1400*1050P60	    pixclk=101M
    begin
        odiv_ratio         <= 8'd19;
        odiv_duty          <= 8'd19;


        fdiv_ratio         <= 8'd71;
        fdiv_duty          <= 8'd71;

        idiv               <= 8'd1;
        mdiv               <= 8'd1;
    end
    8'd4://1440*900P60	    pixclk=88.75M
    begin
        odiv_ratio         <= 8'd21;
        odiv_duty          <= 8'd21;


        fdiv_ratio         <= 8'd69;
        fdiv_duty          <= 8'd69;

        idiv               <= 8'd1;
        mdiv               <= 8'd1;
    end
    8'd5://1600*900P60	    pixclk=108M
    begin
        odiv_ratio         <= 8'd19;
        odiv_duty          <= 8'd19;


        fdiv_ratio         <= 8'd38;
        fdiv_duty          <= 8'd38;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd6://1600*1200P60    pixclk=162M
    begin
        odiv_ratio         <= 8'd13;
        odiv_duty          <= 8'd13;


        fdiv_ratio         <= 8'd39;
        fdiv_duty          <= 8'd39;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd7://1680*1050P60    pixclk=119M
    begin
        odiv_ratio         <= 8'd17;
        odiv_duty          <= 8'd17;


        fdiv_ratio         <= 8'd75;
        fdiv_duty          <= 8'd75;

        idiv               <= 8'd1;
        mdiv               <= 8'd1;
    end
    8'd8://1280*720P60    pixclk=74.25M
    begin
        odiv_ratio         <= 8'd24;
        odiv_duty          <= 8'd24;


        fdiv_ratio         <= 8'd33;
        fdiv_duty          <= 8'd33;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd9://1920*1080P60    pixclk=148.5M
    begin
        odiv_ratio         <= 8'd12;
        odiv_duty          <= 8'd12;


        fdiv_ratio         <= 8'd33;
        fdiv_duty          <= 8'd33;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;
    end
    8'd10://1920*1200P60    pixclk=154M
    begin
        odiv_ratio         <= 8'd10;
        odiv_duty          <= 8'd10;


        fdiv_ratio         <= 8'd57;
        fdiv_duty          <= 8'd57;

        idiv               <= 8'd1;
        mdiv               <= 8'd1;
    end
    default: //1920*1080P60    pixclk=148.5M
    begin
        odiv_ratio         <= 8'd12;
        odiv_duty          <= 8'd12;


        fdiv_ratio         <= 8'd33;
        fdiv_duty          <= 8'd33;

        idiv               <= 8'd1;
        mdiv               <= 8'd2;

    end
    endcase
end



//case1：clkout0 Fre:80Mhz;duty:30% Phase:0
localparam	ODIV0_RATIO				= 8'd10;//分频比设置
localparam	ODIV0_DUTY				= 8'd10;//占空比设置
localparam	ODIV0_RESERVED			= 5'd0;
localparam	ODIV0_MUXSEL_EN			= 1'd1;//输入时钟MUX使能
localparam	ODIV0_FPHASE			= 3'd0;//相位细调设置
localparam	ODIV0_CPHASE			= 7'd0;//相位粗调设置

//CLKIN CFG
localparam	IDIV_RESERVED			= 8'd0;
localparam	IDIV_RATIO				= 8'd1;

//FCLOCK CFG
localparam	FDIV_RATIO				= 8'd40;//分频比设置
localparam	FDIV_DUTY				= 8'd40;//占空比设置
localparam	FDIV_RESERVED			= 5'd0;
localparam	FDIV_MUXSEL_EN			= 1'd1;//输入时钟MUX使能
localparam	FDIV_FPHASE				= 3'd0;//相位细调设置
localparam	FDIV_CPHASE				= 7'd0;//相位粗调设置

localparam	MDIV_RESERVED			= 8'd0;
localparam	MDIV_RATIO				= 8'd1;//分频比设置

//--------------------------------------------------------------------------------


//reg    [4:0] cstate			/* synthesis syn_preserve = 1 */;
//reg    [4:0] nstate			/* synthesis syn_preserve = 1 */;
reg    [6:0] cfg_done_cnt   /* synthesis syn_preserve = 1 */;

reg    [4:0] addr  			/* synthesis syn_preserve = 1 */;
reg          rdy   			/* synthesis syn_preserve = 1 */;
reg          sel   			/* synthesis syn_preserve = 1 */;
reg    [15:0]wdata 			/* synthesis syn_preserve = 1 */;
reg			 apb_wr_r;
reg			 cfg_en_r1;
reg			 cfg_en_r2;
wire	     cfg_en_pos;
reg          cfg_done_r;
reg          cfg_start_r;


//state
   //common state
   localparam   CFG_IDLE     	= 5'b0_0000;
   localparam   ODIV0_CFG1  	= 5'b0_0001;
   localparam   ODIV0_CFG1_RD   = 5'b0_0010;   
   localparam   ODIV0_CFG2  	= 5'b0_0011;
   localparam   ODIV0_CFG2_RD   = 5'b0_0100;     
   localparam   FDIV_CFG1  		= 5'b0_0101;
   localparam   FDIV_CFG1_RD 	= 5'b0_0110;   
   localparam   FDIV_CFG2  		= 5'b0_0111;
   localparam   FDIV_CFG2_RD  	= 5'b0_1000;   
   localparam   IDIV_CFG    	= 5'b0_1001;  
   localparam   IDIV_CFG_RD    	= 5'b0_1010;    
   localparam   MDIV_CFG    	= 5'b0_1011; 
   localparam   MDIV_CFG_RD    	= 5'b0_1100;  
   localparam   CFG_START     	= 5'b1_1110;
   localparam   CFG_DONE    	= 5'b1_1111;    

//state
reg  rdy_nxt;  
always @ (posedge clk or negedge rst_n)
   if(~rst_n)begin
     rdy  <= 1'b0;
     sel  <= 1'b0;
	 cfg_en_r1<=1'b0;
	 cfg_en_r2<=1'b0;
     rdy_nxt<=0;
   end
   else begin
     rdy  <= apb_rdy;
     rdy_nxt <= rdy;
     sel  <= apb_sel;
	 cfg_en_r1<=cfg_en;
	 cfg_en_r2<=cfg_en_r1;
  end

 assign cfg_en_pos = cfg_en_r1&~cfg_en_r2;
 
   always @ (posedge clk or negedge rst_n) begin
     if(!rst_n) cstate <= CFG_IDLE;
     else          cstate <= nstate;
   end
// 

   always @ (*) begin
//	nstate = cstate;
     case(cstate)
        CFG_IDLE            : if(cfg_en_pos)nstate = ODIV0_CFG1; 
                              else nstate = CFG_IDLE;                                 
        CFG_START           : if(apb_rdy) nstate = ODIV0_CFG1;  
                              else nstate = CFG_START;         
        ODIV0_CFG1          : if(apb_rdy) nstate = ODIV0_CFG1_RD;
                              else nstate = ODIV0_CFG1;  
        ODIV0_CFG1_RD       : if(apb_rdy) nstate = ODIV0_CFG2;
                              else nstate = ODIV0_CFG1_RD;
        ODIV0_CFG2          : if(apb_rdy) nstate = ODIV0_CFG2_RD;
                              else nstate = ODIV0_CFG2;
        ODIV0_CFG2_RD       : if(apb_rdy) nstate = FDIV_CFG1;
                              else nstate = ODIV0_CFG2_RD;
        FDIV_CFG1           : if(apb_rdy) nstate = FDIV_CFG1_RD;
                              else nstate = FDIV_CFG1;
        FDIV_CFG1_RD        : if(apb_rdy) nstate = FDIV_CFG2;	
                              else nstate = FDIV_CFG1_RD;				  
        FDIV_CFG2           : if(apb_rdy) nstate = FDIV_CFG2_RD;
                              else nstate = FDIV_CFG2;	
        FDIV_CFG2_RD        : if(apb_rdy) nstate = IDIV_CFG;
                              else nstate = FDIV_CFG2_RD;	
        IDIV_CFG            : if(apb_rdy) nstate = IDIV_CFG_RD;
                              else nstate = IDIV_CFG;
        IDIV_CFG_RD         : if(apb_rdy) nstate = MDIV_CFG;
                              else nstate = IDIV_CFG_RD;
        MDIV_CFG            : if(apb_rdy) nstate = MDIV_CFG_RD;
                              else nstate = MDIV_CFG;
        MDIV_CFG_RD         : if(apb_rdy) nstate = CFG_DONE;
                              else nstate = MDIV_CFG_RD;
        CFG_DONE         	: if(cfg_done_cnt=='d5) nstate = CFG_IDLE;	
                              else nstate = CFG_DONE;						  
        default             : nstate = CFG_IDLE;
     endcase
   end

   always @ (posedge clk or negedge rst_n) begin
     if(!rst_n) begin
       wdata <= 8'd0;
       addr  <= 5'h1f;
	   apb_wr_r<=0;
       cfg_done_cnt<=0;
       cfg_done_r<=0;
       cfg_start_r<=0; 
     end
     else begin
//         case(cstate)
         case(nstate)
            CFG_IDLE      : begin
                               wdata <= 8'd0;
                               addr  <= 5'h1f;
	                           apb_wr_r<=0;
                               cfg_done_cnt<=0;
                              end
            ODIV0_CFG1      : begin
								wdata <= {odiv_ratio,odiv_duty};//{ODIV0_RATIO,ODIV0_DUTY};
								addr  <= 'd0; 
								apb_wr_r<=1;
                                cfg_start_r<=1;
                              end
            ODIV0_CFG1_RD   : begin 
								wdata <= 'd0;
								addr  <= 'h0;
								apb_wr_r<=0;
                              end
            ODIV0_CFG2      : begin
								wdata <= {ODIV0_RESERVED,ODIV0_MUXSEL_EN,ODIV0_FPHASE,ODIV0_CPHASE};
								addr  <= 'd1;
								apb_wr_r<=1;
                              end
            ODIV0_CFG2_RD   : begin
								wdata <= 'd0;
								addr  <= 'h1;
							    apb_wr_r<=0;
                              end	
            FDIV_CFG1       : begin
								wdata <= {fdiv_ratio,fdiv_duty};//{FDIV_RATIO,FDIV_DUTY};
								addr  <= 'hc;
								apb_wr_r<=1;								
                              end
            FDIV_CFG1_RD    : begin 
								wdata <= 'h0;
								addr  <= 'hc;
								apb_wr_r<=0;
                              end
            FDIV_CFG2       : begin
								wdata <= {FDIV_RESERVED,FDIV_MUXSEL_EN,FDIV_FPHASE,FDIV_CPHASE};
								addr  <= 'hd;
								apb_wr_r<=1;
                              end
            FDIV_CFG2_RD    : begin
								wdata <= 'd0;
								addr  <= 'hd;
								apb_wr_r<=0;								
                              end
            IDIV_CFG        : begin
								wdata <= {IDIV_RESERVED,idiv};
								addr  <= 'he;
								apb_wr_r<=1;
                              end
            IDIV_CFG_RD     : begin
								wdata <= 'd0;
								addr  <= 'he;
								apb_wr_r<=0;								
                              end
            MDIV_CFG        : begin 
                                wdata <= {MDIV_RESERVED,mdiv};
                                addr  <= 'hf;
								apb_wr_r<=1;
                              end
            MDIV_CFG_RD     : begin
                                wdata <= 'd0;
                                addr  <= 'hf;
								apb_wr_r<=0;
                              end 
            CFG_DONE        : begin
                                wdata<= 'd0;
                                addr<= 'h1f;
								apb_wr_r<=0;
                                cfg_done_r<=1;
                                cfg_done_cnt<=cfg_done_cnt+1;
                              end							 
            default        : begin
								wdata <= 'd0;
								addr  <= 5'h1f;
                             end  
         endcase
     end
   end


   assign apb_addr  = addr;
   assign apb_sel   = (cfg_en_pos||cstate)&&cstate!=CFG_DONE ? 1'b1 : 1'b0;
   assign apb_en    = ((apb_sel && !sel) || rdy || !apb_sel || !cstate||cstate==CFG_DONE)? 1'b0 : 1'b1;
//   assign apb_en    = ((apb_sel && !sel) || rdy_nxt || !apb_sel || !cstate||cstate==CFG_DONE)? 1'b0 : 1'b1;
   assign apb_write    = apb_wr_r;
   assign apb_wdata = wdata;
   assign abp_cfg_rst = (nstate!=CFG_IDLE)?1'b1:1'b0;

   assign cfg_done = cfg_done_r;
   assign cfg_start = cfg_start_r;



endmodule
