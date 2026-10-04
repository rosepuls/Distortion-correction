`timescale 1ns/1ps

module tb_algorithm_frame_writer_rgbx;
    localparam integer IMAGE_WIDTH = 16;
    localparam integer IMAGE_HEIGHT = 2;
    localparam integer DDR_ADDR_WIDTH = 32;
    localparam [DDR_ADDR_WIDTH-1:0] BASE_ADDR = 32'h00004000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg pixel_valid = 1'b0;
    reg [23:0] pixel_data = 24'd0;
    reg pixel_sof = 1'b0;
    reg pixel_eol = 1'b0;
    wire overflow;
    wire frame_complete;
    wire wr_cmd_en;
    wire [DDR_ADDR_WIDTH-1:0] wr_cmd_addr;
    wire [31:0] wr_cmd_len;
    reg wr_cmd_ready = 1'b1;
    reg wr_cmd_done = 1'b0;
    reg wr_bac = 1'b0;
    wire [255:0] wr_ctrl_data;
    reg wr_data_re = 1'b0;

    reg [23:0] source_pixels [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];
    integer errors = 0;
    integer command_count = 0;
    integer beat_count = 0;
    integer active_command = 0;
    integer command_beat = 0;
    integer i;

    always #5 clk = ~clk;

    algorithm_frame_writer_rgbx #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DDR_ADDR_WIDTH(DDR_ADDR_WIDTH),
        .OUTPUT_BASE_ADDR(BASE_ADDR),
        .SIMULATION(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .pixel_sof(pixel_sof),
        .pixel_eol(pixel_eol),
        .overflow(overflow),
        .frame_complete(frame_complete),
        .wr_cmd_en(wr_cmd_en),
        .wr_cmd_addr(wr_cmd_addr),
        .wr_cmd_len(wr_cmd_len),
        .wr_cmd_ready(wr_cmd_ready),
        .wr_cmd_done(wr_cmd_done),
        .wr_bac(wr_bac),
        .wr_ctrl_data(wr_ctrl_data),
        .wr_data_re(wr_data_re)
    );

    always @(posedge clk) begin
        wr_cmd_done <= 1'b0;
        wr_data_re <= 1'b0;

        if (wr_cmd_en && wr_cmd_ready) begin
            command_count = command_count + 1;
            command_beat = 0;
            active_command = 1;
            if (wr_cmd_len !== 32'd2) begin
                $display("FAIL: expected two RGBX beats per line");
                errors = errors + 1;
            end
            if (wr_cmd_addr !== BASE_ADDR + (command_count - 1) * IMAGE_WIDTH * 4) begin
                $display("FAIL: command %0d address %h", command_count, wr_cmd_addr);
                errors = errors + 1;
            end
        end else if (active_command) begin
            wr_data_re <= 1'b1;
            if (wr_data_re) begin
                integer lane;
                integer pixel_index;
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    pixel_index = (command_count - 1) * IMAGE_WIDTH
                                  + command_beat * 8 + lane;
                    if (wr_ctrl_data[lane*32 +: 32]
                        !== {source_pixels[pixel_index], 8'h00}) begin
                        $display("FAIL: beat %0d lane %0d data mismatch",
                                 command_beat, lane);
                        errors = errors + 1;
                    end
                end
                beat_count = beat_count + 1;
                if (command_beat == 1) begin
                    wr_cmd_done <= 1'b1;
                    active_command = 0;
                end else begin
                    command_beat = command_beat + 1;
                end
            end
        end
    end

    initial begin
        for (i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT; i = i + 1)
            source_pixels[i] = {8'h10 + i[7:0], 8'h20 + i[7:0], 8'h30 + i[7:0]};

        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        for (i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT; i = i + 1) begin
            @(negedge clk);
            pixel_valid <= 1'b1;
            pixel_data <= source_pixels[i];
            pixel_sof <= (i == 0);
            pixel_eol <= ((i % IMAGE_WIDTH) == IMAGE_WIDTH - 1);
            @(posedge clk);
        end
        @(negedge clk);
        pixel_valid <= 1'b0;
        pixel_sof <= 1'b0;
        pixel_eol <= 1'b0;

        wait (frame_complete);
        repeat (3) @(posedge clk);

        if (overflow) begin
            $display("FAIL: writer overflowed");
            errors = errors + 1;
        end
        if (command_count != IMAGE_HEIGHT || beat_count != IMAGE_HEIGHT * 2) begin
            $display("FAIL: commands=%0d beats=%0d", command_count, beat_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: algorithm_frame_writer_rgbx errors=%0d", errors);

        $display("TEST_PASS: algorithm_frame_writer_rgbx");
        $finish;
    end
endmodule
