`timescale 1ns/1ps
// Self-check for sin_amp_offset + uart_commend AMPL/OFFST parsing.
// Run: sim\run_tb_amp_offset.bat
module tb_amp_offset;
    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;

    integer errors = 0;

    // ---------------- sin_amp_offset ----------------
    reg  signed [9:0]  sin_in;
    reg         [6:0]  amp;
    reg  signed [10:0] off;
    wire        [9:0]  code;
    wire        [9:0]  code_inv;

    sin_amp_offset #(.INVERT(0)) dut_a (.clk(clk), .rst_n(rst_n),
        .signed_in(sin_in), .amp_pct(amp), .offset(off), .unsigned_out(code));
    sin_amp_offset #(.INVERT(1)) dut_b (.clk(clk), .rst_n(rst_n),
        .signed_in(sin_in), .amp_pct(amp), .offset(off), .unsigned_out(code_inv));

    function integer expect_code;
        input integer s, a, o;
        integer sc, lv;
        begin
            // round-half-up of s*a/100, same as hardware (floor((x*2+1)/2))
            sc = (s * a * 5243 + 262144);
            if (sc >= 0) sc = sc / 524288;
            else         sc = -((-sc + 524287) / 524288);
            lv = 512 + sc + o;
            if (lv < 0) lv = 0;
            if (lv > 1023) lv = 1023;
            expect_code = lv;
        end
    endfunction

    task check_amp;
        input integer s, a, o;
        integer e, ideal, got;
        begin
            sin_in = s; amp = a; off = o;
            repeat (6) @(posedge clk);
            e = expect_code(s, a, o);
            if (code !== e[9:0] || code_inv !== (10'd1023 - e[9:0])) begin
                $display("FAIL amp: s=%0d a=%0d o=%0d got=%0d inv=%0d exp=%0d", s, a, o, code, code_inv, e);
                errors = errors + 1;
            end
            ideal = 512 + (s * a) / 100 + o;
            got   = code;
            if (ideal >= 1 && ideal <= 1022 && (got - ideal > 1 || ideal - got > 1)) begin
                $display("FAIL ideal: s=%0d a=%0d o=%0d got=%0d ideal=%0d", s, a, o, code, ideal);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- uart_commend ----------------
    reg  [7:0] rx_byte = 0;
    reg        rx_done = 0;
    wire       send_en;
    wire [7:0] send_data;
    wire [31:0] amp0, off0, amp1, off1;

    uart_commend dut_c (
        .clk(clk), .rst_n(rst_n),
        .rec_data(rx_byte), .rec_done(rx_done),
        .tx_done(send_en), .tx_busy(1'b0),
        .sine_freq(), .sine_phase(), .trigger_freq(), .duty_factor(),
        .amplitude_ctrl(amp0), .offset_value(off0),
        .t_light_value(), .d_light_value(),
        .sine_freq_light(), .sine_phase_light(),
        .amplitude_ctrl_light(amp1), .offset_value_light(off1),
        .update_flag_sine(), .update_flag_phase(), .update_flag_trigger(),
        .update_flag_duty(), .update_flag_ampl(), .update_flag_offset(),
        .update_flag_t_light(), .update_flag_d_light(), .update_flag_sine_light(),
        .update_flag_phase_light(), .update_flag_ampl_light(), .update_flag_offset_light(),
        .send_en(send_en), .send_data(send_data)
    );

    reg [8*20-1:0] reply;
    reg send_en_d = 0;
    always @(posedge clk) begin
        send_en_d <= send_en;
        if (send_en && !send_en_d) reply <= {reply[8*19-1:0], send_data};
    end

    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk); rx_byte <= b; rx_done <= 1'b1;
            @(posedge clk); rx_done <= 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    task send_str;
        input [8*24-1:0] s;
        integer i;
        begin
            reply = 0;
            for (i = 23; i >= 0; i = i - 1)
                if (s[i*8 +: 8] != 8'd0) send_byte(s[i*8 +: 8]);
            send_byte("\r");
            send_byte("\n");
            repeat (200) @(posedge clk);
        end
    endtask

    task expect_ok;
        input ok;
        input [8*24-1:0] what;
        begin
            if (ok && reply[8*2-1:0] == "\r\n" && reply[8*3-1:8*2] == "!" && reply[8*4-1:8*3] == "s") ;
            else if (!ok && reply[8*4-1:8*3] == "r") ;
            else begin
                $display("FAIL reply for %0s: ok=%0d reply=%0s", what, ok, reply);
                errors = errors + 1;
            end
        end
    endtask

    integer s, a, o;
    initial begin
        sin_in = 0; amp = 0; off = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;

        // arithmetic sweep
        for (a = 0; a <= 100; a = a + 25)
            for (o = -1023; o <= 1023; o = o + 341)
                for (s = -512; s <= 511; s = s + 73)
                    check_amp(s, a, o);
        check_amp(-512, 100, 0);
        check_amp( 511, 100, 0);
        check_amp(   0,   0,  300);
        check_amp(   0,   0, -300);
        check_amp( 511, 100,  200);   // clip top
        check_amp(-512, 100, -200);   // clip bottom

        // wait boot banner
        repeat (200) @(posedge clk);

        send_str("OFFST:-300");     expect_ok(1, "OFFST:-300");
        if ($signed(off0) !== -300) begin $display("FAIL off0=%0d", $signed(off0)); errors = errors + 1; end
        send_str("OFFST:250");      expect_ok(1, "OFFST:250");
        if ($signed(off0) !== 250)  begin $display("FAIL off0=%0d", $signed(off0)); errors = errors + 1; end
        send_str("OFFSET_LIGHT:-1023"); expect_ok(1, "OFFSET_LIGHT:-1023");
        if ($signed(off1) !== -1023) begin $display("FAIL off1=%0d", $signed(off1)); errors = errors + 1; end
        send_str("OFFST:-1024");    expect_ok(0, "OFFST:-1024");
        if ($signed(off0) !== 250)  begin $display("FAIL off0 changed %0d", $signed(off0)); errors = errors + 1; end
        send_str("AMPL:0");         expect_ok(1, "AMPL:0");
        if (amp0 !== 0) begin $display("FAIL amp0=%0d", amp0); errors = errors + 1; end
        send_str("AMPL:100");       expect_ok(1, "AMPL:100");
        send_str("AMPL:101");       expect_ok(0, "AMPL:101");
        send_str("AMPL:-5");        expect_ok(0, "AMPL:-5");
        if (amp0 !== 100) begin $display("FAIL amp0=%0d", amp0); errors = errors + 1; end
        send_str("OFFST:");         expect_ok(0, "OFFST:");
        send_str("OFFST:-");        expect_ok(0, "OFFST:-");
        send_str("OFFST:1x2");      expect_ok(0, "OFFST:1x2");
        send_str("AMPL_LIGHT:55");  expect_ok(1, "AMPL_LIGHT:55");
        if (amp1 !== 55) begin $display("FAIL amp1=%0d", amp1); errors = errors + 1; end

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d", errors);
        $finish;
    end
endmodule
