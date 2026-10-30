`timescale 1ns / 1ps

module homography_reference_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg [287:0] coefficients = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [10:0] s_u = 0;
    reg [9:0] s_v = 0;
    reg [19:0] s_pixel_id = 0;
    wire h_valid, h_ready, h_geometry_valid;
    wire signed [31:0] h_sx, h_sy;
    wire [19:0] h_pixel_id;
    wire [31:0] h_frame_id;
    wire [15:0] h_param_version;
    wire h_sof, h_eol, h_eof;
    wire m_valid, m_geometry_valid;
    reg m_ready = 1;
    wire signed [31:0] m_sx, m_sy;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;
    reg [438:0] vectors [0:59];
    reg [63:0] expected_dr_product [0:59];
    reg signed [63:0] expected_x_product [0:59];
    reg signed [63:0] expected_y_product [0:59];
    integer sent = 0;
    integer h_received = 0;
    integer m_received = 0;
    integer cycles = 0;
    reg h_stalled = 0, m_stalled = 0;
    reg [135:0] held_h, held_m;
    wire [135:0] h_bundle = {
        h_sx, h_sy, h_geometry_valid, h_pixel_id,
        h_frame_id, h_param_version, h_sof, h_eol, h_eof
    };
    wire [135:0] m_bundle = {
        m_sx, m_sy, m_geometry_valid, m_pixel_id,
        m_frame_id, m_param_version, m_sof, m_eol, m_eof
    };

    homography_mapper homography (
        .clk(clk), .rstn(rstn), .coefficients(coefficients),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'habcdef12),
        .s_param_version(16'hcafe),
        .s_sof(s_pixel_id == 0), .s_eol(s_pixel_id == 59),
        .s_eof(s_pixel_id == 59),
        .m_valid(h_valid), .m_ready(h_ready),
        .m_sx(h_sx), .m_sy(h_sy),
        .m_geometry_valid(h_geometry_valid),
        .m_pixel_id(h_pixel_id), .m_frame_id(h_frame_id),
        .m_param_version(h_param_version),
        .m_sof(h_sof), .m_eol(h_eol), .m_eof(h_eof)
    );
    fractional_brown_mapper lens (
        .clk(clk), .rstn(rstn),
        .s_valid(h_valid), .s_ready(h_ready),
        .s_sx(h_sx), .s_sy(h_sy), .s_geometry_valid(h_geometry_valid),
        .s_pixel_id(h_pixel_id), .s_frame_id(h_frame_id),
        .s_param_version(h_param_version),
        .s_sof(h_sof), .s_eol(h_eol), .s_eof(h_eof),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_sx(m_sx), .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    always @(negedge clk) if (rstn) begin
        if (sent < 60 && s_ready) begin
            coefficients = vectors[sent][287:0];
            s_u = vectors[sent][298:288];
            s_v = vectors[sent][308:299];
            s_pixel_id = sent;
            s_valid = 1;
            sent = sent + 1;
        end else
            s_valid = 0;
    end

    always @(posedge clk) if (rstn) begin
        cycles = cycles + 1;
        if (homography.valid_pipe[3])
            expected_dr_product[homography.meta[3][70:51]] =
                $unsigned(homography.d3[31:0]) * $unsigned(homography.seed3);
        if (homography.valid_pipe[6] &&
            ({homography.dr_p3_6, 32'b0} + {15'b0, homography.dr_low6}) !==
                expected_dr_product[homography.meta[6][70:51]])
            $fatal(1, "Partial product recombination mismatch for pixel %0d: p3=%h low=%h expected=%h",
                homography.meta[6][70:51], homography.dr_p3_6,
                homography.dr_low6,
                expected_dr_product[homography.meta[6][70:51]]);
        if (homography.valid_pipe[7] &&
            homography.dr_product7 !== expected_dr_product[homography.meta[7][70:51]])
            $fatal(1, "Partial reciprocal product mismatch for pixel %0d: got %h expected %h",
                homography.meta[7][70:51], homography.dr_product7,
                expected_dr_product[homography.meta[7][70:51]]);
        if (homography.valid_pipe[11]) begin
            expected_x_product[homography.meta[11][70:51]] =
                $signed(homography.nx11) * $signed(homography.reciprocal11);
            expected_y_product[homography.meta[11][70:51]] =
                $signed(homography.ny11) * $signed(homography.reciprocal11);
        end
        if (homography.valid_pipe[15] &&
            (homography.product_x16 !== expected_x_product[homography.meta[15][70:51]] ||
             homography.product_y16 !== expected_y_product[homography.meta[15][70:51]]))
            $fatal(1, "Coordinate partial-product mismatch for pixel %0d: got %h,%h expected %h,%h",
                homography.meta[15][70:51], homography.product_x16,
                homography.product_y16,
                expected_x_product[homography.meta[15][70:51]],
                expected_y_product[homography.meta[15][70:51]]);
        m_ready <= cycles % 23 < 14;
        if (h_stalled && (!h_valid || h_bundle !== held_h))
            $fatal(1, "Homography output changed while stalled");
        if (m_stalled && (!m_valid || m_bundle !== held_m))
            $fatal(1, "Brown output changed while stalled");
        h_stalled = h_valid && !h_ready;
        m_stalled = m_valid && !m_ready;
        held_h = h_bundle;
        held_m = m_bundle;
        if (h_valid && h_ready) begin
            if (h_received >= 60 || h_pixel_id !== h_received ||
                h_frame_id !== 32'habcdef12 ||
                h_param_version !== 16'hcafe ||
                h_sof !== (h_received == 0) ||
                h_eol !== (h_received == 59) ||
                h_eof !== (h_received == 59) ||
                h_geometry_valid !== vectors[h_received][373] ||
                h_sx !== vectors[h_received][340:309] ||
                h_sy !== vectors[h_received][372:341])
                $fatal(1, "Homography mismatch at vector %0d: x=%0d y=%0d",
                    h_received, h_sx, h_sy);
            h_received = h_received + 1;
        end
        if (m_valid && m_ready) begin
            if (m_received >= 60 || m_pixel_id !== m_received ||
                m_frame_id !== 32'habcdef12 ||
                m_param_version !== 16'hcafe ||
                m_sof !== (m_received == 0) ||
                m_eol !== (m_received == 59) ||
                m_eof !== (m_received == 59) ||
                m_geometry_valid !== vectors[m_received][438] ||
                (vectors[m_received][438] &&
                    (m_sx !== vectors[m_received][405:374] ||
                     m_sy !== vectors[m_received][437:406])))
                $fatal(1, "Brown mismatch at vector %0d: x=%0d y=%0d",
                    m_received, m_sx, m_sy);
            m_received = m_received + 1;
        end
    end

    initial begin
        $readmemh("homography_reference_vectors.mem", vectors);
        repeat (3) @(negedge clk);
        rstn = 1;
        repeat (180) @(negedge clk);
        if (sent != 60 || h_received != 60 || m_received != 60)
            $fatal(1, "Only sent %0d / homography %0d / Brown %0d of 60 vectors",
                sent, h_received, m_received);
        $display("PASS: Stage 8 60 synthetic homography/Brown reference vectors");
        $finish;
    end
endmodule
