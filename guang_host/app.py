# -*- coding: utf-8 -*-
"""Guang FPGA host control GUI."""

from __future__ import annotations

import ctypes
import sys
import threading
import time
import tkinter as tk
from collections.abc import Callable
from tkinter import messagebox, ttk

from protocol import (
    CommandResult,
    GuangDevice,
    deg_to_poff,
    hz_to_pinc,
    list_serial_ports,
    pinc_to_hz,
    poff_to_deg,
)


APP_TITLE = "光热显微调制控制 - Guang Host"
APP_VERSION = "1.3.1"


class ParamRow(ttk.Frame):
    """一行：标签 + 输入框 + 单位 + 单独下发按钮。"""

    def __init__(
        self,
        master,
        label: str,
        default: str = "",
        width: int = 12,
        unit: str = "",
        on_send: Callable[[], None] | None = None,
        send_text: str = "下发",
    ):
        super().__init__(master)
        ttk.Label(self, text=label, width=10, anchor="e").pack(side=tk.LEFT, padx=(0, 6))
        self.var = tk.StringVar(value=default)
        self.entry = ttk.Entry(self, textvariable=self.var, width=width)
        self.entry.pack(side=tk.LEFT)
        if unit:
            ttk.Label(self, text=unit, width=6).pack(side=tk.LEFT, padx=(4, 0))
        if on_send is not None:
            ttk.Button(self, text=send_text, width=8, command=on_send).pack(side=tk.LEFT, padx=(8, 0))

    def get(self) -> str:
        return self.var.get().strip()

    def get_float(self) -> float:
        return float(self.get())

    def get_int(self) -> int:
        return int(float(self.get()))


class GuangApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"{APP_TITLE} v{APP_VERSION}")
        self.geometry("820x700")
        self.minsize(760, 620)

        self.device = GuangDevice()
        self._busy = False
        self._lock = threading.Lock()

        self._build_style()
        self._build_ui()
        self.refresh_ports()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def _build_style(self) -> None:
        style = ttk.Style(self)
        if sys.platform.startswith("win"):
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 14, "bold"))
        style.configure("Hint.TLabel", foreground="#555555")
        style.configure("Status.TLabel", font=("Consolas", 10))

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)

        ttk.Label(root, text="光热显微 Guang FPGA 上位机", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            root,
            text="每个参数单独下发 · 频率→PINC · 相位(度)→POFF · 115200 8N1",
            style="Hint.TLabel",
        ).pack(anchor="w", pady=(2, 10))

        # ---- Serial ----
        ser = ttk.LabelFrame(root, text="串口连接", padding=10)
        ser.pack(fill=tk.X, pady=(0, 8))
        row = ttk.Frame(ser)
        row.pack(fill=tk.X)
        ttk.Label(row, text="端口").pack(side=tk.LEFT)
        self.port_var = tk.StringVar()
        self.port_box = ttk.Combobox(row, textvariable=self.port_var, width=18, state="readonly")
        self.port_box.pack(side=tk.LEFT, padx=6)
        ttk.Button(row, text="刷新", command=self.refresh_ports, width=8).pack(side=tk.LEFT)
        self.conn_btn = ttk.Button(row, text="连接", command=self.toggle_connect, width=10)
        self.conn_btn.pack(side=tk.LEFT, padx=(8, 0))
        self.status_var = tk.StringVar(value="未连接")
        ttk.Label(row, textvariable=self.status_var, style="Status.TLabel").pack(side=tk.LEFT, padx=12)

        # ---- Trigger ----
        trig = ttk.LabelFrame(root, text="同步触发 clk_out（分开下发）", padding=10)
        trig.pack(fill=tk.X, pady=(0, 8))
        self.trig_freq = ParamRow(
            trig, "触发频率", "80", unit="Hz", on_send=self.send_trig_freq
        )
        self.trig_freq.pack(anchor="w", pady=3)
        self.trig_duty = ParamRow(
            trig, "占空比", "50", unit="%", on_send=self.send_trig_duty
        )
        self.trig_duty.pack(anchor="w", pady=3)

        # ---- Channels ----
        chans = ttk.Frame(root)
        chans.pack(fill=tk.X, pady=(0, 8))
        chans.columnconfigure(0, weight=1)
        chans.columnconfigure(1, weight=1)

        self.ch0 = self._channel_frame(chans, "通道0 DAC", light=False)
        self.ch0.grid(row=0, column=0, sticky="nsew", padx=(0, 4))
        self.ch1 = self._channel_frame(chans, "通道1 光源 DAC", light=True)
        self.ch1.grid(row=0, column=1, sticky="nsew", padx=(4, 0))

        # ---- Reserved ----
        adv = ttk.LabelFrame(root, text="预留指令（分开下发）", padding=10)
        adv.pack(fill=tk.X, pady=(0, 8))
        self.t_light = ParamRow(
            adv, "T_LIGHT", "10000", width=10, on_send=self.send_t_light
        )
        self.t_light.pack(anchor="w", pady=3)
        self.d_light = ParamRow(
            adv, "D_LIGHT", "50000", width=10, on_send=self.send_d_light
        )
        self.d_light.pack(anchor="w", pady=3)

        actions = ttk.Frame(root)
        actions.pack(fill=tk.X, pady=(0, 8))
        ttk.Button(actions, text="清空日志", command=self.clear_log).pack(side=tk.LEFT)

        logf = ttk.LabelFrame(root, text="通信日志", padding=8)
        logf.pack(fill=tk.BOTH, expand=True)
        self.log = tk.Text(logf, height=12, wrap=tk.WORD, font=("Consolas", 10))
        self.log.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb = ttk.Scrollbar(logf, command=self.log.yview)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.log.configure(yscrollcommand=sb.set)
        self.log.configure(state=tk.DISABLED)

    def _channel_frame(self, master, title: str, light: bool) -> ttk.LabelFrame:
        frame = ttk.LabelFrame(master, text=title, padding=10)
        default_hz = "1000" if not light else "10000"

        freq = ParamRow(
            frame,
            "正弦频率",
            default_hz,
            unit="Hz",
            on_send=lambda: self.send_sine(light),
        )
        freq.pack(anchor="w", pady=3)

        amp = ParamRow(
            frame,
            "幅度",
            "10",
            unit="%",
            on_send=lambda: self.send_ampl(light),
        )
        amp.pack(anchor="w", pady=3)

        phase = ParamRow(
            frame,
            "相位",
            "0",
            unit="deg",
            on_send=lambda: self.send_phase(light),
        )
        phase.pack(anchor="w", pady=3)

        off = ParamRow(
            frame,
            "偏置",
            "0",
            unit="±DAC",
            on_send=lambda: self.send_offset(light),
        )
        off.pack(anchor="w", pady=3)
        ttk.Label(
            frame,
            text="幅度 0~100%（100=满幅）；偏置 -1023~+1023，0=中点，正上移/负下移",
            style="Hint.TLabel",
        ).pack(anchor="w", pady=(0, 2))

        pinc_var = tk.StringVar(value="")
        ttk.Label(frame, textvariable=pinc_var, style="Hint.TLabel").pack(anchor="w", pady=(2, 0))
        poff_var = tk.StringVar(value="")
        ttk.Label(frame, textvariable=poff_var, style="Hint.TLabel").pack(anchor="w", pady=(0, 0))

        def refresh_pinc(*_):
            try:
                hz = float(freq.get())
                pinc = hz_to_pinc(hz)
                pinc_var.set(f"PINC ≈ {pinc}  ({pinc_to_hz(pinc):.6f} Hz)")
            except Exception:
                pinc_var.set("PINC: 输入无效")

        def refresh_poff(*_):
            try:
                deg = float(phase.get())
                poff = deg_to_poff(deg)
                poff_var.set(f"POFF ≈ {poff}  ({poff_to_deg(poff):.3f} deg)")
            except Exception:
                poff_var.set("POFF: 输入无效")

        freq.var.trace_add("write", refresh_pinc)
        phase.var.trace_add("write", refresh_poff)
        refresh_pinc()
        refresh_poff()

        frame._freq = freq  # type: ignore[attr-defined]
        frame._amp = amp  # type: ignore[attr-defined]
        frame._phase = phase  # type: ignore[attr-defined]
        frame._off = off  # type: ignore[attr-defined]
        frame._light = light  # type: ignore[attr-defined]
        return frame

    def log_msg(self, text: str) -> None:
        def _append():
            self.log.configure(state=tk.NORMAL)
            self.log.insert(tk.END, text + "\n")
            self.log.see(tk.END)
            self.log.configure(state=tk.DISABLED)

        self.after(0, _append)

    def clear_log(self) -> None:
        self.log.configure(state=tk.NORMAL)
        self.log.delete("1.0", tk.END)
        self.log.configure(state=tk.DISABLED)

    def refresh_ports(self) -> None:
        ports = list_serial_ports()
        self.port_box["values"] = ports
        if ports:
            if self.port_var.get() not in ports:
                self.port_var.set(ports[0])
        else:
            self.port_var.set("")
        self.log_msg(f"[信息] 发现串口: {', '.join(ports) if ports else '无'}")

    def toggle_connect(self) -> None:
        if self.device.connected:
            self.device.disconnect()
            self.status_var.set("未连接")
            self.conn_btn.configure(text="连接")
            self.log_msg("[信息] 已断开")
            return
        port = self.port_var.get().strip()
        if not port:
            messagebox.showwarning(APP_TITLE, "请选择串口")
            return
        try:
            self.device.connect(port)
            self.status_var.set(f"已连接 {port}")
            self.conn_btn.configure(text="断开")
            self.log_msg(f"[信息] 已连接 {port} @ 115200 8N1 (DTR/RTS=off, 结尾 CRLF)")
            if self.device.last_banner:
                self.log_msg(f"[信息] 缓冲区内数据: {self.device.last_banner!r}")
            self.log_msg("[信息] 已发送同步换行，可直接下发参数")
        except Exception as exc:
            busy_hint = ""
            msg = str(exc).lower()
            if "permission" in msg or "access" in msg or "占用" in str(exc) or "busy" in msg:
                busy_hint = "\n\n该 COM 口可能被其它程序占用，请关闭 ATK-XCOM 后再试。"
            messagebox.showerror(APP_TITLE, f"连接失败:\n{exc}{busy_hint}")
            self.log_msg(f"[错误] 连接失败: {exc}")

    def _send_one(self, name: str, fn: Callable[[], CommandResult]) -> None:
        if self._busy:
            messagebox.showinfo(APP_TITLE, "正在下发，请稍候")
            return
        if not self.device.connected:
            messagebox.showwarning(APP_TITLE, "请先连接串口")
            return

        def worker() -> None:
            with self._lock:
                self._busy = True
                try:
                    result = fn()
                    mark = "OK" if result.ok else "FAIL"
                    reply = result.response or "(无应答)"
                    self.log_msg(f"[{mark}] {name}")
                    self.log_msg(f"  TX {result.command}")
                    self.log_msg(f"  RX {reply}")
                    if result.detail:
                        self.log_msg(f"  {result.detail}")
                    if not result.ok:
                        self.after(
                            0,
                            lambda: messagebox.showwarning(
                                APP_TITLE, f"{name} 失败\n应答: {reply}"
                            ),
                        )
                except Exception as exc:
                    self.log_msg(f"[错误] {name}: {exc}")
                    self.after(
                        0,
                        lambda e=exc: messagebox.showerror(APP_TITLE, f"{name} 异常:\n{e}"),
                    )
                finally:
                    self._busy = False

        threading.Thread(target=worker, daemon=True).start()

    def send_trig_freq(self) -> None:
        try:
            freq = self.trig_freq.get_float()
        except ValueError:
            messagebox.showerror(APP_TITLE, "触发频率格式错误")
            return
        self._send_one("TRIG", lambda: self.device.set_trigger_hz(freq))

    def send_trig_duty(self) -> None:
        try:
            duty = self.trig_duty.get_float()
        except ValueError:
            messagebox.showerror(APP_TITLE, "占空比格式错误")
            return
        self._send_one("DUTY", lambda: self.device.set_duty_percent(duty))

    def send_sine(self, light: bool) -> None:
        row = self.ch1 if light else self.ch0
        try:
            hz = row._freq.get_float()  # type: ignore[attr-defined]
        except ValueError:
            messagebox.showerror(APP_TITLE, "正弦频率格式错误")
            return
        tag = "SINE_LIGHT" if light else "SINE"
        self._send_one(tag, lambda: self.device.set_sine_hz(hz, light=light))

    def send_ampl(self, light: bool) -> None:
        row = self.ch1 if light else self.ch0
        try:
            amp = row._amp.get_int()  # type: ignore[attr-defined]
        except ValueError:
            messagebox.showerror(APP_TITLE, "幅度格式错误")
            return
        tag = "AMPL_LIGHT" if light else "AMPL"
        self._send_one(tag, lambda: self.device.set_amplitude(amp, light=light))

    def send_phase(self, light: bool) -> None:
        row = self.ch1 if light else self.ch0
        try:
            deg = row._phase.get_float()  # type: ignore[attr-defined]
        except ValueError:
            messagebox.showerror(APP_TITLE, "相位格式错误")
            return
        tag = "PHASE_LIGHT" if light else "PHASE"
        self._send_one(tag, lambda: self.device.set_phase_deg(deg, light=light))

    def send_offset(self, light: bool) -> None:
        row = self.ch1 if light else self.ch0
        try:
            off = row._off.get_int()  # type: ignore[attr-defined]
        except ValueError:
            messagebox.showerror(APP_TITLE, "偏置格式错误")
            return
        tag = "OFFSET_LIGHT" if light else "OFFST"
        self._send_one(tag, lambda: self.device.set_offset(off, light=light))

    def send_t_light(self) -> None:
        try:
            t = self.t_light.get_int()
        except ValueError:
            messagebox.showerror(APP_TITLE, "T_LIGHT 格式错误")
            return
        self._send_one("T_LIGHT", lambda: self.device.set_t_light(t))

    def send_d_light(self) -> None:
        try:
            d = self.d_light.get_int()
        except ValueError:
            messagebox.showerror(APP_TITLE, "D_LIGHT 格式错误")
            return
        self._send_one("D_LIGHT", lambda: self.device.set_d_light(d))

    def on_close(self) -> None:
        try:
            self.device.disconnect()
        finally:
            self.destroy()


def main() -> None:
    if sys.platform.startswith("win"):
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
    app = GuangApp()
    app.mainloop()


if __name__ == "__main__":
    main()
