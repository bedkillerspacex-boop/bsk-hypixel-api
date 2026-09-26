@echo off
REM BSK Hypixel local proxy -- ENABLE interception.
REM Content is ASCII-only on purpose: cmd.exe reads .cmd files using the OEM
REM codepage, so non-ASCII text in here would render as garbage.
REM Elevation (UAC) is handled inside bsk-proxy.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bsk-proxy.ps1" install
if errorlevel 1 pause
