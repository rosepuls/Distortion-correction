`timescale 1ns / 1ps

module interpolation_720p_tb;
    localparam integer IMAGE_WIDTH = 1280;
    localparam integer IMAGE_HEIGHT = 720;
    localparam integer TOTAL = IMAGE_WIDTH * IMAGE_HEIGHT;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [15:0] s_fx = 0, s_fy = 0;
    reg [19:0] s_pixel_id = 0;
    wire m_valid;
    wire [31:0] m_pixel;
    wire [19:0] m_pixel_id;
    integer out_file, sent, received;
    integer x, y, qx, qy, bx, by, row_i, col_i;
    reg [23:0] source_rgb [0:TOTAL-1];

`ifdef BICUBIC
    reg [511:0] s_samples = 0;
    wire [15:0] m_param_version;
    wire [31:0] m_frame_id;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    pipelined_catmull_rom_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_samples(s_samples), .s_fx(s_fx), .s_fy(s_fy),
        .s_neighbor_valid(16'hffff), .s_geometry_valid(1'b1),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'h72000001),
        .s_param_version(16'h0001), .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(1'b1), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
`else
    reg [31:0] s_p00 = 0, s_p10 = 0, s_p01 = 0, s_p11 = 0;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_geometry_valid, m_sof, m_eol, m_eof;
    pipelined_bilinear_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_p00(s_p00), .s_p10(s_p10), .s_p01(s_p01), .s_p11(s_p11),
        .s_fx(s_fx), .s_fy(s_fy), .s_neighbor_valid(4'hf),
        .s_geometry_valid(1'b1), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'h72000001), .s_param_version(16'h0001),
        .s_sof(1'b0), .s_eol(1'b0), .s_eof(1'b0),
        .m_valid(m_valid), .m_ready(1'b1), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
`endif

    function automatic integer clamp_x(input integer value);
        begin
            if (value < 0) clamp_x = 0;
            else if (value >= IMAGE_WIDTH) clamp_x = IMAGE_WIDTH - 1;
            else clamp_x = value;
        end
    endfunction

    function automatic integer clamp_y(input integer value);
        begin
            if (value < 0) clamp_y = 0;
            else if (value >= IMAGE_HEIGHT) clamp_y = IMAGE_HEIGHT - 1;
            else clamp_y = value;
        end
    endfunction

    function automatic [31:0] sample_at(input integer px, input integer py);
        reg [23:0] rgb;
        integer sx, sy;
        begin
            sx = clamp_x(px);
            sy = clamp_y(py);
            rgb = source_rgb[sy * IMAGE_WIDTH + sx];
            sample_at = {rgb, 8'h00};
        end
    endfunction

    always @(posedge clk) begin
        if (rstn && m_valid) begin
            if (m_pixel_id !== received[19:0])
                $fatal(1, "Output order mismatch: got %0d expected %0d", m_pixel_id, received);
            // Compact exact RTL RGB capture: one six-hex-digit RGB word per output pixel.
            $fdisplay(out_file, "%02x%02x%02x", m_pixel[31:24], m_pixel[23:16], m_pixel[15:8]);
            received = received + 1;
            if (received == TOTAL) begin
                $fclose(out_file);
`ifdef BICUBIC
                $display("PASS: 720p Catmull-Rom RTL emitted %0d ordered pixels", received);
`else
                $display("PASS: 720p bilinear RTL emitted %0d ordered pixels", received);
`endif
                $finish;
            end
        end
    end

    initial begin
        $readmemh("source_rgb.mem", source_rgb);
        out_file = $fopen("pixels_rgb.hex", "w");
        if (out_file == 0) $fatal(1, "Could not open pixels_rgb.hex");
        sent = 0;
        received = 0;
        repeat (5) @(negedge clk);
        rstn = 1'b1;

        // A common half-pixel translation guarantees fractional coordinates.
        // It isolates interpolation behavior from frame buffering and geometry.
        for (sent = 0; sent < TOTAL; sent = sent + 1) begin
            x = sent % IMAGE_WIDTH;
            y = sent / IMAGE_WIDTH;
            qx = (x << 16) + 32768;
            qy = (y << 16) + 32768;
            bx = qx >> 16;
            by = qy >> 16;
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_pixel_id = sent[19:0];
            s_fx = qx[15:0];
            s_fy = qy[15:0];
`ifdef BICUBIC
            for (row_i = 0; row_i < 4; row_i = row_i + 1)
                for (col_i = 0; col_i < 4; col_i = col_i + 1)
                    s_samples[(row_i*4+col_i)*32 +: 32] =
                        sample_at(bx + col_i - 1, by + row_i - 1);
`else
            s_p00 = sample_at(bx,     by);
            s_p10 = sample_at(bx + 1, by);
            s_p01 = sample_at(bx,     by + 1);
            s_p11 = sample_at(bx + 1, by + 1);
`endif
            s_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            s_valid = 1'b0;
        end
    end

    initial begin
        #30000000;
        $fatal(1, "720p interpolation simulation timed out");
    end
endmodule
