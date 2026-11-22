@echo off
setlocal
title Portal: Prelude RTX - verify the RTX Remix files
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify.ps1" %*
set "RC=%ERRORLEVEL%"
if not defined REMIXUPGRADE_NOPAUSE pause
exit /b %RC%
