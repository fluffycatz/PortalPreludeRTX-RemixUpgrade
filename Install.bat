@echo off
setlocal
title Portal: Prelude RTX - install RTX Remix 1.6.1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set "RC=%ERRORLEVEL%"
if not defined REMIXUPGRADE_NOPAUSE pause
exit /b %RC%
