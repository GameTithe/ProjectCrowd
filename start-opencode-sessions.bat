@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "SERVER_URL=http://127.0.0.1:4096"
set "SESSION_FILE=%ROOT%opencode-session-ids.txt"

if not exist "%SESSION_FILE%" (
  echo No saved Manager and Worker sessions were found.
  echo Run new-opencode-sessions.bat first.
  pause
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in ("%SESSION_FILE%") do (
  if "%%A"=="MANAGER_SESSION" set "MANAGER_SESSION=%%B"
  if "%%A"=="WORKER_SESSION" set "WORKER_SESSION=%%B"
)

if not defined MANAGER_SESSION (
  echo The saved Manager session ID is missing.
  pause
  exit /b 1
)
if not defined WORKER_SESSION (
  echo The saved Worker session ID is missing.
  pause
  exit /b 1
)

call :ensure_server
if errorlevel 1 exit /b 1

start "OpenCode Manager" /D "%ROOT%" cmd /k "opencode.cmd attach %SERVER_URL% --session %MANAGER_SESSION%"
start "OpenCode Worker" /D "%ROOT%" cmd /k "opencode.cmd attach %SERVER_URL% --session %WORKER_SESSION%"

echo Opened Manager and Worker sessions.
exit /b 0

:ensure_server
curl.exe --silent --fail "%SERVER_URL%/global/health" >nul 2>&1
if not errorlevel 1 goto :server_ready

start "OpenCode Server" /D "%ROOT%" cmd /k "opencode.cmd serve --hostname 127.0.0.1 --port 4096"

for /l %%I in (1,1,20) do (
  curl.exe --silent --fail "%SERVER_URL%/global/health" >nul 2>&1 && goto :server_ready
  timeout /t 1 /nobreak >nul
)

echo Failed to start the OpenCode server at %SERVER_URL%.
exit /b 1

:server_ready
exit /b 0
