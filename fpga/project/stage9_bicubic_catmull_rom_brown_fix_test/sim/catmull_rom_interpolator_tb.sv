`timescale 1ns / 1ps

module catmull_rom_interpolator_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg s_valid = 0;
    wire s_ready;
    reg [511:0] s_samples = 0;
    reg [15:0] s_fx = 0, s_fy = 0;
    reg [15:0] s_neighbor_valid = 16'hffff;
    reg s_geometry_valid = 1;
    reg [19:0] s_pixel_id = 0;
    reg [31:0] s_frame_id = 0;
    reg [15:0] s_param_version = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0;
    wire m_valid;
    reg m_ready = 0;
    wire [31:0] m_pixel;
    wire m_geometry_valid;
    wire [19:0] m_pixel_id;
    wire [31:0] m_frame_id;
    wire [15:0] m_param_version;
    wire m_sof, m_eol, m_eof;
    integer row, col;
    integer invalid_cycles;

    pipelined_catmull_rom_interpolator dut (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_samples(s_samples), .s_fx(s_fx), .s_fy(s_fy),
        .s_neighbor_valid(s_neighbor_valid), .s_geometry_valid(s_geometry_valid),
        .s_pixel_id(s_pixel_id), .s_frame_id(s_frame_id),
        .s_param_version(s_param_version), .s_sof(s_sof), .s_eol(s_eol),
        .s_eof(s_eof), .m_valid(m_valid), .m_ready(m_ready),
        .m_pixel(m_pixel), .m_geometry_valid(m_geometry_valid),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_param_version(m_param_version), .m_sof(m_sof),
        .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic set_constant(input [7:0] value);
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                s_samples[i*32 +: 32] = {value, value, value, 8'hA5};
        end
    endtask

    task automatic set_x_ramp;
        integer r, c;
        reg [7:0] value;
        begin
            for (r = 0; r < 4; r = r + 1)
                for (c = 0; c < 4; c = c + 1) begin
                    value = 10 + c * 10;
                    s_samples[(r*4+c)*32 +: 32] = {value,value,value,8'hFE};
                end
        end
    endtask

    task automatic set_overshoot(input bit high_case);
        integer r, c;
        reg [7:0] value;
        begin
            for (r = 0; r < 4; r = r + 1)
                for (c = 0; c < 4; c = c + 1) begin
                    if (high_case)
                        value = ((c == 1) || (c == 2)) ? 8'd255 : 8'd0;
                    else
                        value = ((c == 0) || (c == 3)) ? 8'd255 : 8'd0;
                    s_samples[(r*4+c)*32 +: 32] = {value,value,value,8'h77};
                end
        end
    endtask

    task automatic run_case(
        input [15:0] fx, input [15:0] fy,
        input [31:0] expected_pixel, input [19:0] id
    );
        integer cycles;
        begin
            @(negedge clk);
            while (!s_ready) @(negedge clk);
            s_fx = fx; s_fy = fy; s_geometry_valid = 1;
            s_neighbor_valid = 16'hffff; s_pixel_id = id;
            s_frame_id = 32'hABCD0000 + id;
            s_param_version = 16'h5A3C; s_sof = (id == 1);
            s_eol = (id == 3); s_eof = (id == 4); s_valid = 1;
            @(posedge clk); #1; s_valid = 0;
            cycles = 0;
            while (!m_valid && cycles < 30) begin
                @(posedge clk); #1; cycles = cycles + 1;
            end
            if (!m_valid) $fatal(1, "Timed out waiting for Catmull-Rom result");
            repeat (2) begin
                if (m_pixel !== expected_pixel || !m_geometry_valid ||
                    m_pixel_id !== id || m_frame_id !== 32'hABCD0000 + id ||
                    m_param_version !== 16'h5A3C ||
                    m_sof !== (id == 1) || m_eol !== (id == 3) ||
                    m_eof !== (id == 4))
                    $fatal(1, "Catmull-Rom result/metadata mismatch for id %0d: %h", id, m_pixel);
                @(posedge clk); #1;
            end
            @(negedge clk); m_ready = 1;
            @(posedge clk); #1;
            if (m_valid) $fatal(1, "Catmull-Rom output did not retire");
            @(negedge clk); m_ready = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1;

        set_constant(8'd73);
        run_case(0, 0, 32'h49494900, 1);

        set_x_ramp();
        run_case(16'h8000, 16'h8000, 32'h19191900, 2);

        set_constant(8'd131);
        run_case(16'h3456, 16'hABCD, 32'h83838300, 3);

        set_overshoot(1);
        run_case(16'h4000, 0, 32'hFFFFFF00, 4);
        set_overshoot(0);
        run_case(16'h4000, 0, 32'h00000000, 5);

        // Invalid support always produces black while keeping metadata.
        set_constant(8'd200);
        @(negedge clk);
        while (!s_ready) @(negedge clk);
        s_fx = 0; s_fy = 0; s_neighbor_valid = 0; s_geometry_valid = 0;
        s_pixel_id = 20'habcde; s_frame_id = 32'h12345678;
        s_param_version = 16'h1111; s_sof = 0; s_eol = 1; s_eof = 0;
        s_valid = 1;
        @(posedge clk); #1; s_valid = 0;
        invalid_cycles = 0;
        while (!m_valid && invalid_cycles < 30) begin
            @(posedge clk); #1; invalid_cycles = invalid_cycles + 1;
        end
        if (!m_valid || m_pixel !== 0 || m_geometry_valid ||
            m_pixel_id !== 20'habcde || m_frame_id !== 32'h12345678 ||
            m_param_version !== 16'h1111 || m_sof || !m_eol || m_eof)
            $fatal(1, "Invalid geometry result did not return black with metadata");
        @(negedge clk); m_ready = 1;
        @(posedge clk); #1;

        $display("PASS: Stage 9 Catmull-Rom fixed-point, saturation and elastic metadata test");
        $finish;
    end
endmodule
