// =============================================================================
// clk_trig.v
// 功能：根据 UART 下发的频率/占空比生成触发方波 clk_out
//
// 参数约定（与 uart_commend 一致）：
//   trigger_freq : 频率 ×1000（单位 mHz）。例：80000 → 80 Hz
//   duty_factor  : 0~100000 → 0%~100.000%。例：50000 → 50%
//
// 计算：
//   period_time = (CLK_FREQ * 1000) / trigger_freq
//   high_time   = period_time * duty_factor / 100000
//   clk_out = 1 when period_cnt < high_time
//
// 保护：
//   - trigger_freq==0 时保持上次有效频率，避免除零
//   - period 至少为 2，避免 period-1 下溢
//   - 乘法器 A 口按 IP 配置取低 32 位（限制最低频率约 >=0.012Hz）
//
// high_time 的 /100000 用 64 拍移位相减除法器循环计算（每 65 个 clk 刷新一次，
// 约 1.3us），不要改回单周期 "/"：64 位常数除法组合逻辑约 20ns，50MHz 下时序违例
// =============================================================================
module clk_trig (
    input        clk_in,
    input        rst_n,
    input [31:0] trigger_freq,
    input        update_flag_trigger,
    input [31:0] duty_factor,
    input        update_flag_duty,
    output reg   clk_out
);

    parameter CLK_FREQ  = 50_000_000;
    parameter INIT_FREQ = 80_000;     // 80 Hz
    parameter INIT_DUTY = 50_000;     // 50%

    reg [31:0] current_freq;
    reg [31:0] current_duty;
    reg [63:0] period_time_reg;
    reg [63:0] high_time_reg;
    reg [63:0] period_cnt;

    wire        div_valid;
    wire [127:0] div_result;
    reg  [63:0] divisor_reg;
    reg  [63:0] dividend_reg;

    wire [64:0] mult_result;
    reg  [31:0] mult_operand;  // 与 mult_gen_0 PortA=32 对齐

    localparam [17:0] DUTY_FULL = 18'd100_000;
    // 必须 64 位：CLK_FREQ*1000 = 5e10，按 32 位整数算会溢出成负数
    localparam [63:0] CLK_X1000 = CLK_FREQ * 64'd1000;
    localparam [63:0] INIT_PER  = CLK_X1000 / INIT_FREQ;

    // 移位相减除法器：hd_q 先装被除数，逐位移出并移入商
    reg  [63:0] hd_q;
    reg  [17:0] hd_r;          // 余数 < 100000 < 2^17，移位后 < 2^18
    reg  [5:0]  hd_cnt;
    reg         hd_busy;
    wire [17:0] hd_r_sh = {hd_r[16:0], hd_q[63]};
    wire        hd_ge   = (hd_r_sh >= DUTY_FULL);

    // period = (CLK_FREQ*1000) / freq
    div_gen_0 u_div (
        .aclk                   (clk_in),
        .s_axis_divisor_tvalid  (1'b1),
        .s_axis_divisor_tdata   (divisor_reg),
        .s_axis_dividend_tvalid (1'b1),
        .s_axis_dividend_tdata  (dividend_reg),
        .m_axis_dout_tvalid     (div_valid),
        .m_axis_dout_tdata      (div_result)
    );

    // high = period * duty / 100000
    // B 口：高位补 0 扩展到 IP 位宽
    mult_gen_0 u_mult (
        .CLK (clk_in),
        .A   (mult_operand),
        .B   ({4'd0, current_duty}),
        .P   (mult_result)
    );

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            current_freq    <= INIT_FREQ;
            current_duty    <= INIT_DUTY;
            dividend_reg    <= CLK_X1000;
            divisor_reg     <= INIT_FREQ;
            period_time_reg <= INIT_PER;
            high_time_reg   <= INIT_PER * INIT_DUTY / 100000;
            mult_operand    <= INIT_PER[31:0];
            hd_q            <= 64'd0;
            hd_r            <= 18'd0;
            hd_cnt          <= 6'd0;
            hd_busy         <= 1'b0;
        end else begin
            // 频率更新：拒绝 0，防止除零
            if (update_flag_trigger) begin
                if (trigger_freq != 32'd0) begin
                    current_freq <= trigger_freq;
                    divisor_reg  <= {32'd0, trigger_freq};
                end
                // trigger_freq==0：保持原值不变
            end

            // 占空比更新：限制 0~100000
            if (update_flag_duty) begin
                if (duty_factor <= 32'd100_000)
                    current_duty <= duty_factor;
            end

            // 同步除法结果
            if (div_valid) begin
                // 周期至少为 2
                if (div_result[127:64] < 64'd2)
                    period_time_reg <= 64'd2;
                else
                    period_time_reg <= div_result[127:64];

                // 乘法器仅 32 位 A 口：超出则饱和到全 1
                if (div_result[127:64] > 64'hFFFF_FFFF)
                    mult_operand <= 32'hFFFF_FFFF;
                else if (div_result[127:64] < 64'd2)
                    mult_operand <= 32'd2;
                else
                    mult_operand <= div_result[95:64];
            end

            // 高电平时间 = mult_result / 100000，循环重算
            if (!hd_busy) begin
                hd_q    <= mult_result[63:0];
                hd_r    <= 18'd0;
                hd_cnt  <= 6'd0;
                hd_busy <= 1'b1;
            end else begin
                hd_r   <= hd_ge ? (hd_r_sh - DUTY_FULL) : hd_r_sh;
                hd_q   <= {hd_q[62:0], hd_ge};
                hd_cnt <= hd_cnt + 1'b1;
                if (hd_cnt == 6'd63) begin
                    hd_busy       <= 1'b0;
                    high_time_reg <= {hd_q[62:0], hd_ge};
                end
            end
        end
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt <= 64'd0;
            clk_out    <= 1'b1;
        end else begin
            if (period_cnt >= (period_time_reg - 64'd1))
                period_cnt <= 64'd0;
            else
                period_cnt <= period_cnt + 1'b1;

            clk_out <= (period_cnt < high_time_reg) ? 1'b1 : 1'b0;
        end
    end

endmodule
