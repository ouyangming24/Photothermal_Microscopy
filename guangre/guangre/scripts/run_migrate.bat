@echo off
chcp 65001 >nul
setlocal EnableExtensions

REM =============================================================================
REM run_migrate.bat  - 新电脑迁移后一键升级 IP / 重新生成
REM
REM 用法:
REM   双击运行（默认：升级 IP + generate，不跑综合）
REM   run_migrate.bat
REM   run_migrate.bat -rebuild
REM   run_migrate.bat -bitstream
REM   run_migrate.bat -no_bd
REM   run_migrate.bat -gui          用 GUI 模式跑脚本（方便看日志）
REM =============================================================================

cd /d "%~dp0\.."
set "PROJ_DIR=%cd%"
set "TCL=%PROJ_DIR%\scripts\migrate_and_upgrade_ip.tcl"

echo ============================================
echo  Guang 工程迁移 / IP 升级
echo  工程目录: %PROJ_DIR%
echo  脚本    : %TCL%
echo ============================================

if not exist "%TCL%" (
  echo [错误] 找不到脚本: %TCL%
  pause
  exit /b 1
)

if not exist "%PROJ_DIR%\guang.xpr" (
  echo [错误] 找不到 guang.xpr，请确认目录正确
  pause
  exit /b 1
)

where vivado >nul 2>&1
if errorlevel 1 (
  echo [错误] 找不到 vivado 命令。
  echo 请先打开 "Vivado Tcl Shell" / "Xilinx Vivado" 对应环境，
  echo 或把 Vivado 安装目录的 bin 加入 PATH，例如:
  echo   C:\Xilinx\Vivado\2025.1\bin
  pause
  exit /b 1
)

set "MODE=batch"
set "EXTRA_ARGS="
:parse
if "%~1"=="" goto run
if /I "%~1"=="-gui" (
  set "MODE=gui"
  shift
  goto parse
)
set "EXTRA_ARGS=%EXTRA_ARGS% %~1"
shift
goto parse

:run
echo 模式: %MODE%
echo 额外参数:%EXTRA_ARGS%
echo.

if /I "%MODE%"=="gui" (
  vivado -mode gui -source "%TCL%" -tclargs -project "%PROJ_DIR%" %EXTRA_ARGS%
) else (
  vivado -mode batch -source "%TCL%" -tclargs -project "%PROJ_DIR%" %EXTRA_ARGS%
)

set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (
  echo [失败] Vivado 退出码 %ERR%
  pause
  exit /b %ERR%
)

echo [成功] 迁移/升级完成
echo 日志可在 Vivado 控制台或工程目录 vivado.log 查看
pause
exit /b 0
