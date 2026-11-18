
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2019 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
//               
// Library:
// Filename:ipmxe_adc_sim_tb.v                 
//////////////////////////////////////////////////////////////////////////////
`timescale 1 ns/1 ps

module ipmxe_adc_sim_tb ();


localparam real   PCLK  =  50.0;

localparam real TCLK = 1000/PCLK;

reg        rst_n;
reg        pclk;
wire       over_temp;
wire       user_temp_alarm;
wire       vcc_alarm;
wire       vcca_alarm;
wire       vcc_cram_alarm;
wire       vcc_drm_alarm;
wire       vcc_pu_alarm;
wire       vcca_pu_alarm;
wire       vccio_ddr_alarm;
wire       logic_done_a;
wire       logic_done_b;
wire       adc_clk_out;
wire       adc_dmodified;
reg [7:0]  paddr;
reg        psel;
reg        penable;
wire       pwrite;
wire       pready;
wire[15:0] pwdata;
wire[15:0] prdata;
reg        adc_a_flag;
reg        adc_b_flag;


always @(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
    begin
        adc_a_flag <= 1'b0;
    end
    else
    begin
        if(logic_done_a) begin
            adc_a_flag <= 1'b1;
        end
        else begin
            adc_a_flag <= adc_a_flag;
        end
    end
end

always @(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
    begin
        adc_b_flag <= 1'b0;
    end
    else
    begin
        if(logic_done_b) begin
            adc_b_flag <= 1'b1;
        end
        else begin
            adc_b_flag <= adc_b_flag;
        end
    end
end


initial
begin
    pclk = 1'b0;
    forever #(TCLK/2)
    pclk = ~pclk;
end

integer handle;
initial
begin
    rst_n = 1'b0;
    paddr = 8'h00;
    penable = 1'b0;
    psel = 1'b0;
    #(5*TCLK)
    rst_n = 1'b1;


    wait(adc_a_flag);

    #(TCLK*20)
    apb_read(8'h40);
    compare(12'ha8c,12'ha29);
    
    #(TCLK*20) 
    apb_read(8'h41);
    compare(12'h590,12'h511);
    
    #(TCLK*20);
    apb_read(8'h42);
    compare(12'h9ea,12'h948);
    
    #(TCLK*20);
    apb_read(8'h43);
    compare(12'h590,12'h511);
    
    #(TCLK*20);
    apb_read(8'h44);
    compare(12'h732,12'h6ab);
    

    #(TCLK*200000);
    $display("ADC simulation test pass! : %t \n",$time);
    $finish;
end

//APB read compare

task apb_read;
    input [7:0]  paddrin;
    begin
        psel = 1'b1;
        paddr = paddrin;
        #TCLK;
        penable = 1'b1;
        #TCLK;
        psel = 1'b0;
        penable = 1'b0;
        #TCLK;
    end
endtask

task compare;
    input  [11:0]  data_top;
    input  [11:0]  data_below;

    begin
    @(negedge pready);
    begin
        handle = $fopen("vsim_ipmxe_adc_sim_tb.log","a");
        if((prdata[15:4] >= data_below ) && (prdata[15:4] <= data_top))
        begin
            $fdisplay(handle,"Monitoring data is written correctly in the specified status reggister 8'h%h!", paddr);
        end
        else begin
            $fdisplay(handle,"Monitoring data is converted error : %t \n",$time);
            $fdisplay(handle,"Error register addr is 8'h%h ",paddr);
            $finish;
        end
        $fclose(handle);
    end
   
    end
endtask
adc_test  u_adc(

    .i_rst_n           (rst_n     ),
    .i_apb_clk         (pclk      ),
    .i_apb_paddr       (paddr     ),
    .i_apb_psel        (psel      ),
    .i_apb_enable      (penable   ),
    .i_apb_pwrite      (1'b0      ),
    .i_apb_pwdata      (pwdata    ),
    .o_apb_prdata      (prdata    ),
    .o_apb_pready      (pready    ),

    .i_adc_loadsc_n    (1'b1 ),

    .o_logic_done_a    (logic_done_a  ),
    .o_logic_done_b    (logic_done_b  ),
    .o_adc_clk_out     (adc_clk_out   ),
    .o_adc_dmodified   (adc_dmodified )
);

endmodule
