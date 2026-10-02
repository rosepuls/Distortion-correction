`timescale 1ns/1ps

module tb_ddr3_frame_reader_rgbx;
    localparam integer IMAGE_WIDTH = 16;
    localparam integer IMAGE_HEIGHT = 2;
    localparam integer DDR_ADDR_WIDTH = 32;
    localparam [DDR_ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = 32'h00005000;

    reg ddr_clk = 1'b0;
    reg pixel_clk = 1'b0;
    reg rst_n = 1'b0;
    reg display_enable = 1'b0;
    reg rd_fsync = 1'b0;
    reg rd_en = 1'b0;
    wire vout_de;
    wire [23:0] vout_data;
    wire underflow;
    wire rd_cmd_en;
    wire [DDR_ADDR_WIDTH-1:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_cmd_ready = 1'b1;
    reg rd_cmd_done = 1'b0;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;

    reg [23:0] pixels [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];
    integer errors = 0;
    integer command_count = 0;
    integer output_count = 0;
    integer active_line = 0;
    integer active_beat = 0;
    reg backend_active = 1'b0;

    always #5 ddr_clk = ~ddr_clk;
    always #7 pixel_clk = ~pixel_clk;

    ddr3_frame_reader_rgbx #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DDR_ADDR_WIDTH(DDR_ADDR_WIDTH),
        .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) dut (
        .ddr_clk(ddr_clk),
        .ddr_rst_n(rst_n),
        .pixel_clk(pixel_clk),
        .pixel_rst_n(rst_n),
        .display_enable(display_enable),
        .rd_fsync(rd_fsync),
        .rd_en(rd_en),
        .vout_de(vout_de),
        .vout_data(vout_data),
        .underflow(underflow),
        .rd_cmd_en(rd_cmd_en),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_done(rd_cmd_done),
        .rd_data(rd_data),
        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready)
    );

    function automatic [31:0] rgbx_word(input integer pixel_index);
        begin
            rgbx_word = {pixels[pixel_index], 8'h00};
        end
    endfunction

    function automatic [255:0] make_beat(input integer line_index, input integer beat_index);
        integer lane;
        begin
            make_beat = 256'd0;
            for (lane = 0; lane < 8; lane = lane + 1)
                make_beat[lane*32 +: 32] = rgbx_word(
                    line_index * IMAGE_WIDTH + beat_index * 8 + lane
                );
        end
    endfunction

    always @(posedge ddr_clk) begin
        rd_cmd_done <= 1'b0;
        rd_data_valid <= 1'b0;

        if (rd_cmd_en && rd_cmd_ready && !backend_active) begin
            command_count = command_count + 1;
            if (rd_cmd_len !== 32'd2) begin
                $display("FAIL: expected two RGBX beats, got %0d", rd_cmd_len);
                errors = errors + 1;
            end
            if (rd_cmd_addr !== FRAME_BASE_BYTE_ADDR
                + (command_count - 1) * IMAGE_WIDTH * 4) begin
                $display("FAIL: command address %h", rd_cmd_addr);
                errors = errors + 1;
            end
            active_line <= command_count - 1;
            active_beat <= 0;
            backend_active <= 1'b1;
        end else if (backend_active && rd_data_ready) begin
            rd_data <= make_beat(active_line, active_beat);
            rd_data_valid <= 1'b1;
            if (active_beat == 1) begin
                rd_cmd_done <= 1'b1;
                backend_active <= 1'b0;
            end else begin
                active_beat <= active_beat + 1;
            end
        end
    end

    always @(posedge pixel_clk) begin
        if (vout_de) begin
            if (vout_data !== pixels[output_count]) begin
                $display("FAIL: pixel %0d expected %h got %h",
                         output_count, pixels[output_count], vout_data);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    task automatic drive_active_line;
        integer x;
        begin
            for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                rd_en <= 1'b1;
                @(posedge pixel_clk);
            end
            rd_en <= 1'b0;
            repeat (12) @(posedge pixel_clk);
        end
    endtask

    integer i;
    initial begin
        for (i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT; i = i + 1)
            pixels[i] = {8'h20 + i[7:0], 8'h40 + i[7:0], 8'h60 + i[7:0]};

        repeat (5) @(posedge ddr_clk);
        rst_n <= 1'b1;
        display_enable <= 1'b1;
        repeat (3) @(posedge pixel_clk);
        rd_fsync <= 1'b1;
        @(posedge pixel_clk);
        rd_fsync <= 1'b0;

        repeat (30) @(posedge pixel_clk);
        drive_active_line();
        drive_active_line();
        repeat (8) @(posedge pixel_clk);

        if (command_count != IMAGE_HEIGHT) begin
            $display("FAIL: expected %0d commands, got %0d", IMAGE_HEIGHT, command_count);
            errors = errors + 1;
        end
        if (output_count != IMAGE_WIDTH*IMAGE_HEIGHT) begin
            $display("FAIL: expected %0d pixels, got %0d",
                     IMAGE_WIDTH*IMAGE_HEIGHT, output_count);
            errors = errors + 1;
        end
        if (underflow) begin
            $display("FAIL: RGBX reader reported underflow");
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr3_frame_reader_rgbx errors=%0d", errors);

        $display("TEST_PASS: ddr3_frame_reader_rgbx");
        $finish;
    end
endmodule
