`timescale 1ns / 1ps

module demo_radial_mapper_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [10:0] s_u = 0;
    reg [9:0] s_v = 0;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 0;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 1;
    wire signed [31:0] m_sx, m_sy;
    wire m_geometry_valid;
    wire signed [31:0] m_j00, m_j01, m_j10, m_j11;
    wire m_j_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;

    demo_radial_mapper dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_sx(m_sx), .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid),
        .m_j00(m_j00), .m_j01(m_j01), .m_j10(m_j10), .m_j11(m_j11),
        .m_j_valid(m_j_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic tick; begin @(posedge clk); #1; end endtask
    task automatic check;
        input condition; input [8*120-1:0] message;
        begin if (condition !== 1'b1) begin
            $display("FAIL at %0t: %0s", $time, message); $fatal(1);
        end end
    endtask
    task automatic drive;
        input [10:0] u; input [9:0] v; input [19:0] id;
        begin
            s_valid=1; s_u=u; s_v=v; s_pixel_id=id;
            s_frame_id=32'habcdef01; s_param_version=16'hd004;
            s_sof=(id==0); s_eol=(u==1279); s_eof=(id==921599);
        end
    endtask

    initial begin
        tick(); tick();
        @(negedge clk); rstn=1;
        drive(11'd640,10'd360,20'd0);
        tick();
        @(negedge clk); drive(11'd1279,10'd719,20'd921599);
        tick();
        @(negedge clk); s_valid=0;
        tick();
        check(m_valid, "center result appears after two pipeline shifts");
        check(m_sx===32'sh02800000 && m_sy===32'sh01680000,
              "optical center remains fixed");
        check(m_pixel_id===0 && m_sof && !m_eol && !m_eof,
              "center metadata preserved");
        check(m_geometry_valid && !m_j_valid, "geometry valid and demo Jacobian unavailable");
        check(m_j00===0 && m_j01===0 && m_j10===0 && m_j11===0,
              "invalid Jacobian is explicitly zero");
        tick();
        check(m_valid, "corner follows center without a bubble");
        check(m_sx===32'sh0527ebd5 && m_sy===32'sh02e5fd7b,
              "corner uses literal radial Q16.16 result");
        check(m_pixel_id===20'd921599 && m_eol && m_eof,
              "corner metadata preserved");

        // Hold a completed result and prove backpressure freezes every stage.
        @(negedge clk); drive(11'd0,10'd0,20'd7);
        tick();
        @(negedge clk); s_valid=0;
        tick();
        @(negedge clk); m_ready=0;
        tick();
        check(m_valid && m_pixel_id===7, "new result reached output");
        check(m_sx===-32'sd2696000 && m_sy===-32'sd1516500,
              "negative corner keeps signed arithmetic shift");
        check(!s_ready, "full pipeline backpressures input");
        tick();
        check(m_sx===-32'sd2696000 && m_sy===-32'sd1516500 && m_pixel_id===7,
              "stalled result remains stable");

        @(negedge clk); rstn=0;
        tick();
        check(!m_valid && !s_ready, "reset flushes radial mapper");
        $display("PASS: demo_radial_mapper radial arithmetic, pipeline and metadata test");
        $finish;
    end
endmodule
