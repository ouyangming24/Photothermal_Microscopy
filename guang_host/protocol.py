"""UART protocol helpers for guang FPGA firmware."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Optional

import serial
import serial.tools.list_ports

DDS_CLK_HZ = 25_000_000.0
PHASE_WIDTH = 48
PHASE_MODULUS = 1 << PHASE_WIDTH

# FPGA UART 回包 + 状态机回到 IDLE 需要间隔
CMD_GAP_S = 0.05

# 与 ATK-XCOM「发送新行」一致：命令以 CRLF 结束
LINE_END = "\r\n"


def list_serial_ports() -> list[str]:
    return [p.device for p in serial.tools.list_ports.comports()]


def hz_to_pinc(freq_hz: float) -> int:
    if freq_hz < 0:
        raise ValueError("频率不能为负")
    pinc = int(round(freq_hz * PHASE_MODULUS / DDS_CLK_HZ))
    return max(0, min(pinc, PHASE_MODULUS - 1))


def pinc_to_hz(pinc: int) -> float:
    return pinc * DDS_CLK_HZ / PHASE_MODULUS


def deg_to_poff(phase_deg: float) -> int:
    """Convert degrees [0, 360) to 48-bit DDS phase offset POFF."""
    deg = phase_deg % 360.0
    if deg < 0:
        deg += 360.0
    poff = int(round(deg / 360.0 * PHASE_MODULUS)) % PHASE_MODULUS
    return poff


def poff_to_deg(poff: int) -> float:
    return (poff % PHASE_MODULUS) * 360.0 / PHASE_MODULUS


def trig_hz_to_cmd(freq_hz: float) -> int:
    """FPGA TRIG value is frequency in mHz (Hz * 1000)."""
    if freq_hz <= 0:
        raise ValueError("触发频率必须大于 0")
    return int(round(freq_hz * 1000.0))


def duty_percent_to_cmd(duty_percent: float) -> int:
    """FPGA DUTY value is 0..100000 for 0..100.000%."""
    if duty_percent < 0 or duty_percent > 100:
        raise ValueError("占空比需在 0~100%")
    return int(round(duty_percent * 1000.0))


@dataclass
class CommandResult:
    ok: bool
    command: str
    response: str
    detail: str = ""


class GuangDevice:
    def __init__(self) -> None:
        self._ser: Optional[serial.Serial] = None
        self.wait_response: bool = True
        self._last_banner: str = ""

    @property
    def last_banner(self) -> str:
        return self._last_banner

    @property
    def connected(self) -> bool:
        return self._ser is not None and self._ser.is_open

    def connect(self, port: str, baudrate: int = 115200, timeout: float = 0.1) -> None:
        self.disconnect()
        # dsrdtr/rtscts 关闭，避免打开串口时 DTR/RTS 把 FPGA 拉复位（XCOM 通常不这样）
        self._ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
            write_timeout=2.0,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        )
        try:
            self._ser.dtr = False
            self._ser.rts = False
        except Exception:
            pass

        time.sleep(0.15)
        self._ser.reset_input_buffer()
        self._ser.reset_output_buffer()

        # USB-UART 开串口时常有毛刺字节，先发 CRLF 让 FPGA 丢掉半截指令
        try:
            self._ser.write(b"\r\n\r\n")
            self._ser.flush()
            time.sleep(0.08)
            self._ser.reset_input_buffer()
        except Exception:
            pass

        # 可选：读上电横幅（需先开串口再按复位才容易看到）
        time.sleep(0.05)
        banner = self._ser.read(128)
        self._last_banner = banner.decode("ascii", errors="replace").strip() if banner else ""

    def disconnect(self) -> None:
        if self._ser is not None:
            try:
                if self._ser.is_open:
                    self._ser.close()
            finally:
                self._ser = None

    def read_available(self, max_bytes: int = 256) -> bytes:
        if not self.connected or self._ser is None:
            return b""
        waiting = self._ser.in_waiting
        if waiting <= 0:
            return b""
        return self._ser.read(min(waiting, max_bytes))

    def send_raw(self, command: str, wait_response: Optional[bool] = None) -> CommandResult:
        if not self.connected or self._ser is None:
            raise RuntimeError("串口未连接")

        if wait_response is None:
            wait_response = self.wait_response

        # 去掉用户可能带的换行，统一补 CRLF（对齐串口助手「发送新行」）
        core = command.rstrip("\r\n")
        payload = core + LINE_END
        cmd_show = payload.replace("\r", "\\r").replace("\n", "\\n")

        # 先丢掉陈旧输入，再发送
        self._ser.reset_input_buffer()
        raw_bytes = payload.encode("ascii", errors="strict")
        n = self._ser.write(raw_bytes)
        self._ser.flush()
        detail = f"write={n}/{len(raw_bytes)} " + " ".join(f"{b:02X}" for b in raw_bytes)

        if not wait_response:
            time.sleep(CMD_GAP_S)
            return CommandResult(ok=True, command=cmd_show, response="(skipped)", detail=detail)

        text, raw_rx = self._read_response(timeout_s=2.0)
        detail += " | RX " + (" ".join(f"{b:02X}" for b in raw_rx) if raw_rx else "(empty)")
        # 以最后一次完整应答为准（开串口毛刺可能先回一条 Error）
        ok = False
        if "Command Success" in text:
            last_ok = text.rfind("Command Success")
            last_err = text.rfind("Command Error")
            ok = last_ok >= 0 and last_ok > last_err
        time.sleep(CMD_GAP_S)
        return CommandResult(ok=ok, command=cmd_show, response=text or "(无应答)", detail=detail)

    def _read_response(self, timeout_s: float) -> tuple[str, bytes]:
        """读取直到出现 Success/Error，或超时。返回 (文本, 原始字节)。"""
        assert self._ser is not None
        deadline = time.time() + timeout_s
        buf = bytearray()
        while time.time() < deadline:
            # in_waiting 优先，避免无数据时每次空等 timeout
            n = self._ser.in_waiting
            if n:
                chunk = self._ser.read(n)
            else:
                chunk = self._ser.read(1)
            if chunk:
                buf.extend(chunk)
                text = buf.decode("ascii", errors="replace")
                if "Command Success" in text or "Command Error" in text:
                    time.sleep(0.03)
                    extra_n = self._ser.in_waiting
                    if extra_n:
                        buf.extend(self._ser.read(extra_n))
                    break
            if len(buf) > 512:
                break
        text = buf.decode("ascii", errors="replace").strip()
        return text, bytes(buf)

    def set_sine_pinc(self, pinc: int, light: bool = False) -> CommandResult:
        name = "SINE_LIGHT" if light else "SINE"
        return self.send_raw(f"{name}:{int(pinc)}")

    def set_sine_hz(self, freq_hz: float, light: bool = False) -> CommandResult:
        return self.set_sine_pinc(hz_to_pinc(freq_hz), light=light)

    def set_amplitude(self, amp: int, light: bool = False) -> CommandResult:
        if amp < 0 or amp > 100:
            raise ValueError("幅度必须在 0~100（%）")
        name = "AMPL_LIGHT" if light else "AMPL"
        return self.send_raw(f"{name}:{int(amp)}")

    def set_offset(self, offset: int, light: bool = False) -> CommandResult:
        if offset < -1023 or offset > 1023:
            raise ValueError("偏置必须在 -1023~+1023（正=上移，负=下移）")
        name = "OFFSET_LIGHT" if light else "OFFST"
        return self.send_raw(f"{name}:{int(offset)}")

    def set_phase_poff(self, poff: int, light: bool = False) -> CommandResult:
        name = "PHASE_LIGHT" if light else "PHASE"
        return self.send_raw(f"{name}:{int(poff)}")

    def set_phase_deg(self, phase_deg: float, light: bool = False) -> CommandResult:
        return self.set_phase_poff(deg_to_poff(phase_deg), light=light)

    def set_trigger_hz(self, freq_hz: float) -> CommandResult:
        return self.send_raw(f"TRIG:{trig_hz_to_cmd(freq_hz)}")

    def set_duty_percent(self, duty_percent: float) -> CommandResult:
        return self.send_raw(f"DUTY:{duty_percent_to_cmd(duty_percent)}")

    def set_t_light(self, value: int) -> CommandResult:
        return self.send_raw(f"T_LIGHT:{int(value)}")

    def set_d_light(self, value: int) -> CommandResult:
        return self.send_raw(f"D_LIGHT:{int(value)}")
