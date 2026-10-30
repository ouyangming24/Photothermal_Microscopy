@echo off
rem Self-check sim for clk_trig (IP replaced by behavioral stubs in tb). Requires Vivado bin in PATH.
cd /d %~dp0
set SRC=..\guang.srcs\sources_1\new
call xvlog %SRC%\clk_trig.v tb_clk_trig.v || exit /b 1
call xelab -debug off -timescale 1ns/1ps tb_clk_trig -s tb_clk_trig_sim || exit /b 1
call xsim tb_clk_trig_sim -R
