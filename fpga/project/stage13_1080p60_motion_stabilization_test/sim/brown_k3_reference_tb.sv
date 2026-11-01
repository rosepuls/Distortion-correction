`timescale 1ns / 1ps

module brown_k3_reference_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg signed [31:0] s_sx = 0;
    reg signed [31:0] s_sy = 0;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 32'h12345678;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 1;
    wire signed [31:0] m_sx, m_sy;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    integer cycles = 0;
    integer received = 0;
    reg stalled = 0;
    reg [135:0] held_output;
    wire [135:0] output_bundle = {
        m_sx, m_sy, m_geometry_valid, m_pixel_id,
        m_frame_id, m_param_version, m_sof, m_eol, m_eof
    };

    fractional_brown_mapper dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_sx(s_sx), .s_sy(s_sy), .s_geometry_valid(1'b1),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_sx(m_sx), .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send_pixel(
        input integer u, input integer v, input integer id
    );
        begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_sx = u <<< 16;
            s_sy = v <<< 16;
            s_pixel_id = id;
            s_param_version = 16'h5500 + id;
            s_sof = (id == 0);
            s_eol = (id == 3);
            s_eof = (id == 3);
            s_valid = 1;
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    always @(posedge clk) if (rstn) begin
        cycles = cycles + 1;
        m_ready <= (cycles % 17 < 5) || (cycles % 17 > 10);
        if (stalled && (!m_valid || output_bundle !== held_output))
            $fatal(1, "Brown k3 output changed while stalled");
        stalled = m_valid && !m_ready;
        held_output = output_bundle;

        if (m_valid && m_ready) begin
            if (!m_geometry_valid || m_pixel_id !== received ||
                m_frame_id !== 32'h12345678 ||
                m_param_version !== (16'h5500 + received) ||
                m_sof !== (received == 0) ||
                m_eol !== (received == 3) || m_eof !== (received == 3))
                $fatal(1, "Brown k3 metadata mismatch at pixel %0d", received);
            case (received)
                0: if (m_sx !== 32'sd41940489 || m_sy !== 32'sd23592106)
                    $fatal(1, "Center coordinate mismatch: %0d,%0d", m_sx, m_sy);
                1: if (m_sx !== 32'sd63233724 || m_sy !== 32'sd31936345)
                    $fatal(1, "k3 reference mismatch at (1000,500): %0d,%0d", m_sx, m_sy);
                2: if (m_sx !== 32'sd16206088 || m_sy !== 32'sd40345076)
                    $fatal(1, "k3 reference mismatch at (200,650): %0d,%0d", m_sx, m_sy);
                3: if (m_sx !== 32'sd75243123 || m_sy !== 32'sd30959534)
                    $fatal(1, "k3/negative-Y reference mismatch at (1279,500): %0d,%0d", m_sx, m_sy);
                default: $fatal(1, "Received unexpected pixel %0d", received);
            endcase
            received = received + 1;
        end
    end

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1;
        send_pixel(640, 360, 0);
        send_pixel(1000, 500, 1);
        send_pixel(200, 650, 2);
        send_pixel(1279, 500, 3);
        repeat (80) @(negedge clk);
        if (received != 4) $fatal(1, "Received only %0d of 4 pixels", received);
        $display("PASS: calibrated Brown k3 reference and backpressure");
        $finish;
    end
endmodule
