`timescale 1ns / 1ps

module identity_coordinate_pipeline_tb;
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 3;
    localparam integer TOTAL = WIDTH * HEIGHT;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg rstn = 1'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg [10:0] s_u = 11'd0;
    reg [9:0] s_v = 10'd0;
    reg [19:0] s_pixel_id = 20'd0;
    reg [31:0] s_frame_id = 32'ha5a55a5a;
    reg [15:0] s_param_version = 16'h0033;
    reg s_sof = 1'b0;
    reg s_eol = 1'b0;
    reg s_eof = 1'b0;

    wire m_valid;
    reg m_ready = 1'b0;
    wire signed [31:0] m_sx;
    wire signed [31:0] m_sy;
    wire m_geometry_valid;
    wire signed [31:0] m_j00;
    wire signed [31:0] m_j01;
    wire signed [31:0] m_j10;
    wire signed [31:0] m_j11;
    wire m_j_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof;
    wire m_eol;
    wire m_eof;
    wire [2:0] fifo_level;

    integer sent = 0;
    integer received = 0;
    integer cycles = 0;
    reg saw_input_backpressure = 1'b0;

    identity_coordinate_pipeline #(
        .FIFO_DEPTH(4)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_u(s_u),
        .s_v(s_v),
        .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_eof(s_eof),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_sx(m_sx),
        .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid),
        .m_j00(m_j00),
        .m_j01(m_j01),
        .m_j10(m_j10),
        .m_j11(m_j11),
        .m_j_valid(m_j_valid),
        .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof),
        .m_eol(m_eol),
        .m_eof(m_eof),
        .fifo_level(fifo_level)
    );

    task automatic check;
        input condition;
        input [8*128-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    always @(negedge clk) begin
        if (!rstn) begin
            s_valid <= 1'b0;
            m_ready <= 1'b0;
        end else begin
            // Force the mapper and FIFO to fill first, then use an irregular
            // downstream schedule so ready propagates through both stages.
            if (cycles < 8)
                m_ready <= 1'b0;
            else
                m_ready <= ((cycles % 5) != 1) && ((cycles % 7) != 3);

            if (sent < TOTAL) begin
                s_valid <= 1'b1;
                s_u <= sent % WIDTH;
                s_v <= sent / WIDTH;
                s_pixel_id <= sent;
                s_sof <= (sent == 0);
                s_eol <= ((sent % WIDTH) == WIDTH - 1);
                s_eof <= (sent == TOTAL - 1);
            end else begin
                s_valid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (s_valid && !s_ready)
                saw_input_backpressure = 1'b1;
            if (s_valid && s_ready)
                sent = sent + 1;

            if (m_valid && m_ready) begin
                check(m_pixel_id === received, "pixel ids remain ordered");
                check(m_sx === $signed((received % WIDTH) * 65536),
                      "identity sx survives mapper and FIFO");
                check(m_sy === $signed((received / WIDTH) * 65536),
                      "identity sy survives mapper and FIFO");
                check(m_geometry_valid, "geometry valid survives pipeline");
                check(m_j_valid && m_j00 === 32'sh00010000 &&
                      m_j01 === 32'sd0 && m_j10 === 32'sd0 &&
                      m_j11 === 32'sh00010000,
                      "Q16.16 identity Jacobian survives pipeline");
                check(m_frame_id === 32'ha5a55a5a && m_param_version === 16'h0033,
                      "frame and parameter versions survive pipeline");
                check(m_sof === (received == 0), "SOF remains aligned");
                check(m_eol === ((received % WIDTH) == WIDTH - 1),
                      "EOL remains aligned");
                check(m_eof === (received == TOTAL - 1), "EOF remains aligned");
                received = received + 1;
                if (received == TOTAL) begin
                    check(saw_input_backpressure,
                          "test filled the queue and exercised propagated backpressure");
                    $display("PASS: identity mapper and coordinate FIFO preserve 24 stalled coordinates");
                    $finish;
                end
            end
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
    end

    initial begin
        repeat (300) @(posedge clk);
        $display("FAIL: identity coordinate pipeline timeout sent=%0d received=%0d", sent, received);
        $fatal(1);
    end
endmodule
