`timescale 1ns/1ps

module tb_board_video_control;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ddr_init_done = 1'b0;
    reg hdmi_init_done = 1'b0;
    reg input_frame_complete = 1'b0;
    reg algo_frame_done = 1'b0;
    reg output_frame_complete = 1'b0;
    wire capture_enable;
    wire process_enable;
    wire display_enable;
    wire algo_frame_start;

    integer errors = 0;
    integer start_count = 0;

    always #5 clk = ~clk;

    board_video_control dut (
        .clk(clk),
        .rst_n(rst_n),
        .ddr_init_done(ddr_init_done),
        .hdmi_init_done(hdmi_init_done),
        .input_frame_complete(input_frame_complete),
        .algo_frame_done(algo_frame_done),
        .output_frame_complete(output_frame_complete),
        .capture_enable(capture_enable),
        .process_enable(process_enable),
        .display_enable(display_enable),
        .algo_frame_start(algo_frame_start)
    );

    always @(posedge clk) begin
        if (algo_frame_start)
            start_count = start_count + 1;
    end

    task automatic pulse_input_complete;
        begin
            input_frame_complete <= 1'b1;
            @(posedge clk);
            input_frame_complete <= 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        pulse_input_complete();
        if (capture_enable || process_enable || display_enable || start_count != 0) begin
            $display("FAIL: activity before DDR/HDMI initialization");
            errors = errors + 1;
        end

        ddr_init_done <= 1'b1;
        repeat (2) @(posedge clk);
        if (capture_enable) begin
            $display("FAIL: capture began before HDMI initialization");
            errors = errors + 1;
        end

        hdmi_init_done <= 1'b1;
        repeat (2) @(posedge clk);
        if (!capture_enable || process_enable || display_enable) begin
            $display("FAIL: controller did not enter capture phase");
            errors = errors + 1;
        end

        pulse_input_complete();
        repeat (2) @(posedge clk);
        if (capture_enable || !process_enable || display_enable || start_count != 1) begin
            $display("FAIL: input completion did not start exactly one processing frame");
            errors = errors + 1;
        end

        pulse_input_complete();
        repeat (2) @(posedge clk);
        if (start_count != 1) begin
            $display("FAIL: second input completion retriggered processing");
            errors = errors + 1;
        end

        output_frame_complete <= 1'b1;
        @(posedge clk);
        output_frame_complete <= 1'b0;
        repeat (2) @(posedge clk);
        if (display_enable) begin
            $display("FAIL: display began before algorithm completion");
            errors = errors + 1;
        end

        algo_frame_done <= 1'b1;
        @(posedge clk);
        algo_frame_done <= 1'b0;
        repeat (2) @(posedge clk);
        if (!display_enable || capture_enable || process_enable) begin
            $display("FAIL: controller did not enter stable display phase");
            errors = errors + 1;
        end

        pulse_input_complete();
        repeat (3) @(posedge clk);
        if (!display_enable || start_count != 1) begin
            $display("FAIL: display phase was not persistent");
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: board_video_control errors=%0d", errors);

        $display("TEST_PASS: board_video_control");
        $finish;
    end
endmodule
