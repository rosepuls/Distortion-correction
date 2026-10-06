`timescale 1ns/1ps

module tb_realtime_frame_scheduler;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg input_frame_done = 1'b0;
    reg input_frame_bank = 1'b0;
    reg algo_frame_done = 1'b0;
    reg output_frame_done = 1'b0;
    reg display_bank_core = 1'b0;

    wire process_start;
    wire process_input_bank;
    wire process_output_bank;
    wire process_active;
    wire output_ready_toggle;
    wire output_ready_bank;
    wire input_overrun;

    realtime_frame_scheduler dut (
        .clk(clk), .rst_n(rst_n),
        .input_frame_done(input_frame_done), .input_frame_bank(input_frame_bank),
        .algo_frame_done(algo_frame_done), .output_frame_done(output_frame_done),
        .display_bank_core(display_bank_core),
        .process_start(process_start), .process_input_bank(process_input_bank),
        .process_output_bank(process_output_bank), .process_active(process_active),
        .output_ready_toggle(output_ready_toggle), .output_ready_bank(output_ready_bank),
        .input_overrun(input_overrun)
    );

    always #5 clk = ~clk;

    task automatic assert_input_done(input bit bank);
        begin
            @(negedge clk);
            input_frame_bank = bank;
            input_frame_done = 1'b1;
        end
    endtask

    task automatic clear_input_done;
        begin
            @(negedge clk);
            input_frame_done = 1'b0;
        end
    endtask

    task automatic assert_completion;
        begin
            @(negedge clk);
            algo_frame_done = 1'b1;
            output_frame_done = 1'b1;
        end
    endtask

    task automatic clear_completion;
        begin
            @(negedge clk);
            algo_frame_done = 1'b0;
            output_frame_done = 1'b0;
        end
    endtask

    task automatic expect_start(input bit expected_input, input bit expected_output);
        begin
            @(posedge clk);
            #1;
            if (!process_start || !process_active ||
                process_input_bank !== expected_input ||
                process_output_bank !== expected_output) begin
                $display("FAIL: expected process start in=%0d out=%0d, got start=%0d active=%0d in=%0d out=%0d",
                         expected_input, expected_output, process_start, process_active,
                         process_input_bank, process_output_bank);
                $fatal;
            end
        end
    endtask

    task automatic expect_output_ready(input bit expected_bank, input bit previous_toggle);
        begin
            @(posedge clk);
            #1;
            if (process_active || output_ready_bank !== expected_bank ||
                output_ready_toggle === previous_toggle) begin
                $display("FAIL: expected completed output bank=%0d toggle change, got active=%0d bank=%0d toggle=%0d",
                         expected_bank, process_active, output_ready_bank, output_ready_toggle);
                $fatal;
            end
        end
    endtask

    reg first_toggle;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // Frame 0 completes in input bank 0. With display bank 0 active, the
        // first corrected frame must use output bank 1.
        assert_input_done(1'b0);
        expect_start(1'b0, 1'b1);
        clear_input_done;
        first_toggle = output_ready_toggle;
        assert_completion;
        expect_output_ready(1'b1, first_toggle);
        clear_completion;

        // Video has atomically adopted bank 1. The next processed frame must
        // read the other input bank and write output bank 0.
        display_bank_core = 1'b1;
        assert_input_done(1'b1);
        expect_start(1'b1, 1'b0);
        clear_input_done;
        first_toggle = output_ready_toggle;
        assert_completion;
        expect_output_ready(1'b0, first_toggle);
        clear_completion;

        // A new completed input cannot overwrite the frame currently owned by
        // the algorithm. The scheduler must expose this condition.
        display_bank_core = 1'b0;
        assert_input_done(1'b0);
        expect_start(1'b0, 1'b1);
        clear_input_done;
        assert_input_done(1'b1);
        @(posedge clk);
        #1;
        if (!input_overrun || !process_active || process_input_bank !== 1'b0) begin
            $display("FAIL: busy input completion did not preserve ownership and raise overrun");
            $fatal;
        end

        $display("TEST_PASS: realtime_frame_scheduler");
        $finish;
    end
endmodule
