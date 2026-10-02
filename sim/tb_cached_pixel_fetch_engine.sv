`timescale 1ns/1ps

module tb_cached_pixel_fetch_engine;
    localparam integer IMAGE_WIDTH = 64;
    localparam integer IMAGE_HEIGHT = 32;
    localparam integer ADDR_WIDTH = 32;
    localparam [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = 32'h00002000;

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
    reg rd_cmd_ready = 1'b1;
    wire [ADDR_WIDTH-1:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_last = 1'b0;

    integer errors = 0;
    integer command_count = 0;
    integer backend_active = 0;
    integer backend_beat = 0;
    integer backend_tx = 0;
    integer backend_ty = 0;
    integer backend_row = 0;
    integer backend_wait = 0;

    always #5 clk = ~clk;

    cached_pixel_fetch_engine #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_x0(in_x0),
        .in_y0(in_y0),
        .in_fx(in_fx),
        .in_fy(in_fy),
        .in_coord_valid(in_coord_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol),
        .rd_cmd_en(rd_cmd_en),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready),
        .rd_data(rd_data),
        .rd_data_last(rd_data_last)
    );

    function automatic [31:0] source_word(input integer source_x, input integer source_y);
        begin
            source_word = {8'hC3, source_y[7:0], source_x[7:0], 8'h5A};
        end
    endfunction

    function automatic [255:0] make_fill_beat(
        input integer tile_x,
        input integer tile_y,
        input integer row_index,
        input integer beat_index
    );
        integer lane;
        begin
            make_fill_beat = 256'd0;
            for (lane = 0; lane < 8; lane = lane + 1)
                make_fill_beat[lane*32 +: 32] = source_word(
                    tile_x * 32 + beat_index * 8 + lane,
                    tile_y * 4 + row_index
                );
        end
    endfunction

    always @(posedge clk) begin
        if (rd_cmd_en && rd_cmd_ready) begin
            integer byte_offset;
            integer source_row;
            integer source_x;
            command_count = command_count + 1;
            if (rd_cmd_len !== 32'd4) begin
                $display("FAIL: expected four-beat DDR command");
                errors = errors + 1;
            end
            byte_offset = rd_cmd_addr - FRAME_BASE_BYTE_ADDR;
            source_row = byte_offset / (IMAGE_WIDTH * 4);
            source_x = (byte_offset % (IMAGE_WIDTH * 4)) / 4;
            backend_tx <= source_x / 32;
            backend_ty <= source_row / 4;
            backend_row <= source_row % 4;
            backend_beat <= 0;
            backend_wait <= 1;
            backend_active <= 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_data_valid <= 1'b0;
            rd_data <= 256'd0;
            rd_data_last <= 1'b0;
            backend_active <= 0;
        end else begin
            if (rd_data_valid && rd_data_ready) begin
                rd_data_valid <= 1'b0;
                if (backend_beat == 3) begin
                    rd_data_last <= 1'b0;
                    backend_active <= 0;
                end else begin
                    backend_beat <= backend_beat + 1;
                end
            end else if (backend_active && !rd_data_valid) begin
                if (backend_wait != 0) begin
                    backend_wait <= backend_wait - 1;
                end else begin
                    rd_data <= make_fill_beat(
                        backend_tx, backend_ty, backend_row, backend_beat
                    );
                    rd_data_valid <= 1'b1;
                    rd_data_last <= (backend_beat == 3);
                end
            end
        end
    end

    task automatic send_and_check(
        input integer x0,
        input integer y0,
        input integer valid_value,
        input integer sof_value,
        input integer eol_value
    );
        reg [23:0] expected_pixel;
        begin
            expected_pixel = valid_value ? {8'hC3, y0[7:0], x0[7:0]} : 24'd0;
            @(negedge clk);
            in_x0 <= x0;
            in_y0 <= y0;
            in_fx <= 16'd0;
            in_fy <= 16'd0;
            in_coord_valid <= valid_value;
            in_sof <= sof_value;
            in_eol <= eol_value;
            in_valid <= 1'b1;
            while (1) begin
                @(posedge clk);
                if (in_ready)
                    break;
            end
            @(negedge clk);
            in_valid <= 1'b0;

            while (1) begin
                @(posedge clk);
                if (out_valid) begin
                    if (out_pixel !== expected_pixel
                        || out_sof !== sof_value
                        || out_eol !== eol_value) begin
                        $display("FAIL: output mismatch at (%0d,%0d): pixel=%h sof=%0d eol=%0d",
                                 x0, y0, out_pixel, out_sof, out_eol);
                        errors = errors + 1;
                    end
                    break;
                end
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        send_and_check(1, 1, 1, 1, 0);
        send_and_check(31, 1, 1, 0, 1);
        send_and_check(2, 2, 1, 0, 0);
        send_and_check(10, 10, 0, 0, 0);

        if (command_count != 8) begin
            $display("FAIL: expected eight DDR row commands, got %0d", command_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: cached_pixel_fetch_engine errors=%0d", errors);

        $display("TEST_PASS: cached_pixel_fetch_engine");
        $finish;
    end
endmodule
