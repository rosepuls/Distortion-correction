`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Meyesemi
// Engineer: Nill
// 
// Create Date: 05/03/24 17:12:56
// Design Name: 
// Module Name: mdio_master_driver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module	mdio_master_driver(
   input	                  clk             ,//50M
   input	                  rstn            ,//控制mdc复位
   input                      reset_n_done    ,//控制mdio复位
	
   output                     mdc             ,
   inout	                  mdio            ,

   input                      start           ,//开始传输标志，至少持续一个mdc周期，下降沿mdio开始传输；
   input        [1:0]         opcode          ,//2bits的操作码，10表示读，01表示写；
   input        [4:0]         phy_addr        ,//5bits的PHY地址，5’b0；
   input        [4:0]         reg_addr        ,//5bits的寄存器地址，即要读或写的寄存器；
   input        [15:0]        write_data      ,//写数据；
   output reg			      write_done  	  ,
   output reg			      read_done  	  ,
   
   output reg   [15:0]        read_data       ,//读数据；
   output reg                 read_data_en    ,//

   output reg                 ready            //ready信号，发送数据期间为低电平；	
);
///////////////////////////////////////////////////////////////////////////////////////////////////
reg                 mdio_oe         ;
reg                 mdio_out  =1'b0 ;
wire                mdio_in         ;
reg                 start_next      ;
wire                start_edge      ;
//接口数据缓存
reg [1:0]           st_code   =2'h0 ;//mdio start code
reg [1:0]           ta_code   =2'h0 ;//mdio write code
reg [1:0]           op_code   =2'h0 ;
reg [4:0]           regaddr   =5'h0 ;
reg [4:0]           phyaddr   =5'h0 ; 
reg [15:0]          writedata =16'h0;

reg [7:0]           counter   =8'd0 ;
reg [7:0]           state           /*synthesis PAP_MARK_DEBUG="1"*/;
reg [7:0]           state_next      ;
reg                 reset_n_done_r  ;
reg                 reset_n         ;
///////////////////////////////////////////////////////////////////////////////////////////////////
assign mdio     = mdio_oe ? mdio_out : 1'bz ;// MDIO数据输出或高阻, 0-READ,1-WRITE
assign mdio_in  = mdio    ;



GTP_IOCLKDIV_E2 #(
    .DIV_FACTOR("6") //50M/6=8.33M  120ns
) u_GTP_IOCLKDIV_E2 (
    .CLKDIVOUT(mdc),// OUTPUT  
    .CE(1'b1),       // INPUT  
    .CLKIN(clk),    // INPUT  
    .RST_N(rstn)     // INPUT  
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//reset_n_done同步处理，以下代码由reset_n复位控制；
always  @(posedge mdc)begin
    reset_n_done_r  <=  reset_n_done  ;
    reset_n <=  reset_n_done_r        ;
end
///////////////////////////////////////////////////////////////////////////////////////////////////
//检测star下降沿，mdio开始发送数据；
always @(posedge mdc)begin
	if(!reset_n)begin
		start_next<=0;
	end
	else 
		start_next<=start;
end

assign start_edge= !start_next & start;

///////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//   counter：
//       0-31  ： PREAMBLE  ：32 位前导码，MAC 端发送 32 位逻辑 1，以同步 PHY 芯片；
//       32、33： ST        ：帧开始信号，2’b01；
//       34、35： OP        ：2bits的操作码，10表示读，01表示写；
//       36-40 ： PHYAD     ：5bits的PHY地址，5’b0；
//       41-45 ： REGAD     ：5bits的寄存器地址，即要读或写的寄存器；
//       46、47： TA        ：2bits的TA，两个时钟周期准备；
//       48-63 ： DATA      ：16bits数据，读数据或写数据；            
//   
////////////////////////////////////////////////////////////////////////////////////////////////////
//状态机，mdio读写流程；
parameter PREAMBLE  =   8'b0000_0001 ;//32 位前导码，MAC 端发送 32 位逻辑 1，以同步 PHY 芯片
parameter ST        =	8'b0000_0010 ;//帧开始信号，2’b01
parameter OP        =   8'b0000_0100 ;//2bits的操作码，10表示读，01表示写；
parameter PHYAD     =   8'b0000_1000 ;//5bits的PHY地址，5’b0；
parameter REGAD     =   8'b0001_0000 ;//5bits的寄存器地址，即要读或写的寄存器；
parameter TA        =   8'b0010_0000 ;//2bits的TA，两个时钟周期准备；
parameter DATA      =   8'b0100_0000 ;//16bits数据，读数据或写数据；            
parameter IDLE      =   8'b1000_0000 ;//

//状态转移
always @(posedge mdc)
begin
	if(!reset_n)
	begin
		state<=IDLE;
	end 
	else if(start_edge)
		begin
			state<=PREAMBLE;
			
		end
		
	else
		state<=state_next;
end

always @(posedge mdc)
begin
	if(!reset_n)
	begin 
		counter<=8'd0;
	end
    else if(write_done)
      counter <= 8'd0;  
	else if(counter==8'd64)//8'd64
	begin
		counter<=8'd0;
	end
	else if(state!=IDLE)
	begin
		counter<=counter+8'd1;
	end		
end

always @(posedge mdc)
begin
	if(!reset_n)
	begin 
		ready <= 1'b0   ;
	end
	else if(state!=IDLE)
	begin
		ready <= 1'b0   ;
	end
    else begin
        ready <= 1'b1   ;
    end    
end

always @(negedge mdc)
begin
	state_next<=state;
	write_done	<=	1'd0;
	read_done	<=	1'd0;
case(state)
	PREAMBLE: 
		begin
			st_code<= 2'b01 ; 
			ta_code<= 2'b10 ;
			op_code<=opcode;//缓存
			regaddr<=reg_addr;
			phyaddr<=phy_addr;
			writedata<=write_data;
			mdio_oe<=1;
			mdio_out<=1;
			if(counter==8'd31)//8'd31
				begin
					state_next<=ST;
				end
		end
	ST:
		begin
			mdio_oe<=1;
			mdio_out<=st_code[1];
			st_code<=st_code<<1;
			if(counter==8'd33)//8'd33
				begin
					state_next<=OP;
				end
		end
	OP:
		begin
			mdio_oe<=1;
			mdio_out<=op_code[1];
			op_code<=op_code<<1;
			if(counter==8'd35)//8'd35
				begin
					state_next<=PHYAD;
				end
		end
	PHYAD:
		begin
			mdio_oe<=1;
			mdio_out<=phyaddr[4];
			phyaddr<=phyaddr<<1;
			if(counter==8'd40)//8'd40
				begin
					state_next<=REGAD;
				end
		end
	REGAD:
		begin
			mdio_oe<=1;
			mdio_out<=regaddr[4];
			regaddr<=regaddr<<1;
			if(counter==8'd45)//8'd45
				begin
					state_next<=TA;
				end
		end
	TA:
		begin
			if(opcode==2'b10)//读
			begin
				mdio_oe<=0;
				if(counter==8'd47)//8'd47
				begin
					state_next<=DATA;
				end
			end
			if(opcode==2'b01)//写
			begin
				mdio_oe<=1;
				mdio_out<=ta_code[1];
				ta_code<=ta_code<<1;
				if(counter==8'd47)//8'd47
				begin
					state_next<=DATA;
				end
			end
		end
	DATA:
		begin
			if(opcode==2'b10)//读取
			begin
				mdio_oe<=0;
				//读取放到外面；
				if(counter==8'd63)//8'd63
				begin
					state_next<=IDLE;
				end
			end
			if(opcode==2'b01)//写入
			begin
				mdio_oe<=1;
				mdio_out<=writedata[15];
				writedata<=writedata<<1;
				if(counter==8'd63)////8'd63
				begin

					write_done <= 1'd1;
					state_next<=IDLE;
				end
			end
		end
	IDLE:
		begin
			write_done <= 1'd0;
			read_done  <= 1'd0;
			mdio_oe<=0;
				if(counter==8'd64)//8'd64
				begin
					state_next<=IDLE;
				end
		end
	default:
		begin
			state_next<=IDLE;
		end	
endcase
end
///////////////////////////////////////////////////////////////////////////////////////////////////	
//读取数据
always @(posedge mdc)
begin
	if(!reset_n|start_edge)
	begin
		read_data<=16'h0;
	end
	else if((state==DATA)&(opcode==2'b10))//(state==DATA)&(opcode==2'b10)  (8'd47<counter||counter<8'd64)&(opcode==2'b10)
	begin
		read_data<={read_data[14:0],mdio_in};
	end
	else 
    begin
		read_data<=read_data;
    end
end

always @(posedge mdc)
begin
	if(!reset_n)
	begin
		read_data_en<=1'b0;
	end
	else if((counter==8'd63)&(opcode==2'b10)&(write_done!=1))
	begin
		read_data_en<=1'b1;
	end
	else 
		read_data_en<=1'b0;
end
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule	


