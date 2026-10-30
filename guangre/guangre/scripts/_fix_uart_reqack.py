# -*- coding: utf-8 -*-
from pathlib import Path
import re

path = Path(
    r"e:\company\Aunion\Photothermal_Microscopy\program\fpga"
    r"\guang - guhua\guang - guhua\guang.srcs\sources_1\new\uart_commend.v"
)
text = path.read_text(encoding="utf-8")

text = text.replace(
    '(* fsm_encoding = "none" *)  // prevent Vivado FSM extract missing tx_done pulse\n',
    "",
    1,
)

text = text.replace(
    "    reg [2:0]  curr_state;",
    '    (* fsm_encoding = "none" *) reg [2:0] curr_state;',
    1,
)

old_lp = """    localparam IDLE          = 3'd0;
    localparam REC_CMD       = 3'd1;
    localparam REC_DATA      = 3'd2;
    localparam SEND_RESPONSE = 3'd3;
    localparam WAIT_SEND     = 3'd4;"""

new_lp = """    localparam IDLE          = 3'd0;
    localparam REC_CMD       = 3'd1;
    localparam REC_DATA      = 3'd2;
    localparam SEND_RESPONSE = 3'd3;
    localparam WAIT_SEND     = 3'd4;
    localparam BOOT_SEND     = 3'd5;
    localparam BOOT_WAIT     = 3'd6;"""

if old_lp not in text:
    raise SystemExit("localparam block not found")
text = text.replace(old_lp, new_lp, 1)

old_regs = """    reg        tx_done_sticky;
    reg [19:0] tx_wait_cnt;"""

new_regs = """    reg        tx_done_sticky;
    reg [19:0] tx_wait_cnt;
    reg        boot_done;
    reg [4:0]  boot_cnt;

    // Power-on banner GuangOK\\r\\n (9 bytes) to verify TX without host cmd
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
                5'd7: boot_byte = "\\r";
                default: boot_byte = "\\n";
            endcase
        end
    endfunction"""

if old_regs not in text:
    raise SystemExit("tx regs not found")
text = text.replace(old_regs, new_regs, 1)

# Only the first curr_state reset (in if !rst_n)
text = text.replace(
    "            curr_state   <= IDLE;\n            cmd_type     <= CMD_NONE;",
    "            curr_state   <= BOOT_SEND;\n            cmd_type     <= CMD_NONE;",
    1,
)

text = text.replace(
    """            tx_done_sticky <= 1'b0;
            tx_wait_cnt    <= 20'd0;

            sine_freq            <= 48'd10_000;""",
    """            tx_done_sticky <= 1'b0;
            tx_wait_cnt    <= 20'd0;
            boot_done      <= 1'b0;
            boot_cnt       <= 5'd0;

            sine_freq            <= 48'd10_000;""",
    1,
)

old_idle = """                IDLE: begin
                    send_en <= 1'b0;
                    if (rec_done) begin
                        cmd_buffer[0] <= rec_data;
                        cmd_cnt       <= 5'd1;
                        cmd_type      <= CMD_NONE;
                        curr_state    <= REC_CMD;
                    end
                end"""

new_idle = """                IDLE: begin
                    send_en <= 1'b0;
                    if (rec_done) begin
                        cmd_buffer[0] <= rec_data;
                        cmd_cnt       <= 5'd1;
                        cmd_type      <= CMD_NONE;
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
                end"""

if old_idle not in text:
    raise SystemExit("IDLE block not found")
text = text.replace(old_idle, new_idle, 1)

pat = re.compile(
    r"                // Reply: pulse send_en 1 cycle; wait sticky tx_done for next byte\n"
    r"                SEND_RESPONSE: begin.*?                default: curr_state <= IDLE;",
    re.S,
)

new_send = """                // Reply with level req/ack (matches uart_send WAIT_ACK)
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

                default: curr_state <= IDLE;"""

m = pat.search(text)
if not m:
    raise SystemExit("SEND_RESPONSE block not found")
text = pat.sub(new_send, text, count=1)

path.write_text(text, encoding="utf-8")
print("OK")
print("boot_byte", "boot_byte" in text)
print("BOOT_SEND", "BOOT_SEND" in text)
print("WAIT_ACK comment", "WAIT_ACK" in text)
