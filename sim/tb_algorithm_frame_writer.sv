`timescale 1ns/1ps

module tb_algorithm_frame_writer;
    localparam integer IMAGE_WIDTH = 32;
    localparam integer IMAGE_HEIGHT = 2;
    localparam [27:0] OUTPUT_BASE_ADDR = 28'h0800000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg pixel_valid = 1'b0;
    reg [23:0] pixel_data = 24'd0;
    reg pixel_sof = 1'b0;
    reg pixel_eol = 1'b0;
    wire overflow;
    wire frame_complete;

    wire wr_cmd_en;
    wire [27:0] wr_cmd_addr;
    wire [31:0] wr_cmd_len;
    reg wr_cmd_ready = 1'b1;
    reg wr_cmd_done = 1'b0;
    reg wr_bac = 1'b0;
    wire [255:0] wr_ctrl_data;
    reg wr_data_re = 1'b0;

    integer errors = 0;
    integer command_count = 0;
    integer beat_index = 0;
    integer active_beats = 0;
    integer timeout;
    reg backend_active = 1'b0;
    reg [27:0] captured_addr [0:1];
    reg [31:0] captured_len [0:1];
    reg [255:0] captured_data [0:5];

    always #5 clk = ~clk;

    algorithm_frame_writer #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DDR_ADDR_WIDTH(28),
        .OUTPUT_BASE_ADDR(OUTPUT_BASE_ADDR),
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

        if (wr_cmd_en && wr_cmd_ready && !backend_active) begin
            captured_addr[command_count] <= wr_cmd_addr;
            captured_len[command_count] <= wr_cmd_len;
            beat_index <= 0;
            active_beats <= wr_cmd_len;
            backend_active <= 1'b1;
            command_count <= command_count + 1;
        end else if (backend_active) begin
            wr_data_re <= 1'b1;
            // Data is sampled only after the request has been visible for a
            // full cycle; the writer advances its read address on that edge.
            if (wr_data_re) begin
                captured_data[(command_count-1)*3 + beat_index] <= wr_ctrl_data;
                if (beat_index == active_beats - 1) begin
                    backend_active <= 1'b0;
                    wr_cmd_done <= 1'b1;
                end else begin
                    beat_index <= beat_index + 1;
                end
            end
        end
    end

    task automatic send_pixel(input [23:0] value, input bit sof, input bit eol,
                              input integer idle_cycles);
        begin
            repeat (idle_cycles) @(posedge clk);
            pixel_data <= value;
            pixel_sof <= sof;
            pixel_eol <= eol;
            pixel_valid <= 1'b1;
            @(posedge clk);
            pixel_valid <= 1'b0;
            pixel_sof <= 1'b0;
            pixel_eol <= 1'b0;
        end
    endtask

    task automatic send_line(input integer line_index);
        integer x;
        reg [23:0] value;
        begin
            for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                if (line_index == 0 && x == 0) value = 24'h11_22_33;
                else if (line_index == 0 && x == 1) value = 24'h44_55_66;
                else if (line_index == 0 && x == 2) value = 24'h77_88_99;
                else if (line_index == 0 && x == 3) value = 24'hAA_BB_CC;
                else if (line_index == 1 && x == 0) value = 24'hDE_AD_01;
                else if (line_index == 1 && x == 1) value = 24'hBE_EF_02;
                else if (line_index == 1 && x == 2) value = 24'hCA_FE_03;
                else if (line_index == 1 && x == 3) value = 24'hBA_BE_04;
                else value = 24'd0;
                send_pixel(value, (line_index == 0 && x == 0),
                           (x == IMAGE_WIDTH-1), (x % 3));
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        send_line(0);
        send_line(1);

        for (timeout = 0; timeout < 500 && !frame_complete; timeout = timeout + 1)
            @(posedge clk);

        if (!frame_complete) begin
            $display("FAIL: timeout waiting for completed output frame");
            errors = errors + 1;
        end
        if (overflow) begin
            $display("FAIL: line buffers overflowed despite normal backend service");
            errors = errors + 1;
        end
        if (command_count != 2) begin
            $display("FAIL: expected 2 line commands, got %0d", command_count);
            errors = errors + 1;
        end
        if (captured_addr[0] !== OUTPUT_BASE_ADDR ||
            captured_addr[1] !== OUTPUT_BASE_ADDR + 28'd24) begin
            $display("FAIL: line addresses %h %h", captured_addr[0], captured_addr[1]);
            errors = errors + 1;
        end
        if (captured_len[0] !== 32'd3 || captured_len[1] !== 32'd3) begin
            $display("FAIL: expected three 256-bit beats per line");
            errors = errors + 1;
        end
        if (captured_data[0][31:0] !== 32'h66_11_22_33 ||
            captured_data[0][63:32] !== 32'h88_99_44_55 ||
            captured_data[0][95:64] !== 32'hAA_BB_CC_77) begin
            $display("FAIL: line 0 RGB888 packing mismatch: %h", captured_data[0][95:0]);
            errors = errors + 1;
        end
        if (captured_data[3][31:0] !== 32'h02_DE_AD_01 ||
            captured_data[3][63:32] !== 32'hFE_03_BE_EF ||
            captured_data[3][95:64] !== 32'hBA_BE_04_CA) begin
            $display("FAIL: line 1 RGB888 packing mismatch: %h", captured_data[3][95:0]);
            errors = errors + 1;
        end
        if (captured_data[1] !== 256'd0 || captured_data[2] !== 256'd0 ||
            captured_data[4] !== 256'd0 || captured_data[5] !== 256'd0) begin
            $display("FAIL: later DDR beats must contain the zero-filled remainder of each line");
            $display("DEBUG: beats 1=%h 2=%h 4=%h 5=%h",
                     captured_data[1], captured_data[2],
                     captured_data[4], captured_data[5]);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: algorithm_frame_writer errors=%0d", errors);

        $display("TEST_PASS: algorithm_frame_writer");
        $finish;
    end
endmodule
