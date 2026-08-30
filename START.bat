@echo off
setlocal EnableExtensions
title AutoFisher-VRC

set "ROOT=%~dp0"
set "CACHE_DIR=%ROOT%_runtime\launcher"
set "CACHE_RUNNER=%CACHE_DIR%\run.cmd"
set "CACHE_REF=%CACHE_DIR%\stable_ref.txt"
set "TMP_REF=%TEMP%\AutoFisher-VRC-ref-%RANDOM%-%RANDOM%.txt"
set "TMP_RUN=%TEMP%\AutoFisher-VRC-run-%RANDOM%-%RANDOM%.cmd"
set "REF_URL=https://raw.githubusercontent.com/demon-mami/AutoFisher-VRC/main/STABLE_REF"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%" >nul 2>nul

set "STABLE_REF="
curl.exe -fsSL --retry 3 --connect-timeout 10 "%REF_URL%" -o "%TMP_REF%" >nul 2>nul
if errorlevel 1 goto USE_CACHE
set /p "STABLE_REF="<"%TMP_REF%"
del /q "%TMP_REF%" >nul 2>nul

call :VALIDATE_REF "%STABLE_REF%"
if errorlevel 1 goto USE_CACHE

set "CACHED_REF="
if exist "%CACHE_REF%" set /p "CACHED_REF="<"%CACHE_REF%"
if /I "%STABLE_REF%"=="%CACHED_REF%" if exist "%CACHE_RUNNER%" goto RUN_CACHED

set "RUN_URL=https://raw.githubusercontent.com/demon-mami/AutoFisher-VRC/%STABLE_REF%/launcher/run.cmd"
curl.exe -fsSL --retry 3 --connect-timeout 10 "%RUN_URL%" -o "%TMP_RUN%" >nul 2>nul
if errorlevel 1 goto USE_CACHE

set "RUN_SIZE=0"
for %%I in ("%TMP_RUN%") do set "RUN_SIZE=%%~zI"
if %RUN_SIZE% LSS 1000 goto USE_CACHE

copy /y "%TMP_RUN%" "%CACHE_RUNNER%" >nul
if errorlevel 1 goto USE_CACHE
>"%CACHE_REF%" echo %STABLE_REF%
del /q "%TMP_RUN%" >nul 2>nul
goto RUN_CACHED

:USE_CACHE
del /q "%TMP_REF%" >nul 2>nul
del /q "%TMP_RUN%" >nul 2>nul
if not exist "%CACHE_RUNNER%" goto NO_LAUNCHER
set "STABLE_REF="
if exist "%CACHE_REF%" set /p "STABLE_REF="<"%CACHE_REF%"
echo [AutoFisher-VRC] Network update unavailable. Using cached stable launcher.

:RUN_CACHED
call "%CACHE_RUNNER%" "%ROOT%" "%STABLE_REF%"
set "RC=%ERRORLEVEL%"
exit /b %RC%

:NO_LAUNCHER
echo.
echo [AutoFisher-VRC] Unable to download the launcher and no cached launcher exists.
echo Check the internet connection and run START.bat again.
pause
exit /b 1

:VALIDATE_REF
set "REF_CHECK=%~1"
if "%REF_CHECK%"=="" exit /b 1
if "%REF_CHECK:~39,1%"=="" exit /b 1
if not "%REF_CHECK:~40,1%"=="" exit /b 1
echo(%REF_CHECK%| findstr /R /I /X "[0-9a-f][0-9a-f]*" >nul
if errorlevel 1 exit /b 1
exit /b 0
