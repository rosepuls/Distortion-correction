`timescale    1ns/1ns
module tb_key_led_test();

reg            clk          ;
reg            rst_n        ;
wire    [7:0]  led          ;
reg            key          ;

reg     [7:0]  data         ;

initial
begin
    rst_n    <=    0;
    clk      <=    0;
    key      <=    0;
    #20
    rst_n    <=    1;
    key      <=    1;    
    #2000
    key      <=    0;
    #2000
    $display("I am stop");
    $stop;
end

always#10 clk = ~clk;//20ns  50MHZ

key_led_test#(
    .CNT_MAX (10 )
)u_key_led_test(
    .clk   ( clk   ),
    .rstn  ( rst_n ),
    .key   ( key   ),
    .led   ( led   )
);

initial
begin
    $monitor("led:%b",led);
end


always@(posedge clk or negedge rst_n)    begin
    if(!rst_n)
        data    <=    8'd0;
    else
    begin
        data    <=    {$random}%256;
        $display("Now data is %d",data);
    end
end

endmodule
