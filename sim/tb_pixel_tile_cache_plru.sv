`timescale 1ns/1ps

module tb_pixel_tile_cache_plru;
    reg  [6:0] state;
    reg  [2:0] touch_way;
    wire [6:0] next_state;
    wire [2:0] victim_way;
    integer errors = 0;

    pixel_tile_cache_plru8 dut (
        .state(state),
        .touch_way(touch_way),
        .next_state(next_state),
        .victim_way(victim_way)
    );

    task automatic check(
        input [6:0] expected_state,
        input [2:0] expected_victim,
        input [127:0] name
    );
        begin
            #1;
            if (next_state !== expected_state) begin
                $display("FAIL: %0s next_state=%b expected=%b",
                         name, next_state, expected_state);
                errors = errors + 1;
            end
            if (victim_way !== expected_victim) begin
                $display("FAIL: %0s victim=%0d expected=%0d",
                         name, victim_way, expected_victim);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // state[0] is the root direction, followed by the two second-level
        // nodes and four leaf nodes.  Zero selects the left/older subtree.
        state = 7'b0000000;
        touch_way = 3'd0;
        check(7'b0001011, 3'd0, "touch_way_0");

        state = 7'b0000000;
        touch_way = 3'd7;
        check(7'b0000000, 3'd0, "touch_way_7");

        state = 7'b0001011;
        touch_way = 3'd4;
        check(7'b0101110, 3'd4, "touch_way_4");

        if (errors != 0)
            $fatal(1, "TEST_FAIL: pixel_tile_cache_plru errors=%0d", errors);
        $display("TEST_PASS: pixel_tile_cache_plru");
        $finish;
    end
endmodule
