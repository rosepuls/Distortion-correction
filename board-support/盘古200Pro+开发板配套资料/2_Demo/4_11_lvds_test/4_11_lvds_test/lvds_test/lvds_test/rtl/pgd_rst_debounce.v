//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_rst_debounce #
    (
    parameter DLY1_RST_WIDTH = 10, //(2**9) = 512
    parameter DLY2_RST_WIDTH = 10 //(2**9)*512 = 256k
    )
    (
     input   wire               sys_clk,
     input   wire               sys_rst_n,
     output  reg                srst_len_n
    );

reg     [DLY1_RST_WIDTH-1:0]  cnt_1;
reg     [DLY2_RST_WIDTH-1:0]  cnt_2;

always@(posedge sys_clk or negedge sys_rst_n)
begin
    if (!sys_rst_n)
    begin
        cnt_1 <= {DLY1_RST_WIDTH{1'b0}};
    end
    else if(cnt_1[DLY1_RST_WIDTH-1])
    begin
        cnt_1 <= {DLY1_RST_WIDTH{1'b0}};
    end
    else
    begin
        cnt_1 <= cnt_1 + { {(DLY1_RST_WIDTH-1){1'b0}}, 1'b1};
    end
end

always@(posedge sys_clk or negedge sys_rst_n)
begin
    if (!sys_rst_n)
    begin
        cnt_2 <= {DLY2_RST_WIDTH{1'b0}};
    end
    else if(cnt_2[DLY2_RST_WIDTH-1])
    begin
        cnt_2 <= cnt_2;
    end
    else if(cnt_1[DLY1_RST_WIDTH-1])
    begin
        cnt_2 <= cnt_2 + { {(DLY2_RST_WIDTH-1){1'b0}}, 1'b1};
    end
end

always@(posedge sys_clk or negedge sys_rst_n)
begin
    if (!sys_rst_n)
    begin
        srst_len_n <= 1'b0;
    end
    `ifdef PGS_PCIEX4_SPEEDUP_SIM
    else if(cnt_1[2])
    `else
    else if(cnt_2[DLY2_RST_WIDTH-1])
    `endif
    begin
        srst_len_n <= 1'b1;
    end
end

endmodule//pgs_rst_debounce
