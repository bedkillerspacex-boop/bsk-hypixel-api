@echo off
REM BSK Hypixel local proxy -- show current status. No admin needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bsk-proxy.ps1" status
pause
