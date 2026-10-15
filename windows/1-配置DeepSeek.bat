@echo off
title 配置 DeepSeek API Key
cd /d "%~dp0"

echo ============================================
echo   配置 DeepSeek API Key 到服务器
echo ============================================
echo.
echo 请先到 https://platform.deepseek.com 创建并复制 Key
echo （sk- 开头的一长串）
echo.
echo 在下面这行后面 右键粘贴 你的 Key，然后按回车：
echo.
set /p KEY=Key:

if "%KEY%"=="" (
    echo.
    echo [!] 你没有输入任何内容，已取消。
    pause
    exit /b
)

echo.
echo 正在配置，请稍候......
echo.
ssh root@175.178.120.171 "bash /opt/n8n/set_deepseek_key.sh %KEY%"

echo.
echo ============================================
echo 看上面有没有出现 "Key 可用"：
echo   有  = 配置成功
echo   没有 = 把上面的报错发给我
echo ============================================
pause
