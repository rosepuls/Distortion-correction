`timescale 1ns / 1ps

module uart_homography_control_tb;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg rx = 1'b1;
    reg frame_start = 1'b0;
    wire tx;
    wire cfg_valid;
    wire cfg_pose_valid;
    wire [287:0] cfg_words;
    wire [15:0] cfg_version;
    wire packet_event;
    wire [7:0] packet_status;
    wire [287:0] active_words;
    wire [15:0] active_version;
    wire active_pose_valid;
    wire active_updated;
    wire pending_valid;
    wire [15:0] pending_version;
    reg [7:0] request [0:64];
    reg [7:0] response [0:64];
    reg [287:0] words;
    reg [15:0] crc;
    integer i;

    always #5 clk = ~clk;

    stage8_uart_homography_control #(.CLK_HZ(1000000), .BAUD_RATE(100000)) dut (
        .clk(clk), .rstn(rstn), .uart_rx(rx), .uart_tx(tx),
        .cfg_valid(cfg_valid), .cfg_pose_valid(cfg_pose_valid),
        .cfg_words(cfg_words), .cfg_version(cfg_version),
        .packet_event(packet_event), .packet_status(packet_status)
    );

    homography_parameter_bank parameter_bank (
        .clk(clk), .rstn(rstn), .cfg_valid(cfg_valid),
        .cfg_pose_valid(cfg_pose_valid), .cfg_words(cfg_words),
        .cfg_version(cfg_version), .frame_start(frame_start),
        .active_words(active_words), .active_version(active_version),
        .active_pose_valid(active_pose_valid), .active_updated(active_updated),
        .pending_valid(pending_valid), .pending_version(pending_version)
    );

    function automatic [15:0] crc16_byte(input [15:0] crc_in, input [7:0] data);
        reg [15:0] c;
        begin
            c = crc_in ^ {data, 8'h00};
            for (integer b = 0; b < 8; b = b + 1)
                c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            crc16_byte = c;
        end
    endfunction

    task automatic make_request(input [15:0] seqno, input reg bad_crc);
        begin
            request[0]=8'hA5; request[1]=8'h5A; request[2]=8'h02; request[3]=8'h01;
            request[4]=seqno[7:0]; request[5]=seqno[15:8]; request[6]=8'h01;
            for (integer j=0;j<36;j=j+1)
                request[7+j]=words[(j/4)*32+(j%4)*8 +: 8];
            for (integer j=43;j<63;j=j+1) request[j]=8'h00;
            crc=16'hFFFF;
            for (integer j=2;j<=62;j=j+1) crc=crc16_byte(crc,request[j]);
            if (bad_crc) crc=crc ^ 16'h0001;
            request[63]=crc[15:8]; request[64]=crc[7:0];
        end
    endtask

    task automatic send_byte(input [7:0] data);
        begin
            rx=1'b0; #100;
            for (integer j=0;j<8;j=j+1) begin rx=data[j]; #100; end
            rx=1'b1; #100;
        end
    endtask

    task automatic receive_byte(output [7:0] data);
        begin
            @(negedge tx); #150;
            for (integer j=0;j<8;j=j+1) begin data[j]=tx; #100; end
            if (tx !== 1'b1) $fatal(1,"UART response stop bit is low");
            #50;
        end
    endtask

    task automatic transact(input [15:0] seqno, input reg bad_crc, input [7:0] expected_status);
        begin
            make_request(seqno,bad_crc);
            for (integer j=0;j<65;j=j+1) send_byte(request[j]);
            for (integer j=0;j<65;j=j+1) receive_byte(response[j]);
            if ({response[0],response[1],response[2],response[3]} !== 32'hA55A0281 ||
                {response[5],response[4]} !== seqno || response[6] !== expected_status)
                $fatal(1,"response header, sequence, or status mismatch");
        end
    endtask

    initial begin
        words=288'd0;
        words[0*32 +: 32]=32'h00010000;
        words[2*32 +: 32]=32'h00100000; // +16 source pixels in h02
        words[4*32 +: 32]=32'h00010000;
        words[8*32 +: 32]=32'h40000000;
        repeat (5) @(posedge clk);
        rstn=1'b1;
        repeat (3) @(posedge clk);

        transact(16'h1234,1'b0,8'h00);
        for (i=0;i<36;i=i+1)
            if (response[7+i] !== request[7+i]) $fatal(1,"ACK payload mismatch");
        crc=16'hFFFF;
        for (i=2;i<=62;i=i+1) crc=crc16_byte(crc,response[i]);
        if ({response[63],response[64]} !== crc) $fatal(1,"ACK CRC mismatch");
        for (i=43;i<63;i=i+1)
            if (response[i] !== 8'h00) $fatal(1,"ACK extension mismatch");
        if (active_words[2*32 +: 32] !== 32'd0 || active_version !== 16'd0 || !pending_valid)
            $fatal(1,"UART packet changed active parameters before frame boundary");
        @(negedge clk); frame_start=1'b1;
        @(negedge clk); frame_start=1'b0;
        @(posedge clk);
        if (!active_pose_valid || active_version !== 16'h1234 || active_words !== words)
            $fatal(1,"accepted UART homography did not become active at frame boundary");

        transact(16'h1235,1'b1,8'h04);
        if (active_version !== 16'h1234 || active_words !== words || pending_valid)
            $fatal(1,"bad CRC packet changed active or pending homography");
        $display("PASS: UART homography ACK/NACK, active coefficients, and frame-boundary update");
        $finish;
    end

    initial begin #100000000; $fatal(1,"UART homography integration test timed out"); end
endmodule
