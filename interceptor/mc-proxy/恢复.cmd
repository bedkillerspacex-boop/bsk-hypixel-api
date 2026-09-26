@echo off
REM BSK Hypixel local proxy -- RESTORE everything.
REM ASCII-only content (see the ENABLE script for why).
REM Elevation (UAC) is handled inside bsk-proxy.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bsk-proxy.ps1" restore
if errorlevel 1 pause
