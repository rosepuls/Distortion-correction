`timescale 1ns / 1ps

module pipelined_bilinear_interpolator_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0, s_valid = 0, m_ready = 0;
    reg [31:0] p00, p10, p01, p11;
    reg [15:0] fx, fy, version;
    reg [3:0] mask;
    reg geo, sof, eol, eof;
    reg [19:0] id;
    reg [31:0] frame;
    wire old_s_ready, new_s_ready, old_valid, new_valid;
    wire [31:0] old_pixel, new_pixel, old_frame, new_frame;
    wire [19:0] old_id, new_id;
    wire [15:0] old_version, new_version;
    wire old_geo, new_geo, old_sof, new_sof, old_eol, new_eol,
         old_eof, new_eof;

    bilinear_interpolator reference (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(old_s_ready),
        .s_p00(p00), .s_p10(p10), .s_p01(p01), .s_p11(p11),
        .s_fx(fx), .s_fy(fy), .s_neighbor_valid(mask),
        .s_geometry_valid(geo), .s_pixel_id(id), .s_frame_id(frame),
        .s_param_version(version), .s_sof(sof), .s_eol(eol), .s_eof(eof),
        .m_valid(old_valid), .m_ready(m_ready), .m_pixel(old_pixel),
        .m_geometry_valid(old_geo), .m_pixel_id(old_id),
        .m_frame_id(old_frame), .m_param_version(old_version),
        .m_sof(old_sof), .m_eol(old_eol), .m_eof(old_eof)
    );
    pipelined_bilinear_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(new_s_ready),
        .s_p00(p00), .s_p10(p10), .s_p01(p01), .s_p11(p11),
        .s_fx(fx), .s_fy(fy), .s_neighbor_valid(mask),
        .s_geometry_valid(geo), .s_pixel_id(id), .s_frame_id(frame),
        .s_param_version(version), .s_sof(sof), .s_eol(eol), .s_eof(eof),
        .m_valid(new_valid), .m_ready(m_ready), .m_pixel(new_pixel),
        .m_geometry_valid(new_geo), .m_pixel_id(new_id),
        .m_frame_id(new_frame), .m_param_version(new_version),
        .m_sof(new_sof), .m_eol(new_eol), .m_eof(new_eof)
    );

    integer i, wait_cycles;
    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            if (!old_s_ready || !new_s_ready) $fatal(1, "input not ready %0d", i);
            p00 = $urandom; p10 = $urandom;
            p01 = $urandom; p11 = $urandom;
            fx = $urandom; fy = $urandom; mask = $urandom;
            if (i == 0) begin fx = 0; fy = 0; mask = 4'hf; end
            if (i == 1) begin fx = 16'hffff; fy = 16'hffff; mask = 4'h5; end
            if (i == 2) mask = 0;
            geo = i[0]; id = i; frame = 32'h98760000 + i;
            version = i; sof = i == 0; eol = i == 99; eof = i == 99;
            s_valid = 1;
            @(negedge clk);
            s_valid = 0;
            wait_cycles = 0;
            while ((!old_valid || !new_valid) && wait_cycles < 10) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!old_valid || !new_valid) $fatal(1, "result timeout %0d", i);
            if ({new_pixel,new_geo,new_id,new_frame,new_version,
                 new_sof,new_eol,new_eof} !==
                {old_pixel,old_geo,old_id,old_frame,old_version,
                 old_sof,old_eol,old_eof})
                $fatal(1, "pipeline mismatch %0d old=%h new=%h", i,
                       old_pixel, new_pixel);
            repeat (3) @(negedge clk);
            if (!old_valid || !new_valid || old_pixel !== new_pixel)
                $fatal(1, "stalled result changed %0d", i);
            m_ready = 1;
            @(negedge clk);
            m_ready = 0;
        end
        $display("PASS: pipelined bilinear interpolation matched 100 reference transactions under output stalls");
        $finish;
    end
endmodule
