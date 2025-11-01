@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

if "%RAPID_LOGS_ROOT%"=="" (
  set "RAPID_LOGS_ROOT=%SCRIPT_DIR%logs"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\manage_log.ps1" %*
