// =============================================================================
// uart_commend.v
// Parse UART ASCII commands, update parameter regs, send Success/Error reply.
//
// Frame: CMDNAME:<decimal>\r  or \n
// OK:    Command Success!\r\n
// Fail:  Command Error!\r\n
//
// Commands (case-sensitive, UPPERCASE):
//   SINE:<PINC>            CH0 DDS phase increment (48-bit), NOT Hz
//                          f_out = PINC * 25MHz / 2^48
//   SINE_LIGHT:<PINC>      CH1 DDS PINC
//   PHASE:<POFF>           CH0 DDS phase offset (48-bit)
//                          phi_deg = POFF * 360 / 2^48
//   PHASE_LIGHT:<POFF>     CH1 DDS phase offset
//   TRIG:<mHz>             trigger freq*1000, e.g. 80000=80Hz; forbid 0
//   DUTY:<0..100000>       trigger duty, e.g. 50000=50%
//   AMPL:<0..100>          CH0 amplitude, percent of DAC full swing (0 = DC only)
//   AMPL_LIGHT:<0..100>    CH1 amplitude
//   OFFST:<-1023..1023>    CH0 signed DAC offset around mid-code 512 (alias OFFSET:)
//                          positive = up, negative = down, 0 = centered
//   OFFSET_LIGHT:<-1023..1023> CH1 signed DAC offset
//   T_LIGHT:<mHz>          light trigger freq*1000; forbid 0
//   D_LIGHT:<0..100000>    light trigger duty
//
// Value: optional leading '-' (only OFFST/OFFSET/OFFSET_LIGHT), then digits.
// Empty value, '-' on other cmds, or non-digit chars -> Command Error!
// Out-of-range -> no reg update + Command Error!
// update_flag_* are 1-cycle pulses
// NOTE: Vivado synthesizes "\r" as ASCII 'r' (0x72), NOT CR (0x0D).
//       Always use 8'h0D / 8'h0A for CR/LF.
// =============================================================================
module uart_commend (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rec_data,
    input  wire        rec_done,
    input  wire        tx_done,
    input  wire        tx_busy,

    output reg  [47:0] sine_freq,
    output reg  [47:0] sine_phase,
    output reg  [31:0] trigger_freq,
    output reg  [31:0] duty_factor,
    output reg  [31:0] amplitude_ctrl,
    output reg  [31:0] offset_value,
    output reg  [31:0] t_light_value,
    output reg  [31:0] d_light_value,
    output reg  [47:0] sine_freq_light,
    output reg  [47:0] sine_phase_light,
    output reg  [31:0] amplitude_ctrl_light,
    output reg  [31:0] offset_value_light,

    output reg         update_flag_sine,
    output reg         update_flag_phase,
    output reg         update_flag_trigger,
    output reg         update_flag_duty,
    output reg         update_flag_ampl,
    output reg         update_flag_offset,
    output reg         update_flag_t_light,
    output reg         update_flag_d_light,
    output reg         update_flag_sine_light,
    output reg         update_flag_phase_light,
    output reg         update_flag_ampl_light,
    output reg         update_flag_offset_light,

    output reg         send_en,
    output reg  [7:0]  send_data
);

    localparam IDLE          = 3'd0;
    localparam REC_CMD       = 3'd1;
    localparam REC_DATA      = 3'd2;
    localparam SEND_RESPONSE = 3'd3;
    localparam WAIT_SEND     = 3'd4;
    localparam BOOT_SEND     = 3'd5;
    localparam BOOT_WAIT     = 3'd6;

    // TX timeout ~20ms @50MHz, recover if WAIT_SEND never sees tx_done
    localparam TX_TIMEOUT_CYCLES = 20'd1_000_000;

    localparam CMD_NONE         = 4'd0;
    localparam CMD_SINE         = 4'd1;
    localparam CMD_TRIG         = 4'd2;
    localparam CMD_DUTY         = 4'd3;
    localparam CMD_AMPL         = 4'd4;
    localparam CMD_OFFSET       = 4'd5;
    localparam CMD_T_LIGHT      = 4'd6;
    localparam CMD_D_LIGHT      = 4'd7;
    localparam CMD_SINE_LIGHT   = 4'd8;
    localparam CMD_AMPL_LIGHT   = 4'd9;
    localparam CMD_OFFSET_LIGHT = 4'd10;
    localparam CMD_PHASE        = 4'd11;
    localparam CMD_PHASE_LIGHT  = 4'd12;

    (* fsm_encoding = "none" *) reg [2:0] curr_state;
    reg [3:0]  cmd_type;
    reg [7:0]  cmd_buffer [0:15];
    reg [4:0]  cmd_cnt;
    reg [47:0] value_buffer;
    reg        value_neg;
    reg        has_digit;
    reg        bad_char;
    reg        rsp_ok;

    wire       is_offset_cmd = (cmd_type == CMD_OFFSET) || (cmd_type == CMD_OFFSET_LIGHT);
    wire [31:0] signed_value = value_neg ? (32'd0 - value_buffer[31:0]) : value_buffer[31:0];

    // Combinational message bytes (avoid initial-array init issues)
    function [7:0] success_byte;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  success_byte = "C";
                5'd1:  success_byte = "o";
                5'd2:  success_byte = "m";
                5'd3:  success_byte = "m";
                5'd4:  success_byte = "a";
                5'd5:  success_byte = "n";
                5'd6:  success_byte = "d";
                5'd7:  success_byte = " ";
                5'd8:  success_byte = "S";
                5'd9:  success_byte = "u";
                5'd10: success_byte = "c";
                5'd11: success_byte = "c";
                5'd12: success_byte = "e";
                5'd13: success_byte = "s";
                5'd14: success_byte = "s";
                5'd15: success_byte = "!";
                5'd16: success_byte = 8'h0D;
                default: success_byte = 8'h0A;
            endcase
        end
    endfunction

    function [7:0] error_byte;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  error_byte = "C";
                5'd1:  error_byte = "o";
                5'd2:  error_byte = "m";
                5'd3:  error_byte = "m";
                5'd4:  error_byte = "a";
                5'd5:  error_byte = "n";
                5'd6:  error_byte = "d";
                5'd7:  error_byte = " ";
                5'd8:  error_byte = "E";
                5'd9:  error_byte = "r";
                5'd10: error_byte = "r";
                5'd11: error_byte = "o";
                5'd12: error_byte = "r";
                5'd13: error_byte = "!";
                5'd14: error_byte = 8'h0D;
                default: error_byte = 8'h0A;
            endcase
        end
    endfunction

    reg [4:0]  msg_cnt;
    reg [4:0]  msg_len;
    reg        tx_done_sticky;
    reg [19:0] tx_wait_cnt;
    reg        boot_done;
    reg [4:0]  boot_cnt;

    // Power-on banner GuangOK\r\n (9 bytes) to verify TX without host cmd
    function [7:0] boot_byte;
        input [4:0] idx;
        begin
            case (idx)
                5'd0: boot_byte = "G";
                5'd1: boot_byte = "u";
                5'd2: boot_byte = "a";
                5'd3: boot_byte = "n";
                5'd4: boot_byte = "g";
                5'd5: boot_byte = "O";
                5'd6: boot_byte = "K";
                5'd7: boot_byte = 8'h0D;
                default: boot_byte = 8'h0A;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state   <= BOOT_SEND;
            cmd_type     <= CMD_NONE;
            cmd_cnt      <= 5'd0;
            value_buffer <= 48'd0;
            value_neg    <= 1'b0;
            has_digit    <= 1'b0;
            bad_char     <= 1'b0;
            msg_cnt        <= 5'd0;
            msg_len        <= 5'd0;
            rsp_ok         <= 1'b1;
            tx_done_sticky <= 1'b0;
            tx_wait_cnt    <= 20'd0;
            boot_done      <= 1'b0;
            boot_cnt       <= 5'd0;

            sine_freq            <= 48'd10_000;
            sine_phase           <= 48'd0;
            sine_freq_light      <= 48'd100_000;
            sine_phase_light     <= 48'd0;
            trigger_freq         <= 32'd80_000;
            duty_factor          <= 32'd50_000;
            amplitude_ctrl       <= 32'd10;
            amplitude_ctrl_light <= 32'd10;
            offset_value         <= 32'd0;
            offset_value_light   <= 32'd0;
            t_light_value        <= 32'd10_000;
            d_light_value        <= 32'd50_000;

            update_flag_sine         <= 1'b0;
            update_flag_phase        <= 1'b0;
            update_flag_trigger      <= 1'b0;
            update_flag_duty         <= 1'b0;
            update_flag_ampl         <= 1'b0;
            update_flag_offset       <= 1'b0;
            update_flag_t_light      <= 1'b0;
            update_flag_d_light      <= 1'b0;
            update_flag_sine_light   <= 1'b0;
            update_flag_phase_light  <= 1'b0;
            update_flag_ampl_light   <= 1'b0;
            update_flag_offset_light <= 1'b0;

            send_en   <= 1'b0;
            send_data <= 8'd0;
        end else begin
            update_flag_sine         <= 1'b0;
            update_flag_phase        <= 1'b0;
            update_flag_trigger      <= 1'b0;
            update_flag_duty         <= 1'b0;
            update_flag_ampl         <= 1'b0;
            update_flag_offset       <= 1'b0;
            update_flag_t_light      <= 1'b0;
            update_flag_d_light      <= 1'b0;
            update_flag_sine_light   <= 1'b0;
            update_flag_phase_light  <= 1'b0;
            update_flag_ampl_light   <= 1'b0;
            update_flag_offset_light <= 1'b0;

            case (curr_state)
                IDLE: begin
                    send_en <= 1'b0;
                    // 只接受 A-Z 作为指令开头，丢掉 USB 开串口毛刺 / 孤立 \r\n / 控制字符
                    if (rec_done && rec_data >= "A" && rec_data <= "Z") begin
                        cmd_buffer[0] <= rec_data;
                        cmd_cnt       <= 5'd1;
                        cmd_type      <= CMD_NONE;
                        value_neg     <= 1'b0;
                        has_digit     <= 1'b0;
                        bad_char      <= 1'b0;
                        value_buffer  <= 48'd0;
                        curr_state    <= REC_CMD;
                    end
                end

                // ---- power-on TX banner ----
                BOOT_SEND: begin
                    if (!tx_busy && !send_en) begin
                        send_en    <= 1'b1;
                        send_data  <= boot_byte(boot_cnt);
                        curr_state <= BOOT_WAIT;
                    end
                end

                BOOT_WAIT: begin
                    if (tx_done) begin
                        send_en <= 1'b0;
                        if (boot_cnt >= 5'd8) begin
                            boot_done  <= 1'b1;
                            boot_cnt   <= 5'd0;
                            curr_state <= IDLE;
                        end else begin
                            boot_cnt   <= boot_cnt + 1'b1;
                            curr_state <= BOOT_SEND;
                        end
                    end
                end

                REC_CMD: begin
                    if (rec_done) begin
                        // 半截指令遇到换行：静默回到 IDLE（用于开串口后的同步）
                        if (rec_data == 8'h0D || rec_data == 8'h0A) begin
                            cmd_cnt    <= 5'd0;
                            cmd_type   <= CMD_NONE;
                            curr_state <= IDLE;
                        end else if (cmd_cnt >= 5'd15) begin
                            rsp_ok     <= 1'b0;
                            msg_cnt    <= 5'd0;
                            msg_len    <= 5'd16;
                            cmd_type   <= CMD_NONE;
                            curr_state <= SEND_RESPONSE;
                        end else begin
                            cmd_buffer[cmd_cnt] <= rec_data;
                            cmd_cnt             <= cmd_cnt + 1'b1;

                            if (rec_data == ":") begin
                                if (cmd_cnt == 5'd4 &&
                                    cmd_buffer[0]=="S" && cmd_buffer[1]=="I" &&
                                    cmd_buffer[2]=="N" && cmd_buffer[3]=="E") begin
                                    cmd_type <= CMD_SINE; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd5 &&
                                    cmd_buffer[0]=="P" && cmd_buffer[1]=="H" &&
                                    cmd_buffer[2]=="A" && cmd_buffer[3]=="S" &&
                                    cmd_buffer[4]=="E") begin
                                    cmd_type <= CMD_PHASE; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd4 &&
                                    cmd_buffer[0]=="T" && cmd_buffer[1]=="R" &&
                                    cmd_buffer[2]=="I" && cmd_buffer[3]=="G") begin
                                    cmd_type <= CMD_TRIG; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd4 &&
                                    cmd_buffer[0]=="D" && cmd_buffer[1]=="U" &&
                                    cmd_buffer[2]=="T" && cmd_buffer[3]=="Y") begin
                                    cmd_type <= CMD_DUTY; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd4 &&
                                    cmd_buffer[0]=="A" && cmd_buffer[1]=="M" &&
                                    cmd_buffer[2]=="P" && cmd_buffer[3]=="L") begin
                                    cmd_type <= CMD_AMPL; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd5 &&
                                    cmd_buffer[0]=="O" && cmd_buffer[1]=="F" &&
                                    cmd_buffer[2]=="F" && cmd_buffer[3]=="S" &&
                                    cmd_buffer[4]=="T") begin
                                    cmd_type <= CMD_OFFSET; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd6 &&
                                    cmd_buffer[0]=="O" && cmd_buffer[1]=="F" &&
                                    cmd_buffer[2]=="F" && cmd_buffer[3]=="S" &&
                                    cmd_buffer[4]=="E" && cmd_buffer[5]=="T") begin
                                    cmd_type <= CMD_OFFSET; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd7 &&
                                    cmd_buffer[0]=="T" && cmd_buffer[1]=="_" &&
                                    cmd_buffer[2]=="L" && cmd_buffer[3]=="I" &&
                                    cmd_buffer[4]=="G" && cmd_buffer[5]=="H" &&
                                    cmd_buffer[6]=="T") begin
                                    cmd_type <= CMD_T_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd7 &&
                                    cmd_buffer[0]=="D" && cmd_buffer[1]=="_" &&
                                    cmd_buffer[2]=="L" && cmd_buffer[3]=="I" &&
                                    cmd_buffer[4]=="G" && cmd_buffer[5]=="H" &&
                                    cmd_buffer[6]=="T") begin
                                    cmd_type <= CMD_D_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd10 &&
                                    cmd_buffer[0]=="S" && cmd_buffer[1]=="I" &&
                                    cmd_buffer[2]=="N" && cmd_buffer[3]=="E" &&
                                    cmd_buffer[4]=="_" && cmd_buffer[5]=="L" &&
                                    cmd_buffer[6]=="I" && cmd_buffer[7]=="G" &&
                                    cmd_buffer[8]=="H" && cmd_buffer[9]=="T") begin
                                    cmd_type <= CMD_SINE_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd11 &&
                                    cmd_buffer[0]=="P" && cmd_buffer[1]=="H" &&
                                    cmd_buffer[2]=="A" && cmd_buffer[3]=="S" &&
                                    cmd_buffer[4]=="E" && cmd_buffer[5]=="_" &&
                                    cmd_buffer[6]=="L" && cmd_buffer[7]=="I" &&
                                    cmd_buffer[8]=="G" && cmd_buffer[9]=="H" &&
                                    cmd_buffer[10]=="T") begin
                                    cmd_type <= CMD_PHASE_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd10 &&
                                    cmd_buffer[0]=="A" && cmd_buffer[1]=="M" &&
                                    cmd_buffer[2]=="P" && cmd_buffer[3]=="L" &&
                                    cmd_buffer[4]=="_" && cmd_buffer[5]=="L" &&
                                    cmd_buffer[6]=="I" && cmd_buffer[7]=="G" &&
                                    cmd_buffer[8]=="H" && cmd_buffer[9]=="T") begin
                                    cmd_type <= CMD_AMPL_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else if (cmd_cnt == 5'd12 &&
                                    cmd_buffer[0]=="O" && cmd_buffer[1]=="F" &&
                                    cmd_buffer[2]=="F" && cmd_buffer[3]=="S" &&
                                    cmd_buffer[4]=="E" && cmd_buffer[5]=="T" &&
                                    cmd_buffer[6]=="_" && cmd_buffer[7]=="L" &&
                                    cmd_buffer[8]=="I" && cmd_buffer[9]=="G" &&
                                    cmd_buffer[10]=="H" && cmd_buffer[11]=="T") begin
                                    cmd_type <= CMD_OFFSET_LIGHT; value_buffer <= 48'd0; curr_state <= REC_DATA;
                                end else begin
                                    rsp_ok <= 1'b0; msg_cnt <= 5'd0; msg_len <= 5'd16;
                                    cmd_type <= CMD_NONE; curr_state <= SEND_RESPONSE;
                                end
                            end
                        end
                    end
                end

                REC_DATA: begin
                    if (rec_done) begin
                        // 结束符优先处理，避免与其它分支纠缠
                        if (rec_data == 8'h0D || rec_data == 8'h0A) begin
                            if (!has_digit || bad_char || (value_neg && !is_offset_cmd)) begin
                                rsp_ok <= 1'b0;
                            end else begin
                                case (cmd_type)
                                    CMD_SINE: begin
                                        sine_freq <= value_buffer;
                                        update_flag_sine <= 1'b1;
                                        rsp_ok <= 1'b1;
                                    end
                                    CMD_PHASE: begin
                                        sine_phase <= value_buffer;
                                        update_flag_phase <= 1'b1;
                                        rsp_ok <= 1'b1;
                                    end
                                    CMD_SINE_LIGHT: begin
                                        sine_freq_light <= value_buffer;
                                        update_flag_sine_light <= 1'b1;
                                        rsp_ok <= 1'b1;
                                    end
                                    CMD_PHASE_LIGHT: begin
                                        sine_phase_light <= value_buffer;
                                        update_flag_phase_light <= 1'b1;
                                        rsp_ok <= 1'b1;
                                    end
                                    CMD_TRIG: begin
                                        if (value_buffer[31:0] != 32'd0) begin
                                            trigger_freq <= value_buffer[31:0];
                                            update_flag_trigger <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_T_LIGHT: begin
                                        if (value_buffer[31:0] != 32'd0) begin
                                            t_light_value <= value_buffer[31:0];
                                            update_flag_t_light <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_DUTY: begin
                                        if (value_buffer <= 48'd100_000) begin
                                            duty_factor <= value_buffer[31:0];
                                            update_flag_duty <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_D_LIGHT: begin
                                        if (value_buffer <= 48'd100_000) begin
                                            d_light_value <= value_buffer[31:0];
                                            update_flag_d_light <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_AMPL: begin
                                        if (value_buffer <= 48'd100) begin
                                            amplitude_ctrl <= value_buffer[31:0];
                                            update_flag_ampl <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_AMPL_LIGHT: begin
                                        if (value_buffer <= 48'd100) begin
                                            amplitude_ctrl_light <= value_buffer[31:0];
                                            update_flag_ampl_light <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_OFFSET: begin
                                        if (value_buffer <= 48'd1023) begin
                                            offset_value <= signed_value;
                                            update_flag_offset <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    CMD_OFFSET_LIGHT: begin
                                        if (value_buffer <= 48'd1023) begin
                                            offset_value_light <= signed_value;
                                            update_flag_offset_light <= 1'b1;
                                            rsp_ok <= 1'b1;
                                        end else rsp_ok <= 1'b0;
                                    end
                                    default: rsp_ok <= 1'b0;
                                endcase
                            end
                            msg_cnt    <= 5'd0;
                            msg_len    <= 5'd0;
                            curr_state <= SEND_RESPONSE;
                        end else if (rec_data >= "0" && rec_data <= "9") begin
                            value_buffer <= value_buffer * 10 + (rec_data - "0");
                            has_digit    <= 1'b1;
                        end else if (rec_data == "-" && !has_digit && !value_neg) begin
                            value_neg <= 1'b1;
                        end else if (rec_data == " ") begin
                            // tolerate spaces
                        end else begin
                            bad_char <= 1'b1;
                        end
                    end
                end

                // Reply with level req/ack (matches uart_send WAIT_ACK)
                SEND_RESPONSE: begin
                    if (msg_len == 5'd0) begin
                        msg_len <= rsp_ok ? 5'd18 : 5'd16;
                        msg_cnt <= 5'd0;
                        send_en <= 1'b0;
                    end else if (!send_en && !tx_busy) begin
                        send_data  <= rsp_ok ? success_byte(msg_cnt) : error_byte(msg_cnt);
                        send_en    <= 1'b1;
                        tx_wait_cnt <= 20'd0;
                        curr_state <= WAIT_SEND;
                    end
                end

                WAIT_SEND: begin
                    if (tx_done) begin
                        send_en <= 1'b0; // release ack -> uart_send returns IDLE
                        tx_wait_cnt <= 20'd0;
                        if (msg_cnt < msg_len - 1'b1) begin
                            msg_cnt    <= msg_cnt + 1'b1;
                            curr_state <= SEND_RESPONSE;
                        end else begin
                            curr_state   <= IDLE;
                            cmd_cnt      <= 5'd0;
                            cmd_type     <= CMD_NONE;
                            value_buffer <= 48'd0;
                            msg_len      <= 5'd0;
                            msg_cnt      <= 5'd0;
                        end
                    end else if (tx_wait_cnt >= TX_TIMEOUT_CYCLES) begin
                        send_en     <= 1'b0;
                        tx_wait_cnt <= 20'd0;
                        msg_len     <= 5'd0;
                        msg_cnt     <= 5'd0;
                        cmd_cnt     <= 5'd0;
                        cmd_type    <= CMD_NONE;
                        curr_state  <= IDLE;
                    end else begin
                        tx_wait_cnt <= tx_wait_cnt + 1'b1;
                    end
                end

                default: curr_state <= IDLE;
            endcase
        end
    end

endmodule
