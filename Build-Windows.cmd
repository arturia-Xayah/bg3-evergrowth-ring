@echo off
setlocal
py -3 "%~dp0tools\build.py"
if errorlevel 1 exit /b 1
echo Rebuild complete. Read README.zh-CN.md before installation.
