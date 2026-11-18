//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_sample_ctrl
(
	input				clk,
	input				rstn,
	input				state_vld,
	input				metastate,
	input		[6:0]	state_loc,
	input				clr,
	output	reg			boundary_end,
	output	reg	[6:0]	right_step
);

reg		[1:0]	 boundary_info;
reg		[5:0]	 boundary_state /* synthesis syn_preserve = 1 */;
reg      [3:0] temp_meta_d;
reg		[1:0] state_vld_d;
reg		[6:0]	state_loc_d0;
reg		[6:0]	state_loc_d1;
reg		[6:0]	state_loc_d2;
reg		[6:0]	state_loc_d3;
reg		[4:0]	curr_state /* synthesis syn_preserve = 1 */;
reg		[4:0]	next_state;
reg		[1:0]	boun_cnt/* synthesis syn_preserve = 1 */;
reg		[6:0]	boun_loc	[2:0]/* synthesis syn_preserve = 1 */;
reg				temp_meta_1;
reg				temp_meta_2;
parameter		 IDLE	    	 =	5'b00001,
				    SEEK_BOUN	 =	5'b00010,
				    FIND_BOUN1 =	5'b00100,
				    FIND_BOUN2 =	5'b01000,
				    SEEK_END	=	5'b10000;

always @(posedge clk or negedge rstn)
	if(!rstn | clr)
		  temp_meta_d	<=	4'b0;
	else if(state_vld)
		  temp_meta_d	<=	{temp_meta_d[2:0],metastate};

always @(posedge clk or negedge rstn)
	if(!rstn | clr)
		  state_vld_d	<=	2'b0;
	else
		  state_vld_d	<=	{state_vld_d[0],state_vld};
		
always @(posedge clk or negedge rstn)
	if(!rstn | clr)
	begin
	    state_loc_d0 <= 7'd0;
	    state_loc_d1 <= 7'd0;
	    state_loc_d2 <= 7'd0;
	    state_loc_d3 <= 7'd0;
	end
	else if(state_vld)
	begin
	    state_loc_d0 <= state_loc   ;
	    state_loc_d1 <= state_loc_d0;
	    state_loc_d2 <= state_loc_d1;
	    state_loc_d3 <= state_loc_d2;
	end			
			
//--------------state machine--------------------------------	
//--------------state transform------------------------------	
always @(posedge clk or negedge rstn)
	if(!rstn | clr)
		curr_state	<=	IDLE;
	else
		curr_state	<=	next_state;

always @(*)
begin
	case(curr_state)
		IDLE:		  begin
						    if(((state_vld_d[0]==1) && (state_loc_d0<=7'd2)) || (state_vld_d[0]==0))
						    	  next_state	=	IDLE;
						    else 
						    	  next_state	=	SEEK_BOUN;
					  end
				
		SEEK_BOUN:	begin
						if((state_vld_d[0]==1) && (state_loc_d0<127))
						begin
							if(~temp_meta_d[0] & ~temp_meta_d[1] & ~temp_meta_d[2] & temp_meta_d[3])
								  next_state	=	FIND_BOUN1;
							else if(temp_meta_d[0] & ~temp_meta_d[1] & ~temp_meta_d[2] & ~temp_meta_d[3])
								  next_state	=	FIND_BOUN2;
							else
								  next_state	=	SEEK_BOUN;	  						      
						end
						else if(((state_vld_d[0]==1) & (state_loc_d0>=127)) || (boundary_state==6'b110111) || (boundary_state==6'b110100))
							  next_state	=	SEEK_END;
                 else
                      next_state  = SEEK_BOUN;
					   end					
		FIND_BOUN1:		next_state	=	SEEK_BOUN;
		FIND_BOUN2:		next_state	=	SEEK_BOUN;
		SEEK_END:	begin
						if(clr)
							next_state	=	IDLE;
						else
							next_state	=	SEEK_END;
					   end
					
		default:		next_state	=	IDLE;
	endcase
end

//----------------output of state machine----------------------------
always @(posedge clk or negedge rstn)
	if(!rstn | clr)
		boun_cnt	<=	2'b00;
	else if(boundary_info[0])
		boun_cnt	<=	boun_cnt + 1;
		
always @(posedge clk or negedge rstn)
	if(!rstn | clr)
    begin
      boun_loc[0]    <= 7'b0000000;
      boun_loc[1]    <= 7'b0000000;
      boun_loc[2]    <= 7'b0000000;
		boundary_state	<=	6'b000000;
    end
	else if(boundary_info[0])
	begin
		boundary_state	<=	{boundary_info,boundary_state[5:2]};
		boun_loc[boun_cnt]	<=	state_loc_d0;
	end

always @(posedge clk or negedge rstn)
	if(!rstn | clr)
	begin
		boundary_info	<=	2'b00;
		boundary_end	<=	1'b0;
		right_step		<=	7'b0000000;
	end
	else
	begin
		boundary_info	<=	2'b00;
		boundary_end	<=	1'b0;
		case(next_state)
			IDLE:		begin
							boundary_info	<=	2'b00;
							boundary_end	<=	1'b0;
							right_step		<=	7'b0000000;
						end
			SEEK_BOUN:	;
			FIND_BOUN1:	boundary_info	<=2'b01;
			FIND_BOUN2:	boundary_info	<=2'b11;
			SEEK_END:	begin
							boundary_end	<=	1;
							case(boundary_state)
								6'b000000:	right_step	<=	7'd64;
								6'b010000:	right_step	<=	(boun_loc[0] >> 1) + (7'd127 >> 1);
								6'b110000:	right_step	<=	boun_loc[0] >> 1;
								6'b011100:	right_step	<=	((7'd127-boun_loc[1])>=boun_loc[0]) ? ((boun_loc[1]>>1) + (7'd127>> 1)): (boun_loc[0] >> 1);
								6'b110100:	right_step	<=	(boun_loc[1] >> 1) + (boun_loc[0] >> 1);
								6'b110111:	right_step	<=	(boun_loc[2] >> 1) + (boun_loc[1] >> 1); 												
								default: ;
							endcase
						end
			default: ;
		endcase
	end

endmodule