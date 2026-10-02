`timescale 1ns/1ps

// Image-level identity test for the one-transaction Pixel Fetch engine.
// Run from xsim.dir/pixel_fetch_image so the relative .mem paths resolve to
// the project result/sim_assets directory.
module tb_pixel_fetch_image;
    localparam integer IMAGE_WIDTH = 64;
    localparam integer IMAGE_HEIGHT = 48;
    localparam integer ADDR_WIDTH = 16;
    localparam integer MEMORY_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam INPUT_MEM_FILE = "../../result/sim_assets/checkerboard_64x48.mem";
    localparam OUTPUT_MEM_FILE = "../../result/sim_assets/rtl_identity_64x48.mem";

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [ADDR_WIDTH-1:0] in_x0 = {ADDR_WIDTH{1'b0}};
    reg [ADDR_WIDTH-1:0] in_y0 = {ADDR_WIDTH{1'b0}};
    reg [15:0] in_dx_q16 = 16'd0;
    reg [15:0] in_dy_q16 = 16'd0;
    reg in_coord_valid = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire in_ready;
    wire req_valid;
    wire req_ready;
    wire [ADDR_WIDTH-1:0] req_addr;
    wire rsp_valid;
    wire rsp_ready;
    wire [23:0] rsp_data;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    integer output_file;
    integer errors = 0;
    integer x;
    integer y;

    always #5 clk = ~clk;

    pixel_fetch_engine #(
        .FRAME_STRIDE_PIXELS(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) engine (
        .clk(clk),
        .rst_n(rst_n),
        .in_x0(in_x0),
        .in_y0(in_y0),
        .in_dx_q16(in_dx_q16),
        .in_dy_q16(in_dy_q16),
        .in_coord_valid(in_coord_valid),
        .in_valid(in_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .in_ready(in_ready),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    ddr_behavior_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PIXEL_WIDTH(24),
        .MEMORY_WORDS(MEMORY_WORDS),
        .FIXED_LATENCY(2),
        .MAX_LATENCY(2),
        .INIT_FILE(INPUT_MEM_FILE)
    ) ddr (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic send_and_check_identity(input integer pixel_x, input integer pixel_y);
        integer timeout;
        reg [23:0] expected_pixel;
        reg expected_sof;
        reg expected_eol;
        begin
            while (!in_ready) tick;
            @(negedge clk);
            in_x0 = pixel_x;
            in_y0 = pixel_y;
            in_dx_q16 = 16'd0;
            in_dy_q16 = 16'd0;
            in_coord_valid = (pixel_x < IMAGE_WIDTH - 1) && (pixel_y < IMAGE_HEIGHT - 1);
            in_sof = (pixel_x == 0) && (pixel_y == 0);
            in_eol = (pixel_x == IMAGE_WIDTH - 1);
            in_valid = 1'b1;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;

            timeout = 0;
            while (!out_valid && timeout < 100) begin
                tick;
                timeout = timeout + 1;
            end
            if (!out_valid) begin
                $display("FAIL: output timeout at x=%0d y=%0d", pixel_x, pixel_y);
                errors = errors + 1;
            end else begin
                if ((pixel_x < IMAGE_WIDTH - 1) && (pixel_y < IMAGE_HEIGHT - 1))
                    expected_pixel = ddr.memory[pixel_y * IMAGE_WIDTH + pixel_x];
                else
                    expected_pixel = 24'h000000;
                expected_sof = (pixel_x == 0) && (pixel_y == 0);
                expected_eol = (pixel_x == IMAGE_WIDTH - 1);

                if (out_pixel !== expected_pixel) begin
                    $display("FAIL: pixel x=%0d y=%0d got=%h expected=%h", pixel_x, pixel_y, out_pixel, expected_pixel);
                    errors = errors + 1;
                end
                if (out_sof !== expected_sof || out_eol !== expected_eol) begin
                    $display("FAIL: controls x=%0d y=%0d got sof=%b eol=%b", pixel_x, pixel_y, out_sof, out_eol);
                    errors = errors + 1;
                end
                $fdisplay(output_file, "%06h", out_pixel);
            end
        end
    endtask

    initial begin
        output_file = $fopen(OUTPUT_MEM_FILE, "w");
        if (output_file == 0)
            $fatal(1, "cannot open output memory file: %s", OUTPUT_MEM_FILE);

        repeat (3) tick;
        rst_n = 1'b1;

        for (y = 0; y < IMAGE_HEIGHT; y = y + 1)
            for (x = 0; x < IMAGE_WIDTH; x = x + 1)
                send_and_check_identity(x, y);

        $fclose(output_file);
        if (errors == 0)
            $display("TEST_PASS: pixel_fetch_image");
        else
            $display("TEST_FAIL: pixel_fetch_image errors=%0d", errors);
        $finish;
    end
endmodule
