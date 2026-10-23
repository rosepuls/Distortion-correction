`timescale 1ns / 1ps

// Export the exact fixed-point Stage 6 mapping and planner coordinates for
// one full 720p frame. The cache replay consumes the planner's clamped x0/y0.
module stage7_cache_trace_tb;
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer PIXELS = WIDTH * HEIGHT;

    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [10:0] s_u = 11'd0;
    reg [9:0] s_v = 10'd0;
    reg [19:0] s_pixel_id = 20'd0;
    wire map_valid, map_ready;
    wire signed [31:0] map_sx, map_sy;
    wire map_geometry_valid;
    wire [19:0] map_pixel_id;
    wire plan_valid;
    wire [10:0] plan_x0, plan_x1;
    wire [9:0] plan_y0, plan_y1;
    wire [19:0] plan_pixel_id;
    wire [3:0] plan_neighbor_valid;
    integer issued = 0;
    integer observed = 0;
    integer cycles = 0;
    integer trace_file;

    demo_radial_mapper #(.RADIAL_DENOM_SHIFT(21)) mapper (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'd0), .s_param_version(16'd0),
        .s_sof(s_pixel_id == 0), .s_eol(s_u == WIDTH-1),
        .s_eof(s_pixel_id == PIXELS-1),
        .m_valid(map_valid), .m_ready(map_ready),
        .m_sx(map_sx), .m_sy(map_sy),
        .m_geometry_valid(map_geometry_valid),
        .m_j00(), .m_j01(), .m_j10(), .m_j11(), .m_j_valid(),
        .m_pixel_id(map_pixel_id), .m_frame_id(), .m_param_version(),
        .m_sof(), .m_eol(), .m_eof()
    );

    bilinear_sample_planner #(.IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT)) planner (
        .clk(clk), .rstn(rstn),
        .s_valid(map_valid), .s_ready(map_ready),
        .s_sx(map_sx), .s_sy(map_sy),
        .s_geometry_valid(map_geometry_valid), .s_border_replicate(1'b0),
        .s_pixel_id(map_pixel_id), .s_frame_id(32'd0),
        .s_param_version(16'd0), .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(plan_valid), .m_ready(1'b1),
        .m_x0(plan_x0), .m_x1(plan_x1),
        .m_y0(plan_y0), .m_y1(plan_y1),
        .m_fx(), .m_fy(), .m_neighbor_valid(plan_neighbor_valid),
        .m_geometry_valid(), .m_pixel_id(plan_pixel_id),
        .m_frame_id(), .m_param_version(), .m_sof(), .m_eol(), .m_eof()
    );

    initial begin
        trace_file = $fopen("stage7_tile_trace.csv", "w");
        if (trace_file == 0) $fatal(1, "Could not create coordinate trace");
        repeat (4) @(negedge clk);
        rstn = 1'b1;
    end

    always @(negedge clk) begin
        if (rstn && issued < PIXELS) begin
            s_valid = 1'b1;
            s_u = issued % WIDTH;
            s_v = issued / WIDTH;
            s_pixel_id = issued;
        end else begin
            s_valid = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (cycles > PIXELS + 100) $fatal(1, "Coordinate trace timeout");
            if (s_valid && s_ready) issued = issued + 1;
            if (plan_valid) begin
                if (plan_pixel_id !== observed[19:0])
                    $fatal(1, "Coordinate order mismatch at %0d", observed);
                $fwrite(trace_file, "%0d,%0d,%0d,%0d\n",
                        plan_pixel_id, plan_x0, plan_y0, plan_neighbor_valid);
                observed = observed + 1;
                if (observed == PIXELS) begin
                    $fclose(trace_file);
                    $display("PASS: exported %0d fixed-point Stage 7 cache coordinates", observed);
                    $finish;
                end
            end
        end
    end
endmodule
