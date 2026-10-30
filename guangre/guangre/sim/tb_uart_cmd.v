`timescale 1ns/1ps
module tb_uart_cmd;
    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;
    reg  [7:0] rx_byte = 0;
    reg        rx_done = 0;
    wire       send_en;
    wire [7:0] send_data;
    wire       tx_done = send_en;
    integer    errors = 0;
    uart_commend dut (
        .clk(clk), .rst_n(rst_n),
        .rec_data(rx_byte), .rec_done(rx_done),
        .tx_done(tx_done), .tx_busy(1'b0),
        .sine_freq(), .sine_phase(), .trigger_freq(), .duty_factor(),
        .amplitude_ctrl(), .offset_value(),
        .t_light_value(), .d_light_value(),
        .sine_freq_light(), .sine_phase_light(),
        .amplitude_ctrl_light(), .offset_value_light(),
        .update_flag_sine(), .update_flag_phase(), .update_flag_trigger(),
        .update_flag_duty(), .update_flag_ampl(), .update_flag_offset(),
        .update_flag_t_light(), .update_flag_d_light(), .update_flag_sine_light(),
        .update_flag_phase_light(), .update_flag_ampl_light(), .update_flag_offset_light(),
        .send_en(send_en), .send_data(send_data)
    );
    reg [8*32-1:0] reply;
    reg send_en_d = 0;
    always @(posedge clk) begin
        send_en_d <= send_en;
        if (send_en && !send_en_d) reply <= {reply[8*31-1:0], send_data};
    end
    task send_byte; input [7:0] b; begin
        @(posedge clk); rx_byte <= b; rx_done <= 1'b1;
        @(posedge clk); rx_done <= 1'b0; repeat (2) @(posedge clk);
    end endtask
    task send_cmd; input [8*40-1:0] s; input [1:0] eol; integer i; begin
        reply = 0;
        for (i = 39; i >= 0; i = i - 1)
            if (s[i*8 +: 8] != 8'd0) send_byte(s[i*8 +: 8]);
        if (eol == 2) begin send_byte(8'h0D); send_byte(8'h0A); end
        else if (eol == 1) send_byte(8'h0A);
        else send_byte(8'h0D);
        repeat (400) @(posedge clk);
    end endtask
    function automatic integer is_success; input [8*32-1:0] r; begin
        is_success = (r[15:0] == 16'h0A0D) && (r[23:16] == "!");
    end endfunction
    function automatic integer is_error; input [8*32-1:0] r; begin
        is_error = (r[15:0] == 16'h0A0D) && (r[47:16] == "rror");
    end endfunction
    task expect_ok; input [8*40-1:0] name; begin
        if (!is_success(reply)) begin $display("FAIL expect Success for %0s, reply=%0s", name, reply); errors = errors + 1; end
    end endtask
    task expect_err; input [8*40-1:0] name; begin
        if (!is_error(reply)) begin $display("FAIL expect Error for %0s, reply=%0s", name, reply); errors = errors + 1; end
    end endtask
    initial begin
        repeat (4) @(posedge clk); rst_n = 1; repeat (200) @(posedge clk);
        send_cmd("AMPL:10", 0);    expect_ok("AMPL:10 CR");
        send_cmd("AMPL:10", 2);    expect_ok("AMPL:10 CRLF");
        send_cmd("TRIG:80000", 2); expect_ok("TRIG CRLF");
        send_cmd("DUTY:50000", 1); expect_ok("DUTY LF");
        send_cmd("OFFST:0", 2);    expect_ok("OFFST:0");
        send_cmd("OFFST:-200", 2); expect_ok("OFFST:-200");
        send_cmd("OFFSET:100", 2); expect_ok("OFFSET alias");
        send_cmd("SINE:10000", 2); expect_ok("SINE");
        send_cmd("AMPL:0", 2);     expect_ok("AMPL:0");
        send_cmd("AMPL:101", 2);   expect_err("AMPL:101");
        send_cmd("AMPL:-1", 2);    expect_err("AMPL:-1");
        send_cmd("OFFST:-1024", 2);expect_err("OFFST:-1024");
        send_cmd("ampl:10", 2);    expect_err("lowercase");
        send_cmd("AMPL:", 2);      expect_err("empty");
        send_cmd("FOO:1", 2);      expect_err("unknown");
        reply = 0; send_byte(8'h0A); send_byte(8'h0D); repeat (100) @(posedge clk);
        if (reply != 0) begin $display("FAIL orphan EOL created reply=%0s", reply); errors = errors + 1; end
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED: %0d", errors);
        $finish;
    end
endmodule
