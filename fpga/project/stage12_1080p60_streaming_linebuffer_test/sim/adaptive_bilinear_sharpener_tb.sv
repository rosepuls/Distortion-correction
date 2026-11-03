`timescale 1ns / 1ps

module adaptive_bilinear_sharpener_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [31:0] p00, p10, p01, p11;
    reg [15:0] fx, fy;
    wire m_valid;
    wire [31:0] m_pixel;
    wire [20:0] m_pixel_id;
    reg m_ready = 1'b0;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof, m_geometry_valid;

    adaptive_bilinear_sharpener #(.EDGE_THRESHOLD(12)) dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_p00(p00), .s_p10(p10), .s_p01(p01), .s_p11(p11),
        .s_fx(fx), .s_fy(fy), .s_neighbor_valid(4'b1111),
        .s_geometry_valid(1'b1), .s_pixel_id(21'd2073599),
        .s_frame_id(32'h12345678), .s_param_version(16'h0031),
        .s_sof(1'b1), .s_eol(1'b1), .s_eof(1'b1),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send(input [31:0] a, b, c, d, input [15:0] xfrac, yfrac);
        begin
            @(negedge clk);
            p00=a; p10=b; p01=c; p11=d; fx=xfrac; fy=yfrac;
            s_valid=1'b1;
            while (!s_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk); s_valid=1'b0;
        end
    endtask

    task automatic expect_pixel(input [31:0] expected);
        begin
            wait(m_valid);
            if (m_pixel !== expected || m_pixel_id !== 21'd2073599 ||
                m_frame_id !== 32'h12345678 || m_param_version !== 16'h0031 ||
                !m_geometry_valid || !m_sof || !m_eol || !m_eof)
                $fatal(1,"FAIL: output pixel=%h expected=%h",m_pixel,expected);
            @(negedge clk); m_ready=1'b1;
            @(posedge clk);
            @(negedge clk); m_ready=1'b0;
        end
    endtask

    initial begin
        p00=0; p10=0; p01=0; p11=0; fx=0; fy=0;
        repeat(3) @(negedge clk); rstn=1'b1;
        // Flat patches are unchanged regardless of the interpolation phase.
        send(32'h50505000,32'h50505000,32'h50505000,32'h50505000,16'hc000,16'h4000);
        expect_pixel(32'h50505000);
        // 0..200 step edge: bilinear gives 150 and bounded 1/4 edge
        // compensation gives 162. RGBX low byte remains zero.
        send(32'h00000000,32'hc8000000,32'h00000000,32'hc8000000,16'hc000,16'h8000);
        expect_pixel(32'ha2000000);
        // A low-contrast 100..105 patch stays unsharpened at threshold 12.
        send(32'h64646400,32'h69696900,32'h64646400,32'h69696900,16'hc000,16'h8000);
        expect_pixel(32'h68686800);
        // A strongly weighted corner would overshoot 200 without the local
        // min/max clamp; the result must stop at the brightest neighbor.
        send(32'h00000000,32'h00000000,32'h00000000,32'hc8c8c800,16'hf000,16'hf000);
        expect_pixel(32'hc8c8c800);
        $display("PASS: adaptive bilinear edge compensation, contrast gate, clamp path, metadata");
        $finish;
    end
    initial begin #10000; $fatal(1,"FAIL: sharpener simulation timed out"); end
endmodule
