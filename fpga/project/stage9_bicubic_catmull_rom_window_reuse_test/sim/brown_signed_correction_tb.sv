`timescale 1ns / 1ps

module brown_signed_correction_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg signed [31:0] s_sx = 0;
    reg signed [31:0] s_sy = 0;
    reg [19:0] s_pixel_id = 0;
    wire m_valid;
    wire signed [31:0] m_sx, m_sy;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;
    integer received = 0;

    fractional_brown_mapper dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_sx(s_sx), .s_sy(s_sy), .s_geometry_valid(1'b1),
        .s_pixel_id(s_pixel_id), .s_frame_id(32'd7),
        .s_param_version(16'd3), .s_sof(1'b0), .s_eol(1'b0),
        .s_eof(1'b0), .m_valid(m_valid), .m_ready(1'b1),
        .m_sx(m_sx), .m_sy(m_sy), .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version), .m_sof(m_sof),
        .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send_pixel(input integer x, input integer y, input [19:0] id);
        begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_sx = x <<< 16;
            s_sy = y <<< 16;
            s_pixel_id = id;
            s_valid = 1;
            @(negedge clk);
            s_valid = 0;
        end
    endtask

    always @(posedge clk) if (rstn && m_valid) begin
        if (!m_geometry_valid || m_frame_id !== 32'd7 ||
            m_param_version !== 16'd3)
            $fatal(1, "Brown metadata/geometry mismatch at %0d", received);
        case (received)
            0: if (m_pixel_id !== 20'h8f087 || m_sy !== 32'h01c3b5d6)
                $fatal(1, "x903 y457: got id=%h sy=%h", m_pixel_id, m_sy);
            1: if (m_pixel_id !== 20'h8f088 || m_sy !== 32'h01c3af2b)
                $fatal(1, "x904 y457: got id=%h sy=%h", m_pixel_id, m_sy);
            2: if (m_pixel_id !== 20'h379a4 || m_sy !== 32'h00cc203d)
                $fatal(1, "x1188 y177: got id=%h sy=%h", m_pixel_id, m_sy);
            default: $fatal(1, "Unexpected Brown output");
        endcase
        received = received + 1;
    end

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1;
        send_pixel(903, 457, 20'h8f087);
        send_pixel(904, 457, 20'h8f088);
        send_pixel(1188, 177, 20'h379a4);
        repeat (40) @(negedge clk);
        if (received != 3) $fatal(1, "Only received %0d of 3 pixels", received);
        $display("PASS: Brown signed Y correction at hardware capture coordinates");
        $finish;
    end
endmodule
