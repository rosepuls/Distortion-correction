`timescale 1ns/1ps

module tb_video_mode_720p60;
    localparam integer H_TOTAL = 1650;
    localparam integer H_SYNC = 40;
    localparam integer H_ACTIVE_START = 260;
    localparam integer H_ACTIVE = 1280;
    localparam integer V_TOTAL = 750;
    localparam integer V_SYNC = 5;
    localparam integer V_ACTIVE_START = 25;
    localparam integer V_ACTIVE = 720;
    localparam integer FRAME_CLOCKS = H_TOTAL * V_TOTAL;
    localparam integer ACTIVE_CLOCKS = H_ACTIVE * V_ACTIVE;
    localparam integer FIRST_REQUEST_CLOCK = V_ACTIVE_START * H_TOTAL + H_ACTIVE_START - 2;
    localparam integer FIRST_ACTIVE_CLOCK = V_ACTIVE_START * H_TOTAL + H_ACTIVE_START;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire hs;
    wire vs;
    wire de;
    wire de_request;
    wire [11:0] x;
    wire [11:0] y;
    wire frame_start;

    integer errors = 0;
    integer sample_index;
    integer hs_high_count;
    integer vs_high_count;
    integer de_high_count;
    integer request_high_count;
    integer frame_start_count;
    integer first_request_clock;
    integer first_active_clock;

    always #1 clk = ~clk;

    video_mode_720p60 dut (
        .clk(clk), .rst_n(rst_n),
        .hs(hs), .vs(vs), .de(de), .de_request(de_request),
        .x(x), .y(y), .frame_start(frame_start)
    );

    task automatic check_cond(input condition, input [8*120-1:0] message);
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic measure_one_frame;
        begin
            hs_high_count = 0;
            vs_high_count = 0;
            de_high_count = 0;
            request_high_count = 0;
            frame_start_count = 0;
            first_request_clock = -1;
            first_active_clock = -1;

            for (sample_index = 0; sample_index < FRAME_CLOCKS; sample_index = sample_index + 1) begin
                if (hs)
                    hs_high_count = hs_high_count + 1;
                if (vs)
                    vs_high_count = vs_high_count + 1;
                if (de)
                    de_high_count = de_high_count + 1;
                if (de_request)
                    request_high_count = request_high_count + 1;
                if (de_request && first_request_clock < 0)
                    first_request_clock = sample_index;
                if (de && first_active_clock < 0)
                    first_active_clock = sample_index;
                if (frame_start) begin
                    frame_start_count = frame_start_count + 1;
                    check_cond(sample_index == 0,
                               "frame_start must occur at the first clock of the raster");
                    check_cond(hs && vs && !de,
                               "frame_start must align with positive HS/VS blanking origin");
                end
                if (de) begin
                    check_cond(x < H_ACTIVE && y < V_ACTIVE,
                               "active coordinates must remain inside 1280x720");
                end else begin
                    check_cond(x == 0 && y == 0,
                               "blanking coordinates must be zero");
                end
                @(negedge clk);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Ignore the partial raster after reset, then observe exactly one full frame.
        while (!frame_start)
            @(negedge clk);
        measure_one_frame();

        check_cond(frame_start,
                   "a full 1650x750 frame must end at the next frame origin");
        check_cond(hs_high_count == H_SYNC * V_TOTAL,
                   "HS must be high for 40 clocks in each of 750 lines");
        check_cond(vs_high_count == H_TOTAL * V_SYNC,
                   "VS must be high for exactly five complete lines");
        check_cond(de_high_count == ACTIVE_CLOCKS,
                   "DE count must equal 1280x720 active pixels");
        check_cond(request_high_count == ACTIVE_CLOCKS,
                   "DE request count must equal the active-pixel count");
        check_cond(first_request_clock == FIRST_REQUEST_CLOCK,
                   "DE request must begin two clocks before active video");
        check_cond(first_active_clock == FIRST_ACTIVE_CLOCK,
                   "DE must begin at 260 clocks into active line 25");
        check_cond(first_active_clock - first_request_clock == 2,
                   "DE request lead must be exactly two clocks");
        check_cond(frame_start_count == 1,
                   "frame_start must pulse exactly once per frame");

        if (errors != 0)
            $fatal(1, "TEST_FAIL: video_mode_720p60 errors=%0d", errors);
        $display("TEST_PASS: video_mode_720p60");
        $finish;
    end
endmodule
