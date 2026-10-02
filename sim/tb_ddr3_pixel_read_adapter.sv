`timescale 1ns/1ps

// A returned DDR beat begins at rd_cmd_addr * 4 bytes.  This test catches
// incorrect RGB byte ordering, byte-offset calculation, and rsp backpressure.
module tb_ddr3_pixel_read_adapter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg mem_req_valid = 1'b0;
    wire mem_req_ready;
    reg [31:0] mem_req_addr = 32'd0;
    reg [27:0] frame_base_addr = 28'd0;
    wire mem_rsp_valid;
    reg mem_rsp_ready = 1'b0;
    wire [23:0] mem_rsp_data;

    wire rd_cmd_en;
    wire [27:0] rd_cmd_addr;
    wire [31:0] rd_cmd_len;
    reg rd_cmd_ready = 1'b1;
    reg rd_cmd_done = 1'b0;
    reg [255:0] rd_data = 256'd0;
    reg rd_data_valid = 1'b0;
    wire rd_data_ready;

    reg [7:0] memory_bytes [0:127];
    integer index;
    integer errors = 0;
    integer pending_base = 0;
    integer pending_delay = -1;

    always #5 clk = ~clk;

    ddr3_pixel_read_adapter dut (
        .clk(clk),
        .rst_n(rst_n),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),
        .frame_base_addr(frame_base_addr),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_ready(mem_rsp_ready),
        .mem_rsp_data(mem_rsp_data),
        .rd_cmd_en(rd_cmd_en),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_done(rd_cmd_done),
        .rd_data(rd_data),
        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready)
    );

    function automatic [255:0] make_beat(input integer base_byte);
        integer byte_index;
        begin
            make_beat = 256'd0;
            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
                make_beat[byte_index*8 +: 8] = memory_bytes[base_byte + byte_index];
            end
        end
    endfunction

    always @(posedge clk) begin
        rd_cmd_done <= 1'b0;
        rd_data_valid <= 1'b0;

        if (rd_cmd_en && rd_cmd_ready) begin
            if (rd_cmd_len !== 32'd1) begin
                $display("FAIL: expected one DDR beat, got length %0d", rd_cmd_len);
                errors = errors + 1;
            end
            pending_base <= rd_cmd_addr * 4;
            pending_delay <= 2;
            rd_cmd_done <= 1'b1;
        end else if (pending_delay >= 0) begin
            if (pending_delay == 0) begin
                if (!rd_data_ready) begin
                    $display("FAIL: adapter was not ready for DDR read data");
                    errors = errors + 1;
                end
                rd_data <= make_beat(pending_base);
                rd_data_valid <= 1'b1;
                pending_delay <= -1;
            end else begin
                pending_delay <= pending_delay - 1;
            end
        end
    end

    task automatic request_pixel(input [31:0] pixel_index, input [23:0] expected_pixel,
                                 input integer stall_response);
        integer timeout;
        begin
            while (!mem_req_ready) @(posedge clk);
            mem_req_addr <= pixel_index;
            mem_req_valid <= 1'b1;
            @(posedge clk);
            while (!mem_req_ready) @(posedge clk);
            mem_req_valid <= 1'b0;

            for (timeout = 0; timeout < 100 && !mem_rsp_valid; timeout = timeout + 1)
                @(posedge clk);
            if (!mem_rsp_valid) begin
                $display("FAIL: timeout waiting for response of pixel %0d", pixel_index);
                errors = errors + 1;
            end else begin
                if (mem_rsp_data !== expected_pixel) begin
                    $display("FAIL: pixel %0d expected %h got %h", pixel_index,
                             expected_pixel, mem_rsp_data);
                    errors = errors + 1;
                end
                repeat (stall_response) begin
                    if (!mem_rsp_valid) begin
                        $display("FAIL: response was dropped during backpressure");
                        errors = errors + 1;
                    end
                    @(posedge clk);
                end
                mem_rsp_ready <= 1'b1;
                @(posedge clk);
                mem_rsp_ready <= 1'b0;
            end
        end
    endtask

    initial begin
        for (index = 0; index < 128; index = index + 1)
            memory_bytes[index] = 8'h00;

        // Packed little-endian bytes: each expected RGB word remains {R,G,B}.
        memory_bytes[0]  = 8'h33; memory_bytes[1]  = 8'h22; memory_bytes[2]  = 8'h11;
        memory_bytes[3]  = 8'h66; memory_bytes[4]  = 8'h55; memory_bytes[5]  = 8'h44;
        memory_bytes[6]  = 8'hCC; memory_bytes[7]  = 8'hBB; memory_bytes[8]  = 8'hAA;
        memory_bytes[9]  = 8'hEF; memory_bytes[10] = 8'hBE; memory_bytes[11] = 8'hAD;
        memory_bytes[16] = 8'hBE; memory_bytes[17] = 8'hFE; memory_bytes[18] = 8'hCA;

        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        request_pixel(32'd0, 24'h11_22_33, 0);
        request_pixel(32'd1, 24'h44_55_66, 2);
        request_pixel(32'd2, 24'hAA_BB_CC, 0);
        request_pixel(32'd3, 24'hAD_BE_EF, 0);
        frame_base_addr <= 28'd4;
        request_pixel(32'd0, 24'hCA_FE_BE, 0);

        if (errors != 0)
            $fatal(1, "TEST_FAIL: ddr3_pixel_read_adapter errors=%0d", errors);

        $display("TEST_PASS: ddr3_pixel_read_adapter");
        $finish;
    end
endmodule
