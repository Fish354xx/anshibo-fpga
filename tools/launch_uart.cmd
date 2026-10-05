@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uart_terminal.ps1" %*
pause
