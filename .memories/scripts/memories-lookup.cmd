@echo off
setlocal enabledelayedexpansion

rem Quick lookup helper for the .memories directory (cmd.exe version).
set "script_dir=%~dp0"
if "%script_dir:~-1%"=="\" set "script_dir=%script_dir:~0,-1%"
set "mem_root=%script_dir%\.."
for %%I in ("%mem_root%") do set "mem_root=%%~fI"
set "modules_dir=%mem_root%\modules"
set "modules_prefix=%modules_dir%\"

if not exist "%modules_dir%" (
  echo Memories modules directory not found: %modules_dir%
  exit /b 2
)

if "%~1"=="" goto :need_service
if /I "%~1"=="--help" goto :help
if /I "%~1"=="--list-modules" goto :list

set "service=%~1"
shift

if not exist "%modules_dir%\%service%" (
  echo Service module not found: %service%
  exit /b 2
)

if "%~1"=="" goto :list_service_files

set "keywords="
:collect
if "%~1"=="" goto :search
if defined keywords (
  set "keywords=%keywords%|||%~1"
) else (
  set "keywords=%~1"
)
shift
goto :collect

:search
set "MEM_LOOKUP_MODULES=%modules_dir%"
set "MEM_LOOKUP_SERVICE=%service%"
set "MEM_LOOKUP_KEYWORDS=%keywords%"
powershell -NoLogo -NoProfile -Command "& { $modules = $env:MEM_LOOKUP_MODULES; $service = $env:MEM_LOOKUP_SERVICE; $raw = $env:MEM_LOOKUP_KEYWORDS; $target = Join-Path -Path $modules -ChildPath $service; if (-not (Test-Path -Path $target)) { Write-Error \"Service module not found: $service\"; exit 2 }; if ([string]::IsNullOrWhiteSpace($raw)) { Write-Error 'Add at least one keyword to perform content search.'; exit 2 }; $keywords = $raw -split '\|\|\|'; $root = Split-Path -Path $modules -Parent; $files = Get-ChildItem -Path $target -Filter '*.md' -Recurse; $results = $files | Select-String -Pattern $keywords -SimpleMatch; if (-not $results) { Write-Output 'No matches.'; exit 1 }; foreach ($match in $results) { $relative = $match.Path.Substring($root.Length + 1); $line = $match.Line.Trim(); Write-Output (\"{0}:{1}:{2}\" -f $relative, $match.LineNumber, $line) } }"
if errorlevel 1 exit /b %errorlevel%
exit /b 0

:list
for /f "tokens=* delims=" %%M in ('dir /B /AD "%modules_dir%"') do echo %%M
exit /b 0

:list_service_files
set "service_root=%modules_dir%\%service%"
set "found="
for /f "delims=" %%F in ('dir /B /S "%service_root%\*.md" 2^>nul') do (
  set "found=1"
  set "file=%%F"
  set "rel=!file:%modules_prefix%=!"
  echo !rel!
)
if not defined found (
  echo No markdown files found under service %service%.
)
exit /b 0

:need_service
echo Missing required service parameter. Use --list-modules to inspect available options.
exit /b 2

:help
:usage
echo Usage: .memories\scripts\memories-lookup.cmd [--list-modules] ^<service^> [keyword...]
echo.
echo Options:
echo   --list-modules   List available memory modules and exit.
echo   --help           Show this help message.
echo.
echo Notes:
echo   - Searches markdown files within the specified module inside .memories\modules.
echo   - Service name is required; use --list-modules to discover available modules.
echo   - Omit keywords to list markdown files for the chosen service.
exit /b 2
