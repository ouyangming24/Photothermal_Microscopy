`timescale 1ns/1ps
// Self-check for clk_trig high_time (sequential /100000) using behavioral IP stubs.
// Run: sim\run_tb_clk_trig.bat
module div_gen_0 (
    input              aclk,
    input              s_axis_divisor_tvalid,
    input       [63:0] s_axis_divisor_tdata,
    input              s_axis_dividend_tvalid,
    input       [63:0] s_axis_dividend_tdata,
    output reg         m_axis_dout_tvalid = 0,
    output reg [127:0] m_axis_dout_tdata = 0
);
    always @(posedge aclk) begin
        m_axis_dout_tvalid <= 1'b1;
        m_axis_dout_tdata  <= {s_axis_dividend_tdata / s_axis_divisor_tdata,
                               s_axis_dividend_tdata % s_axis_divisor_tdata};
    end
endmodule

module mult_gen_0 (
    input             CLK,
    input      [31:0] A,
    input      [35:0] B,
    output reg [64:0] P = 0
);
    always @(posedge CLK) P <= A * B;
endmodule

module tb_clk_trig;
    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;

    reg  [31:0] freq = 0, duty = 0;
    reg         upd_f = 0, upd_d = 0;
    wire        clk_out;
    integer     errors = 0;

    clk_trig #(.CLK_FREQ(50_000_000)) dut (
        .clk_in(clk), .rst_n(rst_n),
        .trigger_freq(freq), .update_flag_trigger(upd_f),
        .duty_factor(duty), .update_flag_duty(upd_d),
        .clk_out(clk_out)
    );

    task set_fd;
        input [31:0] f, d;
        reg [63:0] period, exp_high;
        begin
            @(posedge clk); freq <= f; duty <= d; upd_f <= 1; upd_d <= 1;
            @(posedge clk); upd_f <= 0; upd_d <= 0;
            repeat (300) @(posedge clk);
            period   = (64'd50_000_000 * 1000) / f;
            if (period < 2) period = 2;
            exp_high = ((period > 64'hFFFF_FFFF ? 64'hFFFF_FFFF : period) * d) / 100_000;
            if (dut.period_time_reg !== period || dut.high_time_reg !== exp_high) begin
                $display("FAIL f=%0d d=%0d period=%0d/%0d high=%0d/%0d", f, d,
                         dut.period_time_reg, period, dut.high_time_reg, exp_high);
                errors = errors + 1;
            end
        end
    endtask

    integer hi_cnt, i;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (300) @(posedge clk);
        if (dut.high_time_reg !== 64'd312_500) begin
            $display("FAIL reset high=%0d", dut.high_time_reg); errors = errors + 1;
        end

        set_fd(80_000,      50_000);
        set_fd(80_000,      12_345);
        set_fd(1_000,       99_999);
        set_fd(1,           33_333);     // 0.001 Hz, period saturates mult A port
        set_fd(10_000_000,  25_000);     // 10 kHz
        set_fd(25_000_000_0 / 10, 50_000);
        set_fd(32'd4_000_000_000, 50_000);
        set_fd(80_000,      0);
        set_fd(80_000,      100_000);

        // measure duty: 1 MHz, 30% -> period 50, high 15
        set_fd(1_000_000_000, 30_000);
        hi_cnt = 0;
        for (i = 0; i < 5000; i = i + 1) begin
            @(posedge clk); if (clk_out) hi_cnt = hi_cnt + 1;
        end
        if (hi_cnt < 1490 || hi_cnt > 1510) begin
            $display("FAIL duty count=%0d expect ~1500", hi_cnt); errors = errors + 1;
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d", errors);
        $finish;
    end
endmodule
