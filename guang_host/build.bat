@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo [1/3] 安装依赖...
python -m pip install -r requirements.txt
if errorlevel 1 goto :fail

echo [2/3] 清理旧构建...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist

echo [3/3] 打包单文件 exe (无控制台窗口)...
python -m PyInstaller --noconfirm guang_ctrl.spec
if errorlevel 1 goto :fail

echo.
echo 完成: dist\GuangHost.exe
echo 可直接复制到其他 Windows 电脑运行（无需安装 Python）。
echo 目标电脑需有对应 USB-串口驱动。
pause
exit /b 0

:fail
echo 打包失败。
pause
exit /b 1
