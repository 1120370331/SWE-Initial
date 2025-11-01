@echo off
setlocal enabledelayedexpansion

rem Quick lookup helper for the .memories directory (cmd.exe version).
set "script_dir=%~dp0"
if "%script_dir:~-1%"=="\" set "script_dir=%script_dir:~0,-1%"
set "mem_root=%script_dir%\.."
for %%I in ("%mem_root%") do set "mem_root=%%~fI"
set "modules_dir=%mem_root%\modules"

if not exist "%modules_dir%" (
  echo Memories modules directory not found: %modules_dir%
  exit /b 2
)

if "%~1"=="" goto usage
if /I "%~1"=="--help" goto help
if /I "%~1"=="--list-modules" goto list

set "keywords="
:collect
if "%~1"=="" goto search
if defined keywords (
  set "keywords=%keywords%|||%~1"
) else (
  set "keywords=%~1"
)
shift
goto collect

:search
set "MEM_LOOKUP_MODULES=%modules_dir%"
set "MEM_LOOKUP_KEYWORDS=%keywords%"
powershell -NoLogo -NoProfile -Command "& { $modules = $env:MEM_LOOKUP_MODULES; $raw = $env:MEM_LOOKUP_KEYWORDS; if (-not (Test-Path -Path $modules)) { Write-Error \"Memories modules directory not found: $modules\"; exit 2 }; if ([string]::IsNullOrWhiteSpace($raw)) { Write-Error 'Provide at least one keyword.'; exit 2 }; $keywords = $raw -split '\|\|\|'; $root = Split-Path -Path $modules -Parent; $files = Get-ChildItem -Path $modules -Filter '*.md' -Recurse; $results = $files | Select-String -Pattern $keywords -SimpleMatch; if (-not $results) { Write-Output 'No matches.'; exit 1 }; foreach ($match in $results) { $relative = $match.Path.Substring($root.Length + 1); $line = $match.Line.Trim(); Write-Output (\"{0}:{1}:{2}\" -f $relative, $match.LineNumber, $line) } }"
if errorlevel 1 exit /b %errorlevel%
exit /b 0

:list
for /f "tokens=* delims=" %%M in ('dir /B /AD "%modules_dir%"') do echo %%M
exit /b 0

:help
:usage
echo Usage: .memories\scripts\memories-lookup.cmd [--list-modules] ^<keyword^> [keyword...]
echo.
echo Options:
echo   --list-modules   List available memory modules and exit.
echo   --help           Show this help message.
echo.
echo Notes:
echo   - Searches all markdown files under .memories\modules.
echo   - Requires at least one keyword unless --list-modules is used.
exit /b 2
