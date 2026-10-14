`timescale 1ns/1ps

// Streaming cached source-pixel fetch path.  Cache lookup and response are
// decoupled by a small metadata FIFO so synchronous Tile Bank latency does not
// misalign fractional coordinates or frame markers.
module cached_pixel_fetch_engine #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer ADDR_WIDTH = 32,
    parameter integer COORD_WIDTH = 12,
    parameter integer TILE_CACHE_SET_COUNT = 16,
    parameter integer TILE_CACHE_WAYS = 8,
    parameter integer BANK_READ_LATENCY = 1,
    parameter integer USE_PSEUDO_LRU = 0,
    parameter [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = {ADDR_WIDTH{1'b0}}
) (
    input  wire                         clk,
    input  wire                         rst_n,
    // The cache owns the large storage/reset cone.  Give it an independent
    // reset leaf so fetch-control reset traffic does not span Cache RAM.
    input  wire                         storage_rst_n,
    input  wire                         frame_start,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [COORD_WIDTH-1:0]       in_x0,
    input  wire [COORD_WIDTH-1:0]       in_y0,
    input  wire [15:0]                  in_fx,
    input  wire [15:0]                  in_fy,
    input  wire                         in_coord_valid,
    input  wire                         in_sof,
    input  wire                         in_eol,
    output wire [23:0]                  out_pixel,
    output wire                         out_valid,
    output wire                         out_sof,
    output wire                         out_eol,
    input  wire                         rd_cmd_ready,
    output wire                         rd_cmd_en,
    output wire [ADDR_WIDTH-1:0]        rd_cmd_addr,
    output wire [31:0]                  rd_cmd_len,
    input  wire                         rd_data_valid,
    output wire                         rd_data_ready,
    input  wire [255:0]                 rd_data,
    input  wire                         rd_data_last
);
    localparam integer META_DEPTH = 8;
    localparam integer META_PTR_WIDTH = 3;

    reg [15:0] meta_fx [0:META_DEPTH-1];
    reg [15:0] meta_fy [0:META_DEPTH-1];
    reg meta_coord_valid [0:META_DEPTH-1];
    reg meta_sof [0:META_DEPTH-1];
    reg meta_eol [0:META_DEPTH-1];
    reg [META_PTR_WIDTH-1:0] meta_wr_ptr;
    reg [META_PTR_WIDTH-1:0] meta_rd_ptr;
    integer meta_count;
    integer meta_i;

    wire cache_lookup_valid;
    wire cache_lookup_ready;
    wire cache_rsp_valid;
    wire cache_rsp_ready;
    wire [31:0] cache_p00;
    wire [31:0] cache_p10;
    wire [31:0] cache_p01;
    wire [31:0] cache_p11;
    wire cache_hit;
    wire cache_coord_valid;

    wire cache_fill_req_valid;
    wire cache_fill_req_ready;
    wire [11:0] cache_fill_tile_x;
    wire [11:0] cache_fill_tile_y;
    wire [1:0] cache_fill_row_index;
    wire reader_fill_data_valid;
    wire reader_fill_data_ready;
    wire [255:0] reader_fill_data;
    wire [11:0] reader_fill_tile_x;
    wire [11:0] reader_fill_tile_y;
    wire [1:0] reader_fill_row_index;
    wire [1:0] reader_fill_beat_index;

    assign in_ready = rst_n && (meta_count < META_DEPTH) && cache_lookup_ready;
    wire input_fire = in_valid && in_ready;
    assign cache_lookup_valid = input_fire;
    wire [COORD_WIDTH-1:0] cache_lookup_x = in_coord_valid
                                              ? in_x0
                                              : IMAGE_WIDTH - 1;
    wire [COORD_WIDTH-1:0] cache_lookup_y = in_coord_valid
                                              ? in_y0
                                              : IMAGE_HEIGHT - 1;
    // The interpolation block is a fixed-latency streaming consumer and has
    // no backpressure port.  Keep the cache response enabled whenever a
    // metadata item is present at the head of the FIFO.
    assign cache_rsp_ready = (meta_count != 0);
    wire cache_response_fire = cache_rsp_valid && cache_rsp_ready;

    // cache_response_fire is the only validity qualifier for the
    // interpolation payload.  A response fire requires a metadata entry, so
    // its head is valid on every observable interpolation cycle.  Leave the
    // payload ungated in idle cycles: zero-filling it with meta_count/fire
    // would put the metadata-empty comparator on the wide pixel-data path.
    wire [15:0] interp_fx = meta_fx[meta_rd_ptr];
    wire [15:0] interp_fy = meta_fy[meta_rd_ptr];
    wire [23:0] interp_p00 = cache_p00[31:8];
    wire [23:0] interp_p10 = cache_p10[31:8];
    wire [23:0] interp_p01 = cache_p01[31:8];
    wire [23:0] interp_p11 = cache_p11[31:8];
    wire bilinear_out_sof;
    wire bilinear_out_eol;
    assign out_sof = bilinear_out_sof;
    assign out_eol = bilinear_out_eol;

    pixel_tile_cache #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(12),
        .PIXEL_WIDTH(32),
        .SET_COUNT(TILE_CACHE_SET_COUNT),
        .WAYS(TILE_CACHE_WAYS),
        .BANK_READ_LATENCY(BANK_READ_LATENCY),
        .USE_PSEUDO_LRU(USE_PSEUDO_LRU)
    ) tile_cache_inst (
        .clk(clk), .rst_n(storage_rst_n), .invalidate(frame_start),
        .lookup_valid(cache_lookup_valid), .lookup_ready(cache_lookup_ready),
        .lookup_x0(cache_lookup_x[11:0]), .lookup_y0(cache_lookup_y[11:0]),
        .lookup_rsp_valid(cache_rsp_valid), .lookup_rsp_ready(cache_rsp_ready),
        .pixel_p00(cache_p00), .pixel_p10(cache_p10),
        .pixel_p01(cache_p01), .pixel_p11(cache_p11),
        .cache_hit(cache_hit), .coord_valid(cache_coord_valid),
        .fill_req_valid(cache_fill_req_valid), .fill_req_ready(cache_fill_req_ready),
        .fill_tile_x(cache_fill_tile_x), .fill_tile_y(cache_fill_tile_y),
        .fill_row_index(cache_fill_row_index),
        .fill_data_valid(reader_fill_data_valid), .fill_data_ready(reader_fill_data_ready),
        .fill_data(reader_fill_data), .fill_data_row_index(reader_fill_row_index),
        .fill_data_beat_index(reader_fill_beat_index)
    );

    ddr_burst_reader #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH), .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) burst_reader_inst (
        .clk(clk), .rst_n(rst_n),
        .fill_req_valid(cache_fill_req_valid), .fill_req_ready(cache_fill_req_ready),
        .fill_tile_x(cache_fill_tile_x), .fill_tile_y(cache_fill_tile_y),
        .fill_row_index(cache_fill_row_index),
        .rd_cmd_en(rd_cmd_en), .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr), .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last),
        .fill_data_valid(reader_fill_data_valid), .fill_data_ready(reader_fill_data_ready),
        .fill_data(reader_fill_data), .fill_out_tile_x(reader_fill_tile_x),
        .fill_out_tile_y(reader_fill_tile_y), .fill_out_row_index(reader_fill_row_index),
        .fill_beat_index(reader_fill_beat_index)
    );

    bilinear_interp bilinear_interp_inst (
        .clk(clk), .rst_n(rst_n),
        .p00(interp_p00), .p10(interp_p10), .p01(interp_p01), .p11(interp_p11),
        .dx(interp_fx), .dy(interp_fy),
        .coord_valid(cache_response_fire && cache_coord_valid
                     && meta_coord_valid[meta_rd_ptr]),
        .in_valid(cache_response_fire),
        .in_sof(meta_sof[meta_rd_ptr]),
        .in_eol(meta_eol[meta_rd_ptr]),
        .out_pixel(out_pixel), .out_valid(out_valid),
        .out_sof(bilinear_out_sof), .out_eol(bilinear_out_eol)
    );

    // The metadata FIFO is ordered exactly like cache lookup requests.  It
    // therefore also covers invalid edge coordinates, which are returned by
    // the cache as black responses instead of taking a side path.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_wr_ptr <= 0;
            meta_rd_ptr <= 0;
            meta_count <= 0;
            // meta_count=0 makes every metadata payload entry unreachable.
            // Leave payload RAM untouched to keep this reset leaf small.
        end else begin
            if (input_fire) begin
                meta_fx[meta_wr_ptr] <= in_fx;
                meta_fy[meta_wr_ptr] <= in_fy;
                meta_coord_valid[meta_wr_ptr] <= in_coord_valid;
                meta_sof[meta_wr_ptr] <= in_sof;
                meta_eol[meta_wr_ptr] <= in_eol;
                meta_wr_ptr <= meta_wr_ptr + 1'b1;
            end
            if (cache_response_fire)
                meta_rd_ptr <= meta_rd_ptr + 1'b1;
            case ({input_fire, cache_response_fire})
                2'b10: meta_count <= meta_count + 1;
                2'b01: meta_count <= meta_count - 1;
                default: meta_count <= meta_count;
            endcase
        end
    end
endmodule
