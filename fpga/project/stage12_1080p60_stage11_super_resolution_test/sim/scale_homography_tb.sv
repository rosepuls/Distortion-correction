`timescale 1ns / 1ps
module scale_homography_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [11:0] s_u = 0, s_v = 0;
    reg [20:0] s_pixel_id = 0;
    wire scale_valid, scale_ready;
    wire signed [31:0] scale_sx, scale_sy;
    wire scale_geo;
    wire [20:0] scale_id;
    wire [31:0] scale_frame;
    wire [15:0] scale_version;
    wire scale_sof, scale_eol, scale_eof;
    wire h_valid, h_ready, h_geo;
    wire signed [31:0] h_sx, h_sy;
    wire [19:0] h_id;
    wire [31:0] h_frame;
    wire [15:0] h_version;
    wire h_sof, h_eol, h_eof;
    localparam [287:0] IDENTITY = {
        32'h40000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00010000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00010000
    };
    integer received = 0;
    reg [11:0] test_u [0:3];
    reg [11:0] test_v [0:3];
    reg signed [31:0] expected_x [0:3];
    reg signed [31:0] expected_y [0:3];

    scale_3_2_mapper scale_map (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(32'h12345678), .s_param_version(16'h55aa),
        .s_sof(s_pixel_id == 0), .s_eol(s_pixel_id == 1), .s_eof(s_pixel_id == 3),
        .m_valid(scale_valid), .m_ready(scale_ready),
        .m_sx(scale_sx), .m_sy(scale_sy), .m_geometry_valid(scale_geo),
        .m_pixel_id(scale_id), .m_frame_id(scale_frame),
        .m_param_version(scale_version), .m_sof(scale_sof),
        .m_eol(scale_eol), .m_eof(scale_eof)
    );
    homography_mapper #(.INPUT_Q16(1)) homography (
        .clk(clk), .rstn(rstn), .coefficients(IDENTITY),
        .s_valid(scale_valid), .s_ready(scale_ready), .s_u(11'd0), .s_v(10'd0),
        .s_u_q16(scale_sx), .s_v_q16(scale_sy),
        .s_pixel_id(scale_id[19:0]), .s_frame_id(scale_frame),
        .s_param_version(scale_version), .s_sof(scale_sof),
        .s_eol(scale_eol), .s_eof(scale_eof),
        .m_valid(h_valid), .m_ready(1'b1), .m_sx(h_sx), .m_sy(h_sy),
        .m_geometry_valid(h_geo), .m_pixel_id(h_id), .m_frame_id(h_frame),
        .m_param_version(h_version), .m_sof(h_sof), .m_eol(h_eol), .m_eof(h_eof)
    );

    function automatic signed [31:0] map_q16(input [11:0] coord);
        reg [27:0] quotient_product;
        reg [10:0] quotient;
        reg [1:0] phase;
        reg signed [31:0] base_q16;
        begin
            quotient_product = coord * 16'd43691;
            quotient = quotient_product[27:17];
            phase = coord - (quotient * 3);
            base_q16 = $signed({4'd0, quotient, 1'b0, 16'd0});
            case (phase)
                2'd0: map_q16 = base_q16 - 32'sd10923;
                2'd1: map_q16 = base_q16 + 32'sd32768;
                default: map_q16 = base_q16 + 32'sd76459;
            endcase
        end
    endfunction

    always @(posedge clk) if (rstn && h_valid) begin
        if (received >= 4 || h_id !== received[19:0] || !h_geo ||
            h_sx !== expected_x[received] || h_sy !== expected_y[received] ||
            h_frame !== 32'h12345678 || h_version !== 16'h55aa ||
            h_sof !== (received == 0) || h_eol !== (received == 1) || h_eof !== (received == 3))
            $fatal(1, "3:2 + homography mismatch id=%0d geo=%b xy=%0d,%0d expected=%0d,%0d",
                h_id, h_geo, h_sx, h_sy, expected_x[received], expected_y[received]);
        received = received + 1;
    end

    initial begin
        test_u[0]=0; test_v[0]=0;
        test_u[1]=1; test_v[1]=1;
        test_u[2]=2; test_v[2]=2;
        test_u[3]=1919; test_v[3]=1079;
        for (integer i=0; i<4; i=i+1) begin
            expected_x[i]=map_q16(test_u[i]);
            expected_y[i]=map_q16(test_v[i]);
        end
        repeat (4) @(negedge clk);
        rstn=1;
        for (integer n=0; n<4; n=n+1) begin
            while (!s_ready) @(negedge clk);
            s_u=test_u[n]; s_v=test_v[n]; s_pixel_id=n; s_valid=1;
            @(negedge clk); s_valid=0;
        end
        wait(received == 4);
        $display("PASS: 3:2 fractional coordinates remain in homography range and align with metadata");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "3:2 homography test timed out");
    end
endmodule
