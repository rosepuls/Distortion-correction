`timescale 1ns/1ps

module tb_cached_pixel_fetch_stress;
    localparam integer IMAGE_WIDTH = 64;
    localparam integer IMAGE_HEIGHT = 32;
    localparam integer PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer ADDR_WIDTH = 32;
    localparam [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = 32'h00008000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;
    reg [11:0] in_x0 = 12'd0;
    reg [11:0] in_y0 = 12'd0;
    reg [15:0] in_fx = 16'd0;
    reg [15:0] in_fy = 16'd0;
    reg in_coord_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire [23:0] out_pixel;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    wire rd_cmd_en;
    wire [ADDR_WIDTH-1:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_cmd_ready = 1'b0;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_last = 1'b0;

    integer input_count = 0;
    integer output_count = 0;
    integer command_count = 0;
    integer cycle_count = 0;
    integer timeout_cycles = 0;
    integer errors = 0;
    integer backend_active = 0;
    integer backend_beat = 0;
    integer backend_tx = 0;
    integer backend_ty = 0;
    integer backend_row = 0;
    integer backend_wait = 0;

    always #5 clk = ~clk;

    cached_pixel_fetch_engine #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH), .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_x0(in_x0), .in_y0(in_y0), .in_fx(in_fx), .in_fy(in_fy),
        .in_coord_valid(in_coord_valid), .in_sof(in_sof), .in_eol(in_eol),
        .out_pixel(out_pixel), .out_valid(out_valid),
        .out_sof(out_sof), .out_eol(out_eol),
        .rd_cmd_en(rd_cmd_en), .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr), .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last)
    );

    function automatic [255:0] make_fill_beat(
        input integer tile_x, input integer tile_y,
        input integer row_index, input integer beat_index
    );
        integer lane;
        integer source_x;
        integer source_y;
        begin
            make_fill_beat = 256'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                source_x = tile_x * 32 + beat_index * 8 + lane;
                source_y = tile_y * 4 + row_index;
                make_fill_beat[lane*32 +: 32] = {
                    8'hC3, source_y[7:0], source_x[7:0], 8'h00
                };
            end
        end
    endfunction

    always @(negedge clk) begin
        if (rst_n && input_count < PIXELS && !in_valid && in_ready) begin
            in_valid <= 1'b1;
            in_x0 <= input_count % IMAGE_WIDTH;
            in_y0 <= input_count / IMAGE_WIDTH;
            in_fx <= 16'd0;
            in_fy <= 16'd0;
            in_coord_valid <= ((input_count % IMAGE_WIDTH) < IMAGE_WIDTH - 1)
                              && ((input_count / IMAGE_WIDTH) < IMAGE_HEIGHT - 1);
            in_sof <= (input_count == 0);
            in_eol <= ((input_count % IMAGE_WIDTH) == IMAGE_WIDTH - 1);
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            // Periodic command backpressure, independent of the data path.
            rd_cmd_ready <= ((cycle_count % 13) != 0);
            if (in_valid && in_ready) begin
                input_count = input_count + 1;
                in_valid <= 1'b0;
            end
            if (out_valid)
                output_count = output_count + 1;
        end
    end

    // Variable-latency DDR model. rd_data_valid is held until the reader
    // accepts the beat, so the test also covers data-side backpressure.
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_data_valid <= 1'b0;
            backend_active <= 0;
        end else begin
            if (rd_cmd_en && rd_cmd_ready && !backend_active) begin
                integer byte_offset;
                integer source_row;
                integer source_x;
                command_count = command_count + 1;
                byte_offset = rd_cmd_addr - FRAME_BASE_BYTE_ADDR;
                source_row = byte_offset / (IMAGE_WIDTH * 4);
                source_x = (byte_offset % (IMAGE_WIDTH * 4)) / 4;
                backend_tx <= source_x / 32;
                backend_ty <= source_row / 4;
                backend_row <= source_row % 4;
                backend_beat <= 0;
                backend_wait <= 3 + ((cycle_count + command_count) % 9);
                backend_active <= 1;
            end

            if (backend_active) begin
                if (rd_data_valid && rd_data_ready) begin
                    if (backend_beat == 3) begin
                        rd_data_valid <= 1'b0;
                        backend_active <= 0;
                        rd_data_last <= 1'b0;
                    end else begin
                        backend_beat <= backend_beat + 1;
                        rd_data <= make_fill_beat(
                            backend_tx, backend_ty, backend_row, backend_beat + 1
                        );
                        rd_data_valid <= 1'b1;
                        rd_data_last <= (backend_beat == 2);
                    end
                end else if (!rd_data_valid) begin
                    if (backend_wait != 0)
                        backend_wait <= backend_wait - 1;
                    else begin
                        rd_data <= make_fill_beat(
                            backend_tx, backend_ty, backend_row, backend_beat
                        );
                        rd_data_valid <= 1'b1;
                        rd_data_last <= (backend_beat == 3);
                    end
                end
            end else begin
                rd_data_valid <= 1'b0;
            end
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        while (timeout_cycles < 200000 && output_count < PIXELS) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (input_count != PIXELS || output_count != PIXELS) begin
            $display("FAIL: stress expected %0d input/output pixels, got %0d/%0d",
                     PIXELS, input_count, output_count);
            errors = errors + 1;
        end
        if (command_count == 0) begin
            $display("FAIL: stress DDR model saw no commands");
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "TEST_FAIL: cached_pixel_fetch_stress errors=%0d", errors);

        $display("STRESS_RESULT: pixels=%0d cycles=%0d commands=%0d cycles_per_pixel=%f",
                 PIXELS, timeout_cycles, command_count,
                 timeout_cycles * 1.0 / PIXELS);
        $display("TEST_PASS: cached_pixel_fetch_stress");
        $finish;
    end
endmodule
