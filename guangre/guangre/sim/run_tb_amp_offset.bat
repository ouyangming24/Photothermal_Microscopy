@echo off
rem Self-check sim for AMPL/OFFST. Requires Vivado bin in PATH (xvlog/xelab/xsim).
cd /d %~dp0
set SRC=..\guang.srcs\sources_1\new
call xvlog %SRC%\sin_amp_offset.v %SRC%\uart_commend.v tb_amp_offset.v || exit /b 1
call xelab -debug off -timescale 1ns/1ps tb_amp_offset -s tb_amp_offset_sim || exit /b 1
call xsim tb_amp_offset_sim -R
