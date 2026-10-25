`timescale 1ns / 1ps

module homography_parameter_bank_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg cfg_valid = 1'b0;
    reg cfg_pose_valid = 1'b0;
    reg [287:0] cfg_words = 288'd0;
    reg [15:0] cfg_version = 16'd0;
    reg frame_start = 1'b0;
    wire [287:0] active_words;
    wire [15:0] active_version;
    wire active_pose_valid, active_updated, pending_valid;
    wire [15:0] pending_version;

    localparam [287:0] IDENTITY = {
        32'h40000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00010000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00010000
    };
    localparam [287:0] COEFFICIENTS_A = {9{32'h01010101}};
    localparam [287:0] COEFFICIENTS_B = {9{32'h02020202}};
    localparam [287:0] COEFFICIENTS_C = {9{32'h03030303}};
    localparam [287:0] COEFFICIENTS_D = {9{32'h04040404}};

    homography_parameter_bank dut (
        .clk(clk), .rstn(rstn),
        .cfg_valid(cfg_valid), .cfg_pose_valid(cfg_pose_valid),
        .cfg_words(cfg_words), .cfg_version(cfg_version),
        .frame_start(frame_start),
        .active_words(active_words), .active_version(active_version),
        .active_pose_valid(active_pose_valid), .active_updated(active_updated),
        .pending_valid(pending_valid), .pending_version(pending_version)
    );

    task automatic tick;
        begin @(posedge clk); #1; end
    endtask

    task automatic load_pose(input [287:0] words, input [15:0] version, input pose_valid);
        begin
            @(negedge clk);
            cfg_valid = 1'b1;
            cfg_pose_valid = pose_valid;
            cfg_words = words;
            cfg_version = version;
            tick();
            @(negedge clk);
            cfg_valid = 1'b0;
        end
    endtask

    task automatic next_frame;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            tick();
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    initial begin
        repeat (2) tick();
        @(negedge clk);
        rstn = 1'b1;
        tick();
        if (active_words !== IDENTITY || active_version !== 0 ||
            active_pose_valid !== 0 || pending_valid !== 0)
            $fatal(1, "reset did not select invalid identity pose");

        load_pose(COEFFICIENTS_A, 16'd1, 1'b1);
        if (active_words !== IDENTITY || pending_valid !== 1 || pending_version !== 1)
            $fatal(1, "loading a packet changed the active frame");
        load_pose(COEFFICIENTS_B, 16'd2, 1'b1);
        if (active_words !== IDENTITY || pending_version !== 2)
            $fatal(1, "latest pending packet was not retained");
        next_frame();
        if (active_words !== COEFFICIENTS_B || active_version !== 2 ||
            active_pose_valid !== 1 || pending_valid !== 0 || active_updated !== 1)
            $fatal(1, "frame boundary did not atomically commit packet B");
        tick();
        if (active_updated !== 0)
            $fatal(1, "active_updated is not a one-cycle pulse");

        load_pose(COEFFICIENTS_C, 16'd3, 1'b1);
        @(negedge clk);
        frame_start = 1'b1;
        cfg_valid = 1'b1;
        cfg_pose_valid = 1'b1;
        cfg_words = COEFFICIENTS_D;
        cfg_version = 16'd4;
        tick();
        if (active_words !== COEFFICIENTS_C || active_version !== 3 ||
            pending_valid !== 1 || pending_version !== 4)
            $fatal(1, "coincident boundary and packet load ordering failed");
        @(negedge clk);
        frame_start = 1'b0;
        cfg_valid = 1'b0;
        next_frame();
        if (active_words !== COEFFICIENTS_D || active_version !== 4)
            $fatal(1, "coincident packet did not commit on the following frame");

        load_pose(COEFFICIENTS_A, 16'd5, 1'b0);
        next_frame();
        if (active_words !== IDENTITY || active_version !== 5 || active_pose_valid !== 0)
            $fatal(1, "invalid pose did not select identity on a frame boundary");
        next_frame();
        if (active_words !== IDENTITY || active_version !== 5 || pending_valid !== 0)
            $fatal(1, "frame without new packet changed active coefficients");

        $display("PASS: Stage 8 parameter bank atomic frame update and invalid-pose handling");
        $finish;
    end
endmodule
