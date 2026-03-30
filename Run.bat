@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

set "PORT=8964"
set "RUST_PROXY_PORT=8965"
set "RUST_PROXY_BIN=rust-proxy\target\release\anti-proxy.exe"
set "PID_DIR=%USERPROFILE%\.anti-api"
set "ANTI_API_PID=%PID_DIR%\anti-api.pid"
set "RUST_PID_FILE=%PID_DIR%\rust-proxy.pid"
set "SETTINGS_FILE=%PID_DIR%\settings.json"
set "AUTO_RESTART=false"
set "ANTI_API_PATTERN=anti-api|src/main\.ts|bun(\.exe)?"
set "RUST_PROXY_PATTERN=anti-proxy|rust-proxy"

if not exist "%PID_DIR%" mkdir "%PID_DIR%" >nul 2>&1
if exist "%USERPROFILE%\.bun\bin\bun.exe" set "PATH=%USERPROFILE%\.bun\bin;%PATH%"

echo Anti-API (Local Mode)
echo.

where bun >nul 2>&1
if errorlevel 1 (
    echo Bun not found. Installing...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bun.sh/install.ps1 | iex"
    if errorlevel 1 goto :error
    if exist "%USERPROFILE%\.bun\bin\bun.exe" set "PATH=%USERPROFILE%\.bun\bin;%PATH%"
)

REM Skip ngrok - running in local mode only
echo Running in local mode (ngrok skipped)
echo.

if exist "%SETTINGS_FILE%" (
    for /f %%V in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $data = Get-Content '%SETTINGS_FILE%' -Raw | ConvertFrom-Json; if ($data.autoRestart) { 'true' } else { 'false' } } catch { 'false' }"') do set "AUTO_RESTART=%%V"
)

call :cleanup_existing_processes

echo Building Rust proxy...
REM Skip TypeScript check - Bun runs TypeScript natively
REM bun x tsc >nul

REM Set up MSVC environment for cargo
set "VCVARS_CALLED=0"
set "MSVC_SETUP=0"

REM Try vswhere to find VS installation
if exist "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" (
    for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        if exist "%%i\VC\Auxiliary\Build\vcvars64.bat" (
            call "%%i\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
            set "MSVC_SETUP=1"
        )
    )
)

REM Check common VS 2022 paths
if "%MSVC_SETUP%"=="0" (
    if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
)

REM Check common VS 2019 paths
if "%MSVC_SETUP%"=="0" (
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvars64.bat" (
        call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
        set "MSVC_SETUP=1"
    )
)

cargo build --release --manifest-path rust-proxy/Cargo.toml
if errorlevel 1 goto :error

if not exist "%RUST_PROXY_BIN%" (
    echo Rust proxy binary not found.
    goto :error
)

echo Starting Rust proxy...
set "RUST_PID="
for /f %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$wd=[System.IO.Directory]::GetCurrentDirectory(); $p=Start-Process -FilePath '%RUST_PROXY_BIN%' -WorkingDirectory $wd -PassThru -WindowStyle Hidden; $p.Id"') do set "RUST_PID=%%P"
if not defined RUST_PID (
    echo Failed to start Rust proxy.
    goto :error
)
>%RUST_PID_FILE% echo !RUST_PID!

echo Starting Anti-API on http://localhost:%PORT%
echo.

:api_loop
call :run_api_once
set "API_EXIT=!ERRORLEVEL!"
if "!AUTO_RESTART!"=="true" (
    if not "!API_EXIT!"=="0" if not "!API_EXIT!"=="130" if not "!API_EXIT!"=="143" (
        echo Anti-API exited with code !API_EXIT!. Restarting in 2 seconds...
        timeout /t 2 /nobreak >nul
        goto :api_loop
    )
)

goto :shutdown

:run_api_once
set "API_PID="
REM Use temp file to capture PID, avoiding stdout contamination from the bun process
set "API_PID_TEMP=%PID_DIR%\api_pid_temp.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$wd=[System.IO.Directory]::GetCurrentDirectory(); $p=Start-Process -FilePath 'bun' -ArgumentList @('run','src/main.ts','start') -WorkingDirectory $wd -PassThru -NoNewWindow; $p.Id | Out-File -FilePath '%API_PID_TEMP%' -Encoding ascii"
if not exist "%API_PID_TEMP%" (
    echo Failed to start Anti-API.
    exit /b 1
)
set /p API_PID=<"%API_PID_TEMP%"
del "%API_PID_TEMP%" >nul 2>&1
if not defined API_PID (
    echo Failed to get Anti-API PID.
    exit /b 1
)
>%ANTI_API_PID% echo !API_PID!
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Get-Process -Id !API_PID! -ErrorAction Stop; $p.WaitForExit(); exit $p.ExitCode"
set "API_EXIT=!ERRORLEVEL!"
del "%ANTI_API_PID%" >nul 2>&1
exit /b !API_EXIT!

:cleanup_existing_processes
if exist "%ANTI_API_PID%" (
    set /p OLD_ANTI_PID=<"%ANTI_API_PID%"
    call :safe_kill_pid "!OLD_ANTI_PID!" "%ANTI_API_PATTERN%"
    del "%ANTI_API_PID%" >nul 2>&1
)
if exist "%RUST_PID_FILE%" (
    set /p OLD_RUST_PID=<"%RUST_PID_FILE%"
    call :safe_kill_pid "!OLD_RUST_PID!" "%RUST_PROXY_PATTERN%"
    del "%RUST_PID_FILE%" >nul 2>&1
)
call :safe_kill_by_port "%PORT%" "%ANTI_API_PATTERN%"
call :safe_kill_by_port "%RUST_PROXY_PORT%" "%RUST_PROXY_PATTERN%"
exit /b 0

:safe_kill_by_port
set "TARGET_PORT=%~1"
set "TARGET_PATTERN=%~2"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%TARGET_PORT% .*LISTENING"') do (
    call :safe_kill_pid "%%P" "%TARGET_PATTERN%"
)
exit /b 0

:safe_kill_pid
set "KILL_PID=%~1"
set "KILL_PATTERN=%~2"
if not defined KILL_PID exit /b 0
REM Validate PID is numeric before passing to PowerShell
echo %KILL_PID%| findstr /R "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:KILL_PID='%KILL_PID%'; $env:KILL_PATTERN='%KILL_PATTERN%'; $targetPid=[int]$env:KILL_PID; if($targetPid -le 0){ exit 0 }; $proc=Get-CimInstance Win32_Process -Filter \"ProcessId = $targetPid\" -ErrorAction SilentlyContinue; if(-not $proc){ exit 0 }; $cmd=[string]$proc.CommandLine; $name=[string]$proc.Name; if($cmd -match $env:KILL_PATTERN -or $name -match $env:KILL_PATTERN){ Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue }"
exit /b 0

:shutdown
if exist "%RUST_PID_FILE%" (
    set /p OLD_RUST_PID=<"%RUST_PID_FILE%"
    call :safe_kill_pid "!OLD_RUST_PID!" "%RUST_PROXY_PATTERN%"
    del "%RUST_PID_FILE%" >nul 2>&1
)
call :safe_kill_by_port "%RUST_PROXY_PORT%" "%RUST_PROXY_PATTERN%"
exit /b 0

:error
call :shutdown
echo.
echo Startup failed.
exit /b 1