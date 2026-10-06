`timescale 1ns/1ps

// Physical MES50HP / PGL50H top.
// Continuous pipeline: capture frame N while correcting frame N-1 and
// displaying the most recently completed output frame.  Input and output use
// independent ping-pong regions so no reader sees a frame being overwritten.
module pgl50h_board_top #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 12,
    parameter integer MEM_ROW_ADDR_WIDTH = 15,
    parameter integer MEM_COL_ADDR_WIDTH = 10,
    parameter integer MEM_BADDR_WIDTH = 3,
    parameter integer MEM_DQ_WIDTH = 32,
    parameter integer RESET_DELAY_CYCLES = 10000,
    parameter integer SIMULATION = 0,
    parameter signed [31:0] CFG_FX_Q19 = 32'sd314572800,
    parameter signed [31:0] CFG_FY_Q19 = 32'sd314572800,
    parameter signed [31:0] CFG_CX_Q19 = 32'sd335282176,
    parameter signed [31:0] CFG_CY_Q19 = 32'sd188481536,
    parameter signed [31:0] CFG_INV_FX_Q30 = 32'sd1789569,
    parameter signed [31:0] CFG_INV_FY_Q30 = 32'sd1789569,
    parameter signed [31:0] CFG_K1_Q28 = 32'sd0,
    parameter signed [31:0] CFG_K2_Q28 = 32'sd0,
    parameter signed [31:0] CFG_P1_Q28 = 32'sd0,
    parameter signed [31:0] CFG_P2_Q28 = 32'sd0
) (
    input  wire                         sys_clk,
    output wire                         rstn_out,
    output wire                         iic_scl,
    inout  wire                         iic_sda,
    output wire                         iic_tx_scl,
    inout  wire                         iic_tx_sda,

    input  wire                         pixclk_in,
    input  wire                         vs_in,
    input  wire                         hs_in,
    input  wire                         de_in,
    input  wire [7:0]                   r_in,
    input  wire [7:0]                   g_in,
    input  wire [7:0]                   b_in,

    output wire                         pixclk_out,
    output reg                          vs_out,
    output reg                          hs_out,
    output reg                          de_out,
    output reg  [7:0]                   r_out,
    output reg  [7:0]                   g_out,
    output reg  [7:0]                   b_out,

    output wire                         mem_rst_n,
    output wire                         mem_ck,
    output wire                         mem_ck_n,
    output wire                         mem_cke,
    output wire                         mem_cs_n,
    output wire                         mem_ras_n,
    output wire                         mem_cas_n,
    output wire                         mem_we_n,
    output wire                         mem_odt,
    output wire [MEM_ROW_ADDR_WIDTH-1:0] mem_a,
    output wire [MEM_BADDR_WIDTH-1:0]    mem_ba,
    inout  wire [MEM_DQ_WIDTH/8-1:0]     mem_dqs,
    inout  wire [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n,
    inout  wire [MEM_DQ_WIDTH-1:0]       mem_dq,
    output wire [MEM_DQ_WIDTH/8-1:0]     mem_dm,

    output wire                         hdmi_int_led,
    output wire                         ddr_init_done,
    output reg                          heart_beat_led
);
    localparam integer CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;
    localparam [CTRL_ADDR_WIDTH-1:0] INPUT_FRAME_BASE0 = {CTRL_ADDR_WIDTH{1'b0}};
    localparam [CTRL_ADDR_WIDTH-1:0] INPUT_FRAME_BASE1 =
        ({{(CTRL_ADDR_WIDTH-1){1'b0}},1'b1} << 22);
    localparam [CTRL_ADDR_WIDTH-1:0] OUTPUT_FRAME_BASE0 =
        ({{(CTRL_ADDR_WIDTH-1){1'b0}},1'b1} << 23);
    localparam integer OUTPUT_FRAME_WORDS = (IMAGE_WIDTH * 24 / 32) * IMAGE_HEIGHT;
    localparam [CTRL_ADDR_WIDTH-1:0] OUTPUT_FRAME_BASE1 =
        OUTPUT_FRAME_BASE0 + OUTPUT_FRAME_WORDS;

    wire video_pixel_clk;
    wire cfg_clk;
    wire unused_clk_25m;
    wire video_pll_lock;
    wire hdmi_init_done;
    wire core_clk;
    wire ddr_pll_lock;

    pll video_pll (
        .clkin1(sys_clk),
        .clkout0(video_pixel_clk),
        .clkout1(cfg_clk),
        .clkout2(unused_clk_25m),
        .pll_lock(video_pll_lock)
    );

    reg [15:0] reset_delay_count;
    always @(posedge cfg_clk) begin
        if (!video_pll_lock)
            reset_delay_count <= 16'd0;
        else if (reset_delay_count < RESET_DELAY_CYCLES)
            reset_delay_count <= reset_delay_count + 1'b1;
    end
    assign rstn_out = video_pll_lock && (reset_delay_count >= RESET_DELAY_CYCLES);

    // rstn_out is generated in cfg_clk.  It may assert asynchronously, but
    // every unrelated clock domain must release reset only on a local edge.
    // Keep the DDR3 IP on its vendor reference reset path; these three
    // synchronized resets are for user logic in the HDMI input, 100 MHz core,
    // and HDMI output pixel domains respectively.
    wire input_rst_n;
    wire core_rst_n;
    wire video_rst_n;
    // Keep cfg_clk-generated rstn_out off every asynchronous RS pin in the
    // DDR reset release path.  The synchronous-only two-flop shift register
    // samples release in sys_clk and therefore presents resetn to the IP only
    // after two local edges.
    wire ddr_reset_n;
    wire core_reset_request_n = rstn_out && ddr_init_done;
    mes50hp_reset_sync input_reset_sync (
        .clk(pixclk_in), .reset_n(rstn_out), .rst_n(input_rst_n)
    );
    mes50hp_reset_sync_sync_only ddr_reset_sync (
        .clk(sys_clk), .reset_n(rstn_out), .rst_n(ddr_reset_n)
    );
    mes50hp_reset_sync core_reset_sync (
        .clk(core_clk), .reset_n(core_reset_request_n), .rst_n(core_rst_n)
    );
    mes50hp_reset_sync_sync_only video_reset_sync (
        .clk(video_pixel_clk), .reset_n(rstn_out), .rst_n(video_rst_n)
    );

    ms72xx_ctl hdmi_init (
        .clk(cfg_clk),
        .rst_n(rstn_out),
        .init_over(hdmi_init_done),
        .iic_tx_scl(iic_tx_scl),
        .iic_tx_sda(iic_tx_sda),
        .iic_scl(iic_scl),
        .iic_sda(iic_sda)
    );
    assign hdmi_int_led = hdmi_init_done;
    assign pixclk_out = video_pixel_clk;

    wire pipeline_ready = ddr_init_done && hdmi_init_done;
    wire capture_enable = pipeline_ready;
    wire process_enable;
    wire display_enable;
    wire algo_frame_start;
    wire algo_frame_done;
    wire output_frame_complete;
    wire input_frame_complete;

    wire process_input_bank;
    wire process_output_bank;
    wire output_ready_toggle;
    wire output_ready_bank;
    wire input_overrun;
    wire display_bank_core;
    wire process_active;

    realtime_frame_scheduler realtime_scheduler (
        .clk(core_clk),
        .rst_n(core_rst_n),
        .input_frame_done(input_frame_complete),
        .input_frame_bank(~input_frame_count[0]),
        .algo_frame_done(algo_frame_done),
        .output_frame_done(output_frame_complete),
        .display_bank_core(display_bank_core),
        .process_start(algo_frame_start),
        .process_input_bank(process_input_bank),
        .process_output_bank(process_output_bank),
        .process_active(process_active),
        .output_ready_toggle(output_ready_toggle),
        .output_ready_bank(output_ready_bank),
        .input_overrun(input_overrun)
    );
    assign process_enable = process_active;

    reg display_started;
    reg output_ready_seen;
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            display_started <= 1'b0;
            output_ready_seen <= 1'b0;
        end else if (output_ready_seen != output_ready_toggle) begin
            display_started <= 1'b1;
            output_ready_seen <= output_ready_toggle;
        end
    end
    assign display_enable = pipeline_ready && display_started;

    // The first VS arms the stream; every following VS completes one input
    // frame.  A toggle safely carries each completion into the DDR domain.
    reg capture_pix_1;
    reg capture_pix_2;
    reg vs_in_d;
    reg capture_frame_seen;
    reg capture_complete_toggle;
    always @(posedge pixclk_in or negedge input_rst_n) begin
        if (!input_rst_n) begin
            capture_pix_1 <= 1'b0;
            capture_pix_2 <= 1'b0;
            vs_in_d <= 1'b0;
            capture_frame_seen <= 1'b0;
            capture_complete_toggle <= 1'b0;
        end else begin
            capture_pix_1 <= capture_enable;
            capture_pix_2 <= capture_pix_1;
            vs_in_d <= vs_in;
            if (!capture_pix_2) begin
                capture_frame_seen <= 1'b0;
            end else if (vs_in && !vs_in_d) begin
                if (capture_frame_seen)
                    capture_complete_toggle <= ~capture_complete_toggle;
                else
                    capture_frame_seen <= 1'b1;
            end
        end
    end

    reg capture_toggle_core_1;
    reg capture_toggle_core_2;
    reg capture_toggle_core_3;
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            capture_toggle_core_1 <= 1'b0;
            capture_toggle_core_2 <= 1'b0;
            capture_toggle_core_3 <= 1'b0;
        end else begin
            capture_toggle_core_1 <= capture_complete_toggle;
            capture_toggle_core_2 <= capture_toggle_core_1;
            capture_toggle_core_3 <= capture_toggle_core_2;
        end
    end
    assign input_frame_complete = capture_toggle_core_2 ^ capture_toggle_core_3;

    wire input_wr_req;
    wire [CTRL_ADDR_WIDTH-1:0] input_wr_addr;
    wire [31:0] input_wr_len;
    wire [255:0] input_wr_data;
    wire [5:0] input_frame_count;
    wire unused_input_frame_irq;
    wire shared_wr_ready;
    wire shared_wr_done;
    wire shared_wr_bac;
    wire shared_wr_data_re;
    wire input_wr_done;
    wire input_wr_bac;
    wire input_wr_data_re;
    wire algo_wr_done;
    wire algo_wr_bac;
    wire algo_wr_data_re;
    wire algo_wr_cmd_ready;

    wr_buf #(
        .ADDR_WIDTH(CTRL_ADDR_WIDTH),
        .ADDR_OFFSET(0),
        .H_NUM(IMAGE_WIDTH),
        .V_NUM(IMAGE_HEIGHT),
        .DQ_WIDTH(MEM_DQ_WIDTH),
        .LEN_WIDTH(32),
        .PIX_WIDTH(32),
        .LINE_ADDR_WIDTH(22),
        .FRAME_CNT_WIDTH(6)
    ) input_frame_writer (
        .ddr_clk(core_clk),
        .ddr_rstn(core_rst_n),
        .wr_clk(pixclk_in),
        .wr_fsync(vs_in),
        .wr_en(de_in && capture_pix_2),
        .wr_data({r_in,g_in,b_in,8'h00}),
        .rd_bac(capture_enable ? input_wr_bac : 1'b0),
        .ddr_wreq(input_wr_req),
        .ddr_waddr(input_wr_addr),
        .ddr_wr_len(input_wr_len),
        .ddr_wrdy(capture_enable ? 1'b1 : 1'b0),
        .ddr_wdone(capture_enable ? input_wr_done : 1'b0),
        .ddr_wdata(input_wr_data),
        .ddr_wdata_req(capture_enable ? input_wr_data_re : 1'b0),
        .frame_wcnt(input_frame_count),
        .frame_wirq(unused_input_frame_irq)
    );

    wire [CTRL_ADDR_WIDTH-1:0] input_frame_base = process_input_bank ?
        INPUT_FRAME_BASE1 : INPUT_FRAME_BASE0;

    // The legacy RGB888 one-pixel interface remains on mes50hp_top for
    // compatibility, but the 720P30 board path selects only the RGBX cache
    // ports below.
    wire algo_mem_req_valid;
    wire [31:0] algo_mem_req_addr;
    wire algo_mem_rsp_ready;
    wire cache_rd_cmd_en;
    wire cache_rd_cmd_ready;
    wire [31:0] cache_rd_cmd_addr;
    wire [31:0] cache_rd_cmd_len;
    wire cache_rd_data_valid;
    wire cache_rd_data_ready;
    wire [255:0] cache_rd_data;
    wire cache_rd_data_last;
    wire [23:0] algo_out_pixel;
    wire algo_out_valid;
    wire algo_out_sof;
    wire algo_out_eol;
    wire unused_algo_busy;

    mes50hp_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(COORD_WIDTH),
        .ADDR_WIDTH(32),
        .USE_TILE_CACHE(1),
        // 16 sets x 4 ways = 32 KiB RGBX Tile Cache for the 720p30 path.
        // The four 128-bit banks retain the existing DDR burst protocol.
        .TILE_CACHE_SET_COUNT(16),
        .TILE_CACHE_WAYS(4),
        .USE_PSEUDO_LRU(1),
        .FRAME_BASE_BYTE_ADDR(32'd0)
    ) algorithm_system (
        .clk(core_clk),
        .reset_n(core_rst_n),
        .frame_start(algo_frame_start),
        .frame_busy(unused_algo_busy),
        .frame_done(algo_frame_done),
        .cfg_fx_q19(CFG_FX_Q19), .cfg_fy_q19(CFG_FY_Q19),
        .cfg_cx_q19(CFG_CX_Q19), .cfg_cy_q19(CFG_CY_Q19),
        .cfg_inv_fx_q30(CFG_INV_FX_Q30), .cfg_inv_fy_q30(CFG_INV_FY_Q30),
        .cfg_k1_q28(CFG_K1_Q28), .cfg_k2_q28(CFG_K2_Q28),
        .cfg_p1_q28(CFG_P1_Q28), .cfg_p2_q28(CFG_P2_Q28),
        .mem_req_valid(algo_mem_req_valid),
        .mem_req_ready(1'b0),
        .mem_req_addr(algo_mem_req_addr),
        .mem_rsp_valid(1'b0),
        .mem_rsp_ready(algo_mem_rsp_ready),
        .mem_rsp_data(24'd0),
        .cache_rd_cmd_en(cache_rd_cmd_en),
        .cache_rd_cmd_ready(cache_rd_cmd_ready),
        .cache_rd_cmd_addr(cache_rd_cmd_addr),
        .cache_rd_cmd_len(cache_rd_cmd_len),
        .cache_rd_data_valid(cache_rd_data_valid),
        .cache_rd_data_ready(cache_rd_data_ready),
        .cache_rd_data(cache_rd_data),
        .cache_rd_data_last(cache_rd_data_last),
        .out_pixel(algo_out_pixel),
        .out_valid(algo_out_valid),
        .out_sof(algo_out_sof),
        .out_eol(algo_out_eol)
    );

    wire shared_rd_ready;
    wire shared_rd_done;
    wire [255:0] shared_rd_data;
    wire shared_rd_data_valid;
    wire cache_ctrl_cmd_en;
    wire [CTRL_ADDR_WIDTH-1:0] cache_ctrl_cmd_addr;
    wire [31:0] cache_ctrl_cmd_len;
    wire cache_ctrl_data_ready;
    wire cache_ctrl_cmd_ready;
    wire cache_ctrl_data_valid;

    ddr3_rgbx_cache_adapter #(
        .CACHE_ADDR_WIDTH(32), .CTRL_ADDR_WIDTH(CTRL_ADDR_WIDTH)
    ) cache_ddr_adapter (
        .clk(core_clk), .rst_n(core_rst_n),
        .frame_base_word_addr(input_frame_base),
        .cache_cmd_en(cache_rd_cmd_en), .cache_cmd_ready(cache_rd_cmd_ready),
        .cache_cmd_byte_addr(cache_rd_cmd_addr), .cache_cmd_len(cache_rd_cmd_len),
        .ctrl_cmd_en(cache_ctrl_cmd_en),
        .ctrl_cmd_ready(process_enable ? cache_ctrl_cmd_ready : 1'b0),
        .ctrl_cmd_word_addr(cache_ctrl_cmd_addr), .ctrl_cmd_len(cache_ctrl_cmd_len),
        .ctrl_data_valid(process_enable && cache_ctrl_data_valid),
        .ctrl_data_ready(cache_ctrl_data_ready), .ctrl_data(shared_rd_data),
        .cache_data_valid(cache_rd_data_valid), .cache_data_ready(cache_rd_data_ready),
        .cache_data(cache_rd_data), .cache_data_last(cache_rd_data_last)
    );

    wire algo_wr_cmd_en;
    wire [CTRL_ADDR_WIDTH-1:0] algo_wr_cmd_addr;
    wire [31:0] algo_wr_cmd_len;
    wire [255:0] algo_wr_data;
    wire output_writer_overflow;

    // Input/cache traffic uses RGBX8888.  The output side deliberately keeps
    // the verified RGB888 line-buffer implementation until its RGBX reader is
    // replaced by a vendor dual-clock DRM implementation.
    algorithm_frame_writer #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DDR_ADDR_WIDTH(CTRL_ADDR_WIDTH), .OUTPUT_BASE_ADDR(OUTPUT_FRAME_BASE0),
        .SIMULATION(SIMULATION)
    ) corrected_frame_writer (
        .clk(core_clk), .rst_n(core_rst_n),
        .pixel_valid(algo_out_valid), .pixel_data(algo_out_pixel),
        .pixel_sof(algo_out_sof), .pixel_eol(algo_out_eol),
        .frame_base_addr(process_output_bank ? OUTPUT_FRAME_BASE1 : OUTPUT_FRAME_BASE0),
        .overflow(output_writer_overflow),
        .frame_complete(output_frame_complete),
        .wr_cmd_en(algo_wr_cmd_en), .wr_cmd_addr(algo_wr_cmd_addr),
        .wr_cmd_len(algo_wr_cmd_len),
        .wr_cmd_ready(process_enable ? algo_wr_cmd_ready : 1'b0),
        .wr_cmd_done(process_enable ? algo_wr_done : 1'b0),
        .wr_bac(process_enable ? algo_wr_bac : 1'b0),
        .wr_ctrl_data(algo_wr_data),
        .wr_data_re(process_enable ? algo_wr_data_re : 1'b0)
    );

    wire timing_vs;
    wire timing_hs;
    wire timing_de;
    wire timing_de_request;
    wire timing_frame_start;
    wire display_pixel_valid;
    wire [23:0] display_pixel;
    wire display_underflow;
    reg display_pix_1;
    reg display_pix_2;
    always @(posedge video_pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            display_pix_1 <= 1'b0;
            display_pix_2 <= 1'b0;
        end else begin
            display_pix_1 <= display_enable;
            display_pix_2 <= display_pix_1;
        end
    end

    video_mode_720p30 output_timing (
        .clk(video_pixel_clk), .rst_n(display_pix_2),
        .vs(timing_vs), .hs(timing_hs), .de(timing_de),
        .de_request(timing_de_request),
        .x(), .y(), .frame_start(timing_frame_start)
    );

    // A completed output frame crosses by toggle; its bank becomes visible to
    // HDMI only on the next timing frame boundary, never in active video.
    reg output_ready_pix_1;
    reg output_ready_pix_2;
    reg output_ready_pix_3;
    reg output_ready_bank_pix_1;
    reg output_ready_bank_pix_2;
    reg display_bank_pix;
    always @(posedge video_pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            output_ready_pix_1 <= 1'b0;
            output_ready_pix_2 <= 1'b0;
            output_ready_pix_3 <= 1'b0;
            output_ready_bank_pix_1 <= 1'b0;
            output_ready_bank_pix_2 <= 1'b0;
            display_bank_pix <= 1'b0;
        end else begin
            output_ready_pix_1 <= output_ready_toggle;
            output_ready_pix_2 <= output_ready_pix_1;
            output_ready_bank_pix_1 <= output_ready_bank;
            output_ready_bank_pix_2 <= output_ready_bank_pix_1;
            if (timing_frame_start && (output_ready_pix_2 != output_ready_pix_3)) begin
                display_bank_pix <= output_ready_bank_pix_2;
                output_ready_pix_3 <= output_ready_pix_2;
            end
        end
    end

    reg display_bank_core_1;
    reg display_bank_core_2;
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            display_bank_core_1 <= 1'b0;
            display_bank_core_2 <= 1'b0;
        end else begin
            display_bank_core_1 <= display_bank_pix;
            display_bank_core_2 <= display_bank_core_1;
        end
    end
    assign display_bank_core = display_bank_core_2;

    wire frame_rd_cmd_en;
    wire [CTRL_ADDR_WIDTH-1:0] frame_rd_cmd_addr;
    wire [31:0] frame_rd_cmd_len;
    wire frame_rd_data_ready;
    wire frame_rd_cmd_ready;
    wire frame_rd_cmd_done;
    wire frame_rd_data_valid;

    ddr3_frame_reader #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DDR_ADDR_WIDTH(CTRL_ADDR_WIDTH), .FRAME_BASE_ADDR(OUTPUT_FRAME_BASE0),
        .SIMULATION(SIMULATION)
    ) corrected_frame_reader (
        .ddr_clk(core_clk), .ddr_rst_n(core_rst_n),
        .pixel_clk(video_pixel_clk), .pixel_rst_n(video_rst_n),
        .display_enable(display_enable), .rd_fsync(timing_vs),
        .rd_en(timing_de_request),
        .frame_base_addr(display_bank_core ? OUTPUT_FRAME_BASE1 : OUTPUT_FRAME_BASE0),
        .vout_de(display_pixel_valid),
        .vout_data(display_pixel), .underflow(display_underflow),
        .rd_cmd_en(frame_rd_cmd_en), .rd_cmd_addr(frame_rd_cmd_addr),
        .rd_cmd_len(frame_rd_cmd_len),
        .rd_cmd_ready(display_enable ? frame_rd_cmd_ready : 1'b0),
        .rd_cmd_done(display_enable ? frame_rd_cmd_done : 1'b0),
        .rd_data(shared_rd_data),
        .rd_data_valid(display_enable && frame_rd_data_valid),
        .rd_data_ready(frame_rd_data_ready)
    );

    always @(posedge video_pixel_clk) begin
        if (!display_pix_2) begin
            vs_out <= 1'b0; hs_out <= 1'b0; de_out <= 1'b0;
            r_out <= 8'd0; g_out <= 8'd0; b_out <= 8'd0;
        end else begin
            vs_out <= timing_vs;
            hs_out <= timing_hs;
            de_out <= display_pixel_valid;
            r_out <= display_pixel[23:16];
            g_out <= display_pixel[15:8];
            b_out <= display_pixel[7:0];
        end
    end

    wire shared_wr_cmd_en;
    wire [CTRL_ADDR_WIDTH-1:0] shared_wr_cmd_addr;
    wire [31:0] shared_wr_cmd_len;
    wire [255:0] shared_wr_ctrl_data;

    // Capture and corrected-output writes may overlap.  The arbiter latches
    // the granted source until the controller completes that burst.
    ddr_two_client_arbiter #(.ADDR_WIDTH(CTRL_ADDR_WIDTH)) write_arbiter (
        .clk(core_clk), .rst_n(core_rst_n),
        .c0_cmd_valid(capture_enable && input_wr_req),
        .c0_cmd_addr(input_wr_addr), .c0_cmd_len(input_wr_len), .c0_data(input_wr_data),
        .c0_cmd_ready(), .c0_done(input_wr_done),
        .c0_bac(input_wr_bac), .c0_data_re(input_wr_data_re),
        .c1_cmd_valid(process_enable && algo_wr_cmd_en),
        .c1_cmd_addr(algo_wr_cmd_addr), .c1_cmd_len(algo_wr_cmd_len), .c1_data(algo_wr_data),
        .c1_cmd_ready(algo_wr_cmd_ready), .c1_done(algo_wr_done),
        .c1_bac(algo_wr_bac), .c1_data_re(algo_wr_data_re),
        .ctrl_cmd_valid(shared_wr_cmd_en), .ctrl_cmd_addr(shared_wr_cmd_addr),
        .ctrl_cmd_len(shared_wr_cmd_len), .ctrl_cmd_ready(shared_wr_ready),
        .ctrl_done(shared_wr_done), .ctrl_bac(shared_wr_bac),
        .ctrl_data_re(shared_wr_data_re), .ctrl_data(shared_wr_ctrl_data)
    );

    wire shared_rd_cmd_en;
    wire [CTRL_ADDR_WIDTH-1:0] shared_rd_cmd_addr;
    wire [31:0] shared_rd_cmd_len;
    wire shared_read_ready;

    // Cache reads and display prefetches likewise retain ownership from
    // command acceptance through the final returned beat.  Display wins an
    // idle-cycle tie to protect HDMI from starvation.
    ddr_two_client_read_arbiter #(.ADDR_WIDTH(CTRL_ADDR_WIDTH)) read_arbiter (
        .clk(core_clk), .rst_n(core_rst_n),
        .c0_cmd_valid(process_enable && cache_ctrl_cmd_en),
        .c0_cmd_addr(cache_ctrl_cmd_addr), .c0_cmd_len(cache_ctrl_cmd_len),
        .c0_cmd_ready(cache_ctrl_cmd_ready), .c0_data_ready(cache_ctrl_data_ready),
        .c0_data_valid(cache_ctrl_data_valid), .c0_data(shared_rd_data),
        .c0_done(),
        .c1_cmd_valid(display_enable && frame_rd_cmd_en),
        .c1_cmd_addr(frame_rd_cmd_addr), .c1_cmd_len(frame_rd_cmd_len),
        .c1_cmd_ready(frame_rd_cmd_ready), .c1_data_ready(frame_rd_data_ready),
        .c1_data_valid(frame_rd_data_valid), .c1_data(), .c1_done(frame_rd_cmd_done),
        .ctrl_cmd_valid(shared_rd_cmd_en), .ctrl_cmd_addr(shared_rd_cmd_addr),
        .ctrl_cmd_len(shared_rd_cmd_len), .ctrl_cmd_ready(shared_rd_ready),
        .ctrl_data_ready(shared_read_ready), .ctrl_data_valid(shared_rd_data_valid),
        .ctrl_data(shared_rd_data), .ctrl_done(shared_rd_done)
    );

    wire [CTRL_ADDR_WIDTH-1:0] axi_awaddr;
    wire [3:0] axi_awid;
    wire [3:0] axi_awlen;
    wire [2:0] axi_awsize;
    wire [1:0] axi_awburst;
    wire axi_awready;
    wire axi_awvalid;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    wire axi_wlast;
    wire axi_wvalid;
    wire axi_wready;
    wire axi_bready;
    wire [CTRL_ADDR_WIDTH-1:0] axi_araddr;
    wire [3:0] axi_arid;
    wire [3:0] axi_arlen;
    wire [2:0] axi_arsize;
    wire [1:0] axi_arburst;
    wire axi_arvalid;
    wire axi_arready;
    wire axi_rready;
    wire [255:0] axi_rdata;
    wire axi_rvalid;
    wire axi_rlast;
    wire [3:0] axi_rid;

    wr_rd_ctrl_top #(
        .CTRL_ADDR_WIDTH(CTRL_ADDR_WIDTH), .MEM_DQ_WIDTH(MEM_DQ_WIDTH)
    ) memory_command_controller (
        .clk(core_clk), .rstn(core_rst_n),
        .wr_cmd_en(shared_wr_cmd_en), .wr_cmd_addr(shared_wr_cmd_addr),
        .wr_cmd_len(shared_wr_cmd_len), .wr_cmd_ready(shared_wr_ready),
        .wr_cmd_done(shared_wr_done), .wr_bac(shared_wr_bac),
        .wr_ctrl_data(shared_wr_ctrl_data), .wr_data_re(shared_wr_data_re),
        .rd_cmd_en(shared_rd_cmd_en), .rd_cmd_addr(shared_rd_cmd_addr),
        .rd_cmd_len(shared_rd_cmd_len), .rd_cmd_ready(shared_rd_ready),
        .rd_cmd_done(shared_rd_done), .read_ready(shared_read_ready),
        .read_rdata(shared_rd_data), .read_en(shared_rd_data_valid),
        .axi_awaddr(axi_awaddr), .axi_awid(axi_awid), .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize), .axi_awburst(axi_awburst),
        .axi_awready(axi_awready), .axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
        .axi_bid(4'd0), .axi_bresp(2'd0), .axi_bvalid(1'b0), .axi_bready(axi_bready),
        .axi_araddr(axi_araddr), .axi_arid(axi_arid), .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize), .axi_arburst(axi_arburst),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rready(axi_rready), .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid),
        .axi_rlast(axi_rlast), .axi_rid(axi_rid), .axi_rresp(2'd0)
    );

    DDR3_50H ddr3_controller (
        .ref_clk(sys_clk), .resetn(ddr_reset_n), .ddr_init_done(ddr_init_done),
        .ddrphy_clkin(core_clk), .pll_lock(ddr_pll_lock),
        .axi_awaddr(axi_awaddr), .axi_awuser_ap(1'b0), .axi_awuser_id(axi_awid),
        .axi_awlen(axi_awlen), .axi_awready(axi_awready), .axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wready(axi_wready),
        .axi_wusero_id(), .axi_wusero_last(axi_wlast),
        .axi_araddr(axi_araddr), .axi_aruser_ap(1'b0), .axi_aruser_id(axi_arid),
        .axi_arlen(axi_arlen), .axi_arready(axi_arready), .axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata), .axi_rid(axi_rid), .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .apb_clk(1'b0), .apb_rst_n(1'b1), .apb_sel(1'b0), .apb_enable(1'b0),
        .apb_addr(8'd0), .apb_write(1'b0), .apb_ready(),
        .apb_wdata(16'd0), .apb_rdata(), .apb_int(),
        .debug_data(), .debug_slice_state(), .debug_calib_ctrl(),
        .ck_dly_set_bin(), .force_ck_dly_en(1'b0), .force_ck_dly_set_bin(8'h05),
        .dll_step(), .dll_lock(), .init_read_clk_ctrl(2'b0), .init_slip_step(4'b0),
        .force_read_clk_ctrl(1'b0), .ddrphy_gate_update_en(1'b0),
        .update_com_val_err_flag(), .rd_fake_stop(1'b0),
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n),
        .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm)
    );

    reg [26:0] heartbeat_count;
    always @(posedge core_clk) begin
        if (!core_rst_n) begin
            heartbeat_count <= 27'd0;
            heart_beat_led <= 1'b0;
        end else if (heartbeat_count == 27'd33000000) begin
            heartbeat_count <= 27'd0;
            heart_beat_led <= ~heart_beat_led;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    wire unused_inputs = hs_in ^ timing_de ^ output_writer_overflow ^
                         display_underflow ^ ddr_pll_lock ^ axi_wvalid ^
                         axi_bready ^ axi_rready ^ axi_awsize[0] ^
                         axi_awburst[0] ^ axi_arsize[0] ^ axi_arburst[0];
endmodule
