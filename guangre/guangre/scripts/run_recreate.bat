@echo off
chcp 65001 >nul
setlocal

REM 从源文件干净重建工程到 _recreated\
cd /d "%~dp0\.."
set "PROJ_DIR=%cd%"
set "TCL=%PROJ_DIR%\scripts\recreate_project.tcl"
set "OUT=%PROJ_DIR%\_recreated"

where vivado >nul 2>&1
if errorlevel 1 (
  echo [错误] 找不到 vivado，请先配置 PATH
  pause
  exit /b 1
)

echo 重建工程到: %OUT%
vivado -mode batch -source "%TCL%" -tclargs -out "%OUT%"
echo 完成。新工程: %OUT%\guang.xpr
pause
