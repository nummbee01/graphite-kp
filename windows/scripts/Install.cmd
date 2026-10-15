@echo off
setlocal
cd /d "%~dp0"

rem --- self-elevate ---------------------------------------------------------
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo === Building Graphite KP ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if not "%errorlevel%"=="0" (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

echo.
echo === Installing Graphite KP ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -SetDefault
if not "%errorlevel%"=="0" (
    echo.
    echo INSTALL FAILED.
    pause
    exit /b 1
)

echo.
echo Finished. Sign out and back in (or reboot) to activate the layout.
pause
