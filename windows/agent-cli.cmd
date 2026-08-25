@echo off
if "%~1"=="" (
  echo Usage: agent-cli ^<cli-adapter arguments^> 1>&2
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-cli.ps1" %*
exit /b %ERRORLEVEL%
