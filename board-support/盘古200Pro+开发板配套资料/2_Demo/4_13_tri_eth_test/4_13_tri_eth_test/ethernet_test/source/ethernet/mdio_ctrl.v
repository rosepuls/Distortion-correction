`timescale 1ns/1ps
/*//////////////////////////////////////////////////////////////////////////////////////////


*//////////////////////////////////////////////////////////////////////////////////////////
`define UD #1 
module mdio_ctrl#(
	parameter MDC_120MS    = 1000_000                  //mdc时钟，每隔120ms轮询一次       
)(
    input                       i_clk                  ,//mdc
    input                       i_rst_n               /*synthesis PAP_MARK_DEBUG="1"*/ ,

    output                      mdc                    ,
    inout                       mdio                   ,
    //读取寄存器
    output  reg [1:0]           eth_status  /*synthesis PAP_MARK_DEBUG="1"*/            //10:1000mbps   01:100mbps   00:10mbps

);

    reg                start          /*synthesis PAP_MARK_DEBUG="1"*/; 
    reg [1:0]         opcode           /*synthesis PAP_MARK_DEBUG="1"*/; //2'b10 : Read; 2'b01:Write
    wire [4:0]         phy_addr       =5'b00001; //5'b00001
    reg [4:0]         reg_addr       /*synthesis PAP_MARK_DEBUG="1"*/; //8'h11:PHY Status
    reg [15:0]        write_data     /*synthesis PAP_MARK_DEBUG="1"*/; //
    wire [15:0]        read_data      /*synthesis PAP_MARK_DEBUG="1"*/; 
    wire               read_data_en   /*synthesis PAP_MARK_DEBUG="1"*/; 
    wire               ready          ; 

	reg					read_data_en_d;
	
	
	
	reg	[23:0]	cycle_cnt;
	reg			cycle_done/*synthesis PAP_MARK_DEBUG="1"*/;

	//定时查询状态
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			cycle_cnt <= 1'b0;
			cycle_done <= 'd0;
		end
		else begin
			if(cycle_cnt == 24'd1_000_000 - 1'b1) begin
				cycle_done <= 1'b1;
				cycle_cnt <= 'd0;
			end
			else begin
				cycle_done <= 1'b0;
				cycle_cnt <= cycle_cnt + 1'b1;
			end
		end
	end  
	

	reg	[3:0]			state	/*synthesis PAP_MARK_DEBUG="1"*/;
	wire				write_done;
	wire				read_done;
	//状态机控制

	reg		set_addr;
    reg     default_testr/*synthesis PAP_MARK_DEBUG="1"*/;
    reg     check_flag/*synthesis PAP_MARK_DEBUG="1"*/;



	always@(posedge i_clk or negedge i_rst_n)	begin
		if(!i_rst_n)
            set_addr    <=    1'd1;
        else    if(read_data == 16'h0a43)
            set_addr    <=    1'd0;
        else
            set_addr    <=    set_addr;
    end

	always@(posedge i_clk or negedge i_rst_n)	begin
		if(!i_rst_n)
		begin	
			state		<=	4'd0;	
			reg_addr	<=	5'd0;
			write_data	<=	16'd0;
			opcode		<=	2'd0;
            check_flag  <=  1'd0;  
            default_testr<=1'd0;
            eth_status  <=  2'd0;
		end
		else
		begin
			case(state)
				4'd0:	begin
							if(set_addr)
							begin
								opcode		<=	2'b01	;	//write
								reg_addr	<=	5'h1f	;	//切换page
								write_data	<=	16'h0a43;
								state		<=	4'd1	;
							end
							else	if(cycle_done)
							begin
								opcode		<=	2'b10	;	//read
								reg_addr	<=	5'h1a	;
								state		<=	4'd2	;
							end
						end
				
				4'd1:	begin
							if(write_done)
								state	<=	4'd3;
							else
								state	<=	state;
						end
						
				4'd2:	begin
							if(read_data_en)
							begin
								if(read_data[5:4] == 2'b10)
									eth_status	<=	2'b10;	//1000mbps
								else	if(read_data[5:4] == 2'b01)
									eth_status	<=	2'b01;	//100mbps
								else	if(read_data[5:4] == 2'b00)
									eth_status	<=	2'b00;	//10mbps
								state	<=	4'd0;
							end
							else
								state	<=	state;
						end
						
				4'd3:	begin
							opcode		<=	2'b10	;	//read
							reg_addr	<=	5'h1f	;
							state		<=	4'd4	;
						end
				
				4'd4:	begin
							if(read_data_en)
							begin
								if(read_data == 16'h0a43)
								begin
									state		<=	4'd0;
                                    check_flag  <=  1'd1;
								end
								else
								begin
									state		<=	4'd0;
                                    check_flag  <=  1'd0;
								end
							end
							else
							begin
								state	 <=	state;
                                check_flag <= check_flag;
                            end
						end
            default: begin
                        state <= 4'd0;
                        default_testr<=1'd1;
                     end						
			endcase
		end
	end			




    mdio_master_driver mdio_master_driver(
        .clk            (   i_clk          ),// input 50M
        .rstn           (   i_rst_n        ),// input
        .reset_n_done   (   1'b1        ),// input
        .mdc            (   mdc            ),// output
        .mdio           (   mdio            ),// inout
        .start          (   start          ),// input
        .opcode         (   opcode         ),// input[1:0]
        .phy_addr       (   phy_addr       ),// input[4:0]
        .reg_addr       (   reg_addr       ),// input[4:0]
        .write_data     (   write_data     ),// input[15:0]
		.write_done		(	write_done	   ),
		.read_done		(	read_done	   ),
        .read_data      (   read_data      ),// output[15:0]
        .read_data_en   (   read_data_en   ),// output
        .ready          (   ready          ) // output         
    );
    
    reg [22:0] cycle_delay;
    always @(posedge i_clk)
    begin
        if(!i_rst_n)
            cycle_delay <= 'd0;
        else 
        begin
            if(cycle_delay == MDC_120MS - 1)
                cycle_delay <= 'd0;
            else
                cycle_delay <= cycle_delay + 'd1;
        end 
        
        start <= (cycle_delay > MDC_120MS - 30);
    end 
    


///////////////////////////////////////////////////////////////////////////////////////////////////////////
endmodule

