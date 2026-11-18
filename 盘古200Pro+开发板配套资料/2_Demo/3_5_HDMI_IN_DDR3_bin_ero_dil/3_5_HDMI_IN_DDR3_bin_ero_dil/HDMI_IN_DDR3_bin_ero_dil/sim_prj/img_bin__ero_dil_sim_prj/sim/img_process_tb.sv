//图像处理仿真模块
//后续的图像处理都基于该平台
//默认使用全局二值化
`timescale 1ns/1ns
module	img_process_tb();

//图片高度宽度 
//仿真需要改小视频大小 避免太大

//时序参考模板  仿真中不需要严格按照vesa时序标准
parameter IMG_WIDTH = 16'd1280;//有效区域           
parameter H_FP = 16'd110;    //前沿            
parameter H_SYNC = 16'd40;   //同步            
parameter H_BP = 16'd220 ;   //后沿
parameter TOTAL_WIDTH = IMG_WIDTH  + H_FP  +H_SYNC + H_BP; 
  
parameter IMG_HEIGHT = 16'd720; //有效区域           
parameter V_FP  = 16'd5;      //前沿               
parameter V_SYNC  = 16'd5;    //同步               
parameter V_BP  = 16'd20;     //后沿           
parameter TOTAL_HEIGHT = IMG_HEIGHT + V_FP + + V_SYNC + V_BP;            

localparam	HREF_DELAY	=	5;
localparam	VSYNC_DELAY	=	5;

reg	video_clk	;
reg	rst_n		;


wire			video_vs;
wire			video_de;
wire	[23:0]	video_data;
//定义处理后的文件
integer	output_file;
initial
begin
	video_clk	=	1'd0;
	rst_n		=	1'd0;
	#20
	rst_n		=	1'd1;
	output_file	=	$fopen("D:/2L676demo/img_bin__ero_dil_sim_prj/img_bin__ero_dil_sim_prj/sim/img_process.txt","w");
end
//生成 100MHZ
always#5 video_clk = ~video_clk;

//读取图片数据

video_data_gen#(
    .DATA_WIDTH   ( 24          ),
    .TOTAL_WIDTH  ( TOTAL_WIDTH ),
    .IMG_WIDTH    ( IMG_WIDTH   ),
    .H_SYNC       ( H_SYNC      ),
    .H_BP         ( H_BP        ),
    .H_FP         ( H_FP        ),
    .TOTAL_HEIGHT ( TOTAL_HEIGHT),
    .IMG_HEIGHT   ( IMG_HEIGHT  ),
    .V_SYNC       ( V_SYNC      ),
    .V_BP         ( V_BP        ),
    .V_FP         ( V_FP        )
)u_video_data_gen (
    .video_clk    ( video_clk    ),
    .rst_n        ( rst_n        ),
    .video_vs     ( video_vs     ),
    .video_de     ( video_de     ),
    .video_data   ( video_data   )
);
wire    gray_vs;
wire    gray_de;
wire    [7:0]    gray_data;

RGB2YCbCr u_RGB2YCbCr(
    .clk       ( video_clk ),
    .rst_n     ( rst_n     ),
    .vsync_in  ( video_vs  ),
    .hsync_in  ( video_de  ),
    .de_in     ( video_de     ),
    .red       ( video_data[23:16]       ),
    .green     ( video_data[15:8]     ),
    .blue      ( video_data[7:0]      ),
    .vsync_out ( gray_vs ),
    .hsync_out (  ),
    .de_out    ( gray_de    ),
    .y         ( gray_data         ),
    .cb        (         ),
    .cr        (         )
);


//全局二值化
wire    bin_vs;
wire    bin_hs;
wire    bin_de;
wire    bin_data;
binarization u_binarization(
    .clk        ( video_clk  ),
    .rst_n      ( rst_n      ),
    .vsync_in   ( gray_vs    ),
    .hsync_in   ( gray_de    ),
    .de_in      ( gray_de    ),
    .y_in       ( gray_data  ),
    .vsync_out  ( bin_vs     ),
    .hsync_out  ( bin_hs     ),
    .de_out     ( bin_de     ),
    .pix        ( bin_data   )
);
wire    matrix_de;
wire    matrix_vs;
wire    matrix11;
wire    matrix12;
wire    matrix13;
wire    matrix21;
wire    matrix22;
wire    matrix23;
wire    matrix31;
wire    matrix32;
wire    matrix33;
matrix_3x3_1bit#(
    .IMG_WIDTH   ( IMG_WIDTH ),
    .IMG_HEIGHT  ( IMG_HEIGHT )
)u_matrix_3x3_1bit(
    .video_clk   ( video_clk   ),
    .rst_n       ( rst_n       ),

    .video_vs    ( bin_vs    ),
    .video_de    ( bin_de    ),
    .video_data  ( bin_data  ),

    .matrix_de   ( matrix_de   ),
    .matrix_vs   ( matrix_vs   ),
    .matrix11    ( matrix11    ),
    .matrix12    ( matrix12    ),
    .matrix13    ( matrix13    ),
    .matrix21    ( matrix21    ),
    .matrix22    ( matrix22    ),
    .matrix23    ( matrix23    ),
    .matrix31    ( matrix31    ),
    .matrix32    ( matrix32    ),
    .matrix33    ( matrix33    )
);

//腐蚀
wire    erosion_vs;
wire    erosion_de;
wire    erosion_data;
erosion u_erosion(
    .video_clk    ( video_clk    ),
    .rst_n        ( rst_n        ),
    .bin_vs       ( matrix_vs       ),
    .bin_de       ( matrix_de       ),
    .bin_data_11  ( matrix11  ),
    .bin_data_12  ( matrix12  ),
    .bin_data_13  ( matrix13  ),
    .bin_data_21  ( matrix21  ),
    .bin_data_22  ( matrix22  ),
    .bin_data_23  ( matrix23  ),
    .bin_data_31  ( matrix31  ),
    .bin_data_32  ( matrix32  ),
    .bin_data_33  ( matrix33  ),
    .erosion_vs   ( erosion_vs   ),
    .erosion_de   ( erosion_de   ),
    .erosion_data  ( erosion_data  )
);

wire    ero_matrix_de;
wire    ero_matrix_vs;
wire    ero_matrix11;
wire    ero_matrix12;
wire    ero_matrix13;
wire    ero_matrix21;
wire    ero_matrix22;
wire    ero_matrix23;
wire    ero_matrix31;
wire    ero_matrix32;
wire    ero_matrix33;
matrix_3x3_1bit#(
    .IMG_WIDTH   ( IMG_WIDTH ),
    .IMG_HEIGHT  ( IMG_HEIGHT )
)u_matrix_3x3_1bit_erosion(
    .video_clk   ( video_clk   ),
    .rst_n       ( rst_n       ),

    .video_vs    ( erosion_vs    ),
    .video_de    ( erosion_de    ),
    .video_data  ( erosion_data  ),

    .matrix_de   ( ero_matrix_de   ),
    .matrix_vs   ( ero_matrix_vs   ),
    .matrix11    ( ero_matrix11    ),
    .matrix12    ( ero_matrix12    ),
    .matrix13    ( ero_matrix13    ),
    .matrix21    ( ero_matrix21    ),
    .matrix22    ( ero_matrix22    ),
    .matrix23    ( ero_matrix23    ),
    .matrix31    ( ero_matrix31    ),
    .matrix32    ( ero_matrix32    ),
    .matrix33    ( ero_matrix33    )
);
//膨胀
wire        dilate_vs;
wire        dilate_de;
wire        dilate_data;

dilate u_dilate(
    .video_clk    ( video_clk    ),
    .rst_n        ( rst_n        ),
    .bin_vs       ( ero_matrix_vs       ),
    .bin_de       ( ero_matrix_de       ),
    .bin_data_11  ( ero_matrix11 ),
    .bin_data_12  ( ero_matrix12 ),
    .bin_data_13  ( ero_matrix13 ),
    .bin_data_21  ( ero_matrix21 ),
    .bin_data_22  ( ero_matrix22 ),
    .bin_data_23  ( ero_matrix23 ),
    .bin_data_31  ( ero_matrix31 ),
    .bin_data_32  ( ero_matrix32 ),
    .bin_data_33  ( ero_matrix33 ),
    .dilate_vs    ( dilate_vs    ),
    .dilate_de    ( dilate_de    ),
    .dilate_data  ( dilate_data  )
);


GTP_GRS GRS_INST(
    .GRS_N(1'b1)
    ) ;



//写数据
reg	video_vs_d	;	//打拍寄存
reg	img_done	;	
wire    frame_flag;


always@(posedge video_clk or negedge rst_n)	begin
	if(!rst_n)
		video_vs_d	<=	1'd0;
	else
		video_vs_d	<=	dilate_vs;
end

assign frame_flag = ~dilate_vs & video_vs_d;    //下降沿

reg    [7:0]    img_done_cnt    ;

//备用 用来第二帧再写入
always@(posedge video_clk or negedge rst_n)	begin
	if(!rst_n)
        img_done_cnt    <=    8'd0;
	else if(frame_flag)    //下降沿 判断一帧结束
		img_done_cnt <= img_done_cnt + 1'b1;
	else
		img_done_cnt <= img_done_cnt;
end


always@(posedge video_clk or negedge rst_n)	begin
	if(!rst_n)
		img_done <= 1'b0;
	else if(frame_flag)    //下降沿 判断一帧结束
		img_done <= 1'b1;
	else
		img_done <= img_done;
end


always@(posedge video_clk or negedge rst_n)	begin
	if(img_done)
	begin
        $display("finish to write img in txt!");
		$stop;    //停止仿真
	end  	
	else if(dilate_de)    //写入数据
	begin
		$fdisplay(output_file,"%h\t%h\t%h",{8{dilate_data}},{8{dilate_data}},{8{dilate_data}});    //16进制写入  
	end
end

endmodule