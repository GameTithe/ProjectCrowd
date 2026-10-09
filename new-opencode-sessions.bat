@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "SERVER_URL=http://127.0.0.1:4096"
set "SESSION_FILE=%ROOT%opencode-session-ids.txt"

call :ensure_server
if errorlevel 1 (
  pause
  exit /b 1
)

for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -Command "$body = [string]::Concat([char]123,[char]34,'title',[char]34,[char]58,[char]34,'Manager',[char]34,[char]125); (Invoke-RestMethod -Method Post -Uri '%SERVER_URL%/session' -ContentType 'application/json' -Body $body).id"`) do set "MANAGER_SESSION=%%A"
for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -Command "$body = [string]::Concat([char]123,[char]34,'title',[char]34,[char]58,[char]34,'Worker',[char]34,[char]125); (Invoke-RestMethod -Method Post -Uri '%SERVER_URL%/session' -ContentType 'application/json' -Body $body).id"`) do set "WORKER_SESSION=%%A"

if not defined MANAGER_SESSION (
  echo Failed to create the Manager session.
  pause
  exit /b 1
)
if not defined WORKER_SESSION (
  echo Failed to create the Worker session.
  pause
  exit /b 1
)

(
  echo MANAGER_SESSION=%MANAGER_SESSION%
  echo WORKER_SESSION=%WORKER_SESSION%
) > "%SESSION_FILE%"

echo Created and saved new session IDs:
echo Manager: %MANAGER_SESSION%
echo Worker:  %WORKER_SESSION%

start "OpenCode Manager" /D "%ROOT%" cmd /k "opencode.cmd attach %SERVER_URL% --session %MANAGER_SESSION%"
start "OpenCode Worker" /D "%ROOT%" cmd /k "opencode.cmd attach %SERVER_URL% --session %WORKER_SESSION%"
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
