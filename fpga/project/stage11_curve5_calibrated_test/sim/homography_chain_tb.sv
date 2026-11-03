`timescale 1ns / 1ps

module homography_chain_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg [287:0] coefficients;
    reg s_valid = 0;
    wire s_ready;
    reg [10:0] s_u = 0;
    reg [9:0] s_v = 0;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 32'h12345678;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;

    wire h_valid, h_ready, h_geometry_valid;
    wire signed [31:0] h_sx, h_sy;
    wire [19:0] h_pixel_id;
    wire [31:0] h_frame_id;
    wire [15:0] h_param_version;
    wire h_sof, h_eol, h_eof;
    wire m_valid;
    reg m_ready = 1;
    wire signed [31:0] m_sx, m_sy;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    localparam [287:0] IDENTITY = {
        32'h40000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00010000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00010000
    };
    localparam [287:0] SCALE_075 = {
        32'h30000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h0000c000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h0000c000
    };
    localparam [287:0] SCALE_125 = {
        32'h50000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00014000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00014000
    };
    reg signed [31:0] expected_x [0:7];
    reg signed [31:0] expected_y [0:7];
    reg expected_geometry [0:7];
    reg [15:0] expected_version [0:7];
    integer received = 0;
    integer cycles = 0;
    reg stalled = 0;
    reg [135:0] held_output;
    wire [135:0] output_bundle = {
        m_sx, m_sy, m_geometry_valid, m_pixel_id, m_frame_id,
        m_param_version, m_sof, m_eol, m_eof
    };

    homography_mapper homography (
        .clk(clk), .rstn(rstn), .coefficients(coefficients),
        .s_valid(s_valid), .s_ready(s_ready), .s_u(s_u), .s_v(s_v),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(h_valid), .m_ready(h_ready),
        .m_sx(h_sx), .m_sy(h_sy), .m_geometry_valid(h_geometry_valid),
        .m_pixel_id(h_pixel_id), .m_frame_id(h_frame_id),
        .m_param_version(h_param_version),
        .m_sof(h_sof), .m_eol(h_eol), .m_eof(h_eof)
    );
    fractional_brown_mapper brown (
        .clk(clk), .rstn(rstn),
        .s_valid(h_valid), .s_ready(h_ready),
        .s_sx(h_sx), .s_sy(h_sy), .s_geometry_valid(h_geometry_valid),
        .s_pixel_id(h_pixel_id), .s_frame_id(h_frame_id),
        .s_param_version(h_param_version),
        .s_sof(h_sof), .s_eol(h_eol), .s_eof(h_eof),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_sx(m_sx), .m_sy(m_sy), .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send_pixel(
        input [287:0] words, input [10:0] u, input [9:0] v,
        input [19:0] id, input [15:0] version
    );
        begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            coefficients = words;
            s_u = u; s_v = v; s_pixel_id = id;
            s_param_version = version;
            s_sof = id == 0; s_eol = id == 1; s_eof = id == 7;
            s_valid = 1;
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    always @(posedge clk) if (rstn) begin
        cycles = cycles + 1;
        m_ready <= (cycles % 19 < 7) || (cycles % 19 > 12);
        if (stalled && (!m_valid || output_bundle !== held_output))
            $fatal(1, "Output changed while stalled");
        stalled = m_valid && !m_ready;
        held_output = output_bundle;
        if (m_valid && m_ready) begin
            if (received >= 8 || m_pixel_id !== received ||
                m_frame_id !== 32'h12345678 ||
                m_param_version !== expected_version[received] ||
                m_geometry_valid !== expected_geometry[received] ||
                m_sof !== (received == 0) ||
                m_eol !== (received == 1) ||
                m_eof !== (received == 7))
                $fatal(1, "Metadata/valid mismatch at output %0d", received);
            if (expected_geometry[received] &&
                (m_sx !== expected_x[received] ||
                 m_sy !== expected_y[received]))
                $fatal(1, "Coordinate mismatch at output %0d: %0d,%0d expected %0d,%0d",
                    received, m_sx, m_sy,
                    expected_x[received], expected_y[received]);
            received = received + 1;
        end
    end

    initial begin
        coefficients = IDENTITY;
        expected_x[0] = 41940489;
        expected_y[0] = 23592106;
        expected_x[1] = 42006025;
        expected_y[1] = 23592106;
        expected_x[2] = 41973257;
        expected_y[2] = 23592106;
        expected_x[3] = expected_x[1];
        expected_y[3] = expected_y[1];
        expected_x[4] = 0; expected_y[4] = 0;
        expected_x[5] = 0; expected_y[5] = 0;
        expected_x[6] = 41940418; expected_y[6] = 23592066;
        expected_x[7] = 41940463; expected_y[7] = 23592092;
        expected_geometry[0] = 1; expected_geometry[1] = 1;
        expected_geometry[2] = 1; expected_geometry[3] = 1;
        expected_geometry[4] = 0; expected_geometry[5] = 0;
        expected_geometry[6] = 1; expected_geometry[7] = 1;
        expected_version[0] = 0; expected_version[1] = 0;
        expected_version[2] = 7; expected_version[3] = 8;
        expected_version[4] = 9; expected_version[5] = 10;
        expected_version[6] = 11; expected_version[7] = 12;

        repeat (3) @(negedge clk);
        rstn = 1;
        send_pixel(IDENTITY, 640, 360, 0, 0);
        send_pixel(IDENTITY, 641, 360, 1, 0);
        send_pixel(IDENTITY | (288'h8000 << 64), 640, 360, 2, 7);
        send_pixel(IDENTITY | (288'h10000 << 64), 640, 360, 3, 8);
        send_pixel((IDENTITY & ~(288'hffffffff << 256)) |
            (288'h10000000 << 256), 640, 360, 4, 9);
        send_pixel(IDENTITY | (288'h7fffffff << 64), 640, 360, 5, 10);
        send_pixel(SCALE_075, 640, 360, 6, 11);
        send_pixel(SCALE_125, 640, 360, 7, 12);
        repeat (80) @(negedge clk);
        if (received != 8) $fatal(1, "Only received %0d of 8 pixels", received);
        $display("PASS: Stage 8 homography/Brown chain and backpressure");
        $finish;
    end
endmodule
