// =============================================================================
// guang.v  -- Photothermal modulation / trigger top-level
// Part: xc7z020clg484-2 (PL only, sys_clk = 50 MHz)
//
// UART(115200) configures:
//   clk_trig x2 -> clk_out, clk_light
//   DDS x2 (PINC + POFF programmable) + sin_amp_offset x2 -> dual AD9708
//
// Clocks:
//   sys_clk  50MHz : UART, commands, trigger PWM
//   clk_dac  25MHz : DDS, amp/offset, DAC data+clock
//
// DDS config TDATA: currently 48-bit PINC (until DDS IP regenerated for POFF)
//   f_out   = PINC * 25e6 / 2^48
//   After regenerate: 96-bit {POFF[47:0], PINC[47:0]}, phi_deg = POFF * 360 / 2^48
// =============================================================================
module guang (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    input  wire       clk_fx,
    output wire       clk_out,
    output wire       clk_light,
    output wire       da_clk,
    output wire [9:0] da_data,
    output wire       da_clk1,
    output wire [9:0] da_data1
);

    wire [7:0] send_data;
    wire       send_en;
    wire       tx_done;
    wire       tx_busy;
    wire [7:0] rec_data;
    wire       rec_done;

    uart_send u_uart_send (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .send_en(send_en), .send_data(send_data),
        .tx(uart_tx), .tx_done(tx_done), .busy(tx_busy)
    );

    uart_rec u_uart_rec (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .rx(uart_rx), .rec_data(rec_data), .rec_done(rec_done)
    );

    wire [47:0] sine_freq;
    wire [47:0] sine_phase;
    wire [31:0] trigger_freq;
    wire [31:0] duty_factor;
    wire [31:0] amp_factor;
    wire [31:0] offset_value;
    wire [31:0] t_light_value;
    wire [31:0] d_light_value;
    wire [47:0] sine_freq_light;
    wire [47:0] sine_phase_light;
    wire [31:0] amp_factor_light;
    wire [31:0] offset_value_light;

    wire update_flag_sine;
    wire update_flag_phase;
    wire update_flag_trigger;
    wire update_flag_duty;
    wire update_flag_amp;
    wire update_flag_offset;
    wire update_flag_t_light;
    wire update_flag_d_light;
    wire update_flag_sine_light;
    wire update_flag_phase_light;
    wire update_flag_ampl_light;
    wire update_flag_offset_light;

    uart_commend u_uart_commend (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .rec_data(rec_data), .rec_done(rec_done),
        .tx_done(tx_done), .tx_busy(tx_busy),
        .sine_freq(sine_freq),
        .sine_phase(sine_phase),
        .trigger_freq(trigger_freq),
        .duty_factor(duty_factor),
        .amplitude_ctrl(amp_factor),
        .offset_value(offset_value),
        .t_light_value(t_light_value),
        .d_light_value(d_light_value),
        .sine_freq_light(sine_freq_light),
        .sine_phase_light(sine_phase_light),
        .amplitude_ctrl_light(amp_factor_light),
        .offset_value_light(offset_value_light),
        .update_flag_sine(update_flag_sine),
        .update_flag_phase(update_flag_phase),
        .update_flag_trigger(update_flag_trigger),
        .update_flag_duty(update_flag_duty),
        .update_flag_ampl(update_flag_amp),
        .update_flag_offset(update_flag_offset),
        .update_flag_t_light(update_flag_t_light),
        .update_flag_d_light(update_flag_d_light),
        .update_flag_sine_light(update_flag_sine_light),
        .update_flag_phase_light(update_flag_phase_light),
        .update_flag_ampl_light(update_flag_ampl_light),
        .update_flag_offset_light(update_flag_offset_light),
        .send_en(send_en), .send_data(send_data)
    );

    clk_trig u_clk_trig (
        .clk_in(sys_clk), .rst_n(sys_rst_n),
        .trigger_freq(trigger_freq), .update_flag_trigger(update_flag_trigger),
        .duty_factor(duty_factor), .update_flag_duty(update_flag_duty),
        .clk_out(clk_out)
    );

    clk_trig u_clk_light (
        .clk_in(sys_clk), .rst_n(sys_rst_n),
        .trigger_freq(t_light_value), .update_flag_trigger(update_flag_t_light),
        .duty_factor(d_light_value), .update_flag_duty(update_flag_d_light),
        .clk_out(clk_light)
    );

    wire clk_dac;
    clk_fenpin #(.DIVIDE_RATIO(2)) u_clk_fenpin (
        .clk_in(sys_clk), .rst_n(sys_rst_n), .clk_out(clk_dac)
    );

    // DDS config: generated IP is still 48-bit PINC only (Phase_offset=Fixed).
    // xci says Programmable but regenerate was not applied -> synth warned 96 vs 48.
    // Drive PINC only so frequency updates; keep phase regs for after IP regen:
    //   wire [95:0] dds_cfg_0 = {sine_phase_dac, sine_freq_dac};
    // -------------------------------------------------------------------------
    reg [47:0] sine_freq_dac;
    reg [47:0] sine_freq_light_dac;
    reg [47:0] sine_phase_dac;
    reg [47:0] sine_phase_light_dac;
    always @(posedge clk_dac or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sine_freq_dac        <= 48'd10_000;
            sine_freq_light_dac  <= 48'd100_000;
            sine_phase_dac       <= 48'd0;
            sine_phase_light_dac <= 48'd0;
        end else begin
            sine_freq_dac        <= sine_freq;
            sine_freq_light_dac  <= sine_freq_light;
            sine_phase_dac       <= sine_phase;
            sine_phase_light_dac <= sine_phase_light;
        end
    end

    wire [47:0] dds_cfg_0 = sine_freq_dac;
    wire [47:0] dds_cfg_1 = sine_freq_light_dac;

    wire signed [15:0] sine_16;
    wire signed [9:0]  sine = sine_16[9:0];
    wire               m_axis_data_tvalid_0;
    wire               m_axis_phase_tvalid_0;
    wire        [47:0] m_axis_phase_tdata_0;

    dds_compiler_0 u_dds_compiler_0 (
        .aclk(clk_dac),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(dds_cfg_0),
        .m_axis_data_tvalid(m_axis_data_tvalid_0),
        .m_axis_data_tdata(sine_16),
        .m_axis_phase_tvalid(m_axis_phase_tvalid_0),
        .m_axis_phase_tdata(m_axis_phase_tdata_0)
    );

    // 示波器上若发现正偏置反而下移（模拟前端反相），把这里改成 1
    localparam DAC_INVERT = 0;

    wire [9:0] dac_in;
    sin_amp_offset #(.INVERT(DAC_INVERT)) u_sin_amp_offset (
        .clk(clk_dac), .rst_n(sys_rst_n),
        .signed_in(sine), .amp_pct(amp_factor[6:0]),
        .offset(offset_value[10:0]), .unsigned_out(dac_in)
    );

    wire signed [15:0] sine_light_16;
    wire signed [9:0]  sine_light = sine_light_16[9:0];
    wire               m_axis_data_tvalid_1;
    wire               m_axis_phase_tvalid_1;
    wire        [47:0] m_axis_phase_tdata_1;

    dds_compiler_1 u_dds_compiler_1 (
        .aclk(clk_dac),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(dds_cfg_1),
        .m_axis_data_tvalid(m_axis_data_tvalid_1),
        .m_axis_data_tdata(sine_light_16),
        .m_axis_phase_tvalid(m_axis_phase_tvalid_1),
        .m_axis_phase_tdata(m_axis_phase_tdata_1)
    );

    wire [9:0] dac_in_light;
    sin_amp_offset #(.INVERT(DAC_INVERT)) u_sin_amp_offset_light (
        .clk(clk_dac), .rst_n(sys_rst_n),
        .signed_in(sine_light), .amp_pct(amp_factor_light[6:0]),
        .offset(offset_value_light[10:0]), .unsigned_out(dac_in_light)
    );

    reg [9:0] da_data_r;
    reg [9:0] da_data1_r;
    always @(posedge clk_dac or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            da_data_r  <= 10'd0;
            da_data1_r <= 10'd0;
        end else begin
            da_data_r  <= dac_in;
            da_data1_r <= dac_in_light;
        end
    end

    assign da_clk   = clk_dac;
    assign da_clk1  = clk_dac;
    assign da_data  = da_data_r;
    assign da_data1 = da_data1_r;

    ila_0 u_ila_0 (
        .clk(sys_clk),
        .probe0(da_data),
        .probe1(da_data1),
        .probe2(clk_out)
    );

    (* keep = "true" *) wire _unused =
        clk_fx | update_flag_sine | update_flag_phase | update_flag_amp | update_flag_offset |
        update_flag_sine_light | update_flag_phase_light | update_flag_ampl_light |
        update_flag_offset_light |
        (|sine_phase_dac) | (|sine_phase_light_dac) |
        m_axis_data_tvalid_0 | m_axis_data_tvalid_1 |
        m_axis_phase_tvalid_0 | m_axis_phase_tvalid_1 |
        (|m_axis_phase_tdata_0) | (|m_axis_phase_tdata_1);

endmodule
