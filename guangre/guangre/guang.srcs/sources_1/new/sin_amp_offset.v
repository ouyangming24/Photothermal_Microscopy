// =============================================================================
// sin_amp_offset.v
// 对 DDS 有符号正弦做幅度缩放 + 有符号偏置 + 饱和，输出 10-bit 无符号 DAC 码
//
//   code = clamp( 512 + round(signed_in * amp_pct / 100) + offset , 0, 1023 )
//
// 参数：
//   signed_in : DDS 有符号输出，-512 ~ +511
//   amp_pct   : 幅度百分比 0 ~ 100（0 = 只输出直流）
//   offset    : 有符号偏置（DAC 码），-1023 ~ +1023
//               正值 -> 中心电平上移，负值 -> 下移，0 -> 中点 512
//   INVERT    : 1 = 输出码取反（1023-code），用于模拟前端反相的板子
//
// 实现：/100 用乘法近似 amp*5243/2^19（误差 < 0.002%），不综合除法器
// 延迟：3 个 clk
// 波形 + 偏置超出 0~1023 时会削顶/削底（饱和），不会回绕
// =============================================================================
module sin_amp_offset #(
    parameter INVERT = 0
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire signed [9:0]  signed_in,
    input  wire        [6:0]  amp_pct,
    input  wire signed [10:0] offset,
    output reg         [9:0]  unsigned_out
);

    localparam signed [12:0] MID_CODE = 13'sd512;

    reg        [6:0]  amp_r;
    reg signed [10:0] off_r;
    reg        [19:0] gain_q;   // amp_pct * 5243，最大 524300 < 2^20
    reg signed [10:0] off_d;
    reg signed [30:0] prod;
    reg signed [12:0] level;

    // 四舍五入后右移 19 位，结果落在 -512 ~ +511
    wire signed [30:0] prod_rnd = prod + 31'sd262144;
    wire signed [11:0] scaled   = prod_rnd >>> 19;

    wire [9:0] code_clamped = (level < 13'sd0)    ? 10'd0    :
                              (level > 13'sd1023) ? 10'd1023 :
                                                    level[9:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            amp_r        <= 7'd0;
            off_r        <= 11'sd0;
            gain_q       <= 20'd0;
            off_d        <= 11'sd0;
            prod         <= 31'sd0;
            level        <= MID_CODE;
            unsigned_out <= INVERT ? 10'd511 : 10'd512;
        end else begin
            // 参数来自 sys_clk 域，先在本时钟域打一拍
            amp_r  <= (amp_pct > 7'd100) ? 7'd100 : amp_pct;
            off_r  <= offset;
            gain_q <= amp_r * 20'd5243;

            // 1) 幅度缩放
            prod  <= signed_in * $signed({1'b0, gain_q});
            off_d <= off_r;

            // 2) 中点 + 缩放后正弦 + 有符号偏置
            level <= MID_CODE + scaled + off_d;

            // 3) 饱和（可选反相）
            unsigned_out <= INVERT ? (10'd1023 - code_clamped) : code_clamped;
        end
    end

endmodule
