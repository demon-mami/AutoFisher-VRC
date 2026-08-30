@echo off
setlocal EnableExtensions

set "ROOT=%~1"
set "REF=%~2"
if "%ROOT%"=="" exit /b 2
if "%REF%"=="" set "REF=main"

set "RUNTIME=%ROOT%_runtime"
set "APPROOT=%RUNTIME%\app"
set "DOWNLOADS=%RUNTIME%\downloads"
set "PATCH_REF_FILE=%RUNTIME%\PATCH_REF.txt"
set "PATCH_VERSION_FILE=%RUNTIME%\PATCH_VERSION.txt"
set "BASE_NAME=VRC.auto.fish.26031901.7z"
set "BASE_URL=https://github.com/day123123123/vrc-auto-fish/releases/download/26031901/VRC.auto.fish.26031901.7z"
set "BASE_SHA256=dbb7501b10c42d6372b53d5cd197683f131badd7e5a3038adbe1727243bee72c"

where curl.exe >nul 2>nul
if errorlevel 1 goto REQUIREMENTS_ERROR
where tar.exe >nul 2>nul
if errorlevel 1 goto REQUIREMENTS_ERROR
where certutil.exe >nul 2>nul
if errorlevel 1 goto REQUIREMENTS_ERROR

if not exist "%RUNTIME%" mkdir "%RUNTIME%" >nul 2>nul
if not exist "%DOWNLOADS%" mkdir "%DOWNLOADS%" >nul 2>nul

call :FIND_APP
if defined APP_EXE goto HAVE_APP

call :INSTALL_BASE
if errorlevel 1 goto FAIL
call :FIND_APP
if not defined APP_EXE goto FAIL

:HAVE_APP
for %%I in ("%APP_EXE%") do set "EXE_DIR=%%~dpI"
if defined AUTOFISHER_LAUNCHER_TEST echo [TEST] APP_EXE=%APP_EXE%
if defined AUTOFISHER_LAUNCHER_TEST echo [TEST] EXE_DIR=%EXE_DIR%

if defined AUTOFISHER_LAUNCHER_TEST goto SKIP_RUNNING_CHECK
tasklist /NH 2>nul | find /I "VRC auto fish-CUDA.exe" >nul
if not errorlevel 1 goto ALREADY_RUNNING

:SKIP_RUNNING_CHECK
call :SYNC_PATCH
if not errorlevel 1 goto LAUNCH

call :PATCH_READY
if errorlevel 1 goto FAIL
echo [AutoFisher-VRC] Update check failed. Starting the last verified local patch.

:LAUNCH
if defined AUTOFISHER_LAUNCHER_TEST (
    echo [AutoFisher-VRC] Launcher smoke test passed.
    exit /b 0
)
start "" "%APP_EXE%"
if errorlevel 1 goto FAIL
echo [AutoFisher-VRC] Started.
exit /b 0

:ALREADY_RUNNING
echo [AutoFisher-VRC] Already running.
exit /b 0

:REQUIREMENTS_ERROR
echo.
echo [AutoFisher-VRC] Required Windows tools are missing.
echo This launcher requires curl.exe, tar.exe, and certutil.exe.
pause
exit /b 1

:FAIL
echo.
echo [AutoFisher-VRC] Startup failed.
echo The existing runtime and patch were not intentionally replaced after a failed validation.
pause
exit /b 1

:FIND_APP
set "APP_EXE="
set "REL_EXE="
if exist "%RUNTIME%\APP_PATH.txt" set /p "REL_EXE="<"%RUNTIME%\APP_PATH.txt"
if defined REL_EXE if exist "%RUNTIME%\%REL_EXE%" set "APP_EXE=%RUNTIME%\%REL_EXE%"
if defined APP_EXE exit /b 0
if not exist "%APPROOT%" exit /b 0
for /r "%APPROOT%" %%F in ("VRC auto fish-CUDA.exe") do if not defined APP_EXE set "APP_EXE=%%~fF"
exit /b 0

:INSTALL_BASE
echo.
echo [AutoFisher-VRC] First-time runtime setup.
echo [1/3] Downloading the base runtime from the official upstream release...
set "BASE_ARCHIVE=%DOWNLOADS%\%BASE_NAME%"
curl.exe -fL --retry 3 --connect-timeout 15 -C - "%BASE_URL%" -o "%BASE_ARCHIVE%"
if errorlevel 1 exit /b 1

echo [2/3] Verifying SHA-256...
call :VERIFY_SHA256 "%BASE_ARCHIVE%" "%BASE_SHA256%"
if errorlevel 1 (
    echo [AutoFisher-VRC] Base runtime hash verification failed.
    del /q "%BASE_ARCHIVE%" >nul 2>nul
    exit /b 1
)

echo [3/3] Extracting the base runtime...
set "BASE_STAGE=%RUNTIME%\app.__new"
if exist "%BASE_STAGE%" rmdir /s /q "%BASE_STAGE%"
mkdir "%BASE_STAGE%" >nul 2>nul
tar.exe -xf "%BASE_ARCHIVE%" -C "%BASE_STAGE%"
if errorlevel 1 exit /b 1

set "STAGE_EXE="
for /r "%BASE_STAGE%" %%F in ("VRC auto fish-CUDA.exe") do if not defined STAGE_EXE set "STAGE_EXE=%%~fF"
if not defined STAGE_EXE (
    echo [AutoFisher-VRC] Base runtime EXE was not found after extraction.
    exit /b 1
)

if exist "%APPROOT%" rmdir /s /q "%APPROOT%"
move "%BASE_STAGE%" "%APPROOT%" >nul
if errorlevel 1 exit /b 1
del /q "%BASE_ARCHIVE%" >nul 2>nul
exit /b 0

:VERIFY_SHA256
set "HASH_FILE=%~1"
set "HASH_EXPECTED=%~2"
set "HASH_ACTUAL="
for /f "usebackq tokens=*" %%H in (`certutil.exe -hashfile "%HASH_FILE%" SHA256 ^| findstr /R /I /X "[0-9A-F][0-9A-F]*"`) do if not defined HASH_ACTUAL set "HASH_ACTUAL=%%H"
if not defined HASH_ACTUAL exit /b 1
if /I not "%HASH_ACTUAL%"=="%HASH_EXPECTED%" exit /b 1
exit /b 0

:PATCH_READY
if not defined EXE_DIR exit /b 1
if not exist "%EXE_DIR%patch\core\bite_detector.py" exit /b 1
if not exist "%EXE_DIR%patch\core\pd_controller.py" exit /b 1
if not exist "%EXE_DIR%patch\core\control_executor.py" exit /b 1
if not exist "%EXE_DIR%patch\core\control_backends.py" exit /b 1
if not exist "%EXE_DIR%patch\gui\app.py" exit /b 1
exit /b 0

:SYNC_PATCH
set "LOCAL_REF="
if exist "%PATCH_REF_FILE%" set /p "LOCAL_REF="<"%PATCH_REF_FILE%"
call :PATCH_READY
if errorlevel 1 goto NEED_PATCH
if /I "%LOCAL_REF%"=="%REF%" exit /b 0

:NEED_PATCH
echo [AutoFisher-VRC] Updating stable patch...
set "PATCH_ZIP=%DOWNLOADS%\AutoFisher-VRC-%REF%.zip"
set "SRC_STAGE=%RUNTIME%\patchsrc.__new"
set "SRC_ROOT="

del /q "%PATCH_ZIP%" >nul 2>nul
if exist "%SRC_STAGE%" rmdir /s /q "%SRC_STAGE%"
mkdir "%SRC_STAGE%" >nul 2>nul

curl.exe -fL --retry 3 --connect-timeout 10 "https://github.com/demon-mami/AutoFisher-VRC/archive/%REF%.zip" -o "%PATCH_ZIP%" >nul
if errorlevel 1 goto SYNC_FAIL
tar.exe -xf "%PATCH_ZIP%" -C "%SRC_STAGE%"
if errorlevel 1 goto SYNC_FAIL

for /d %%D in ("%SRC_STAGE%\AutoFisher-VRC-*") do if not defined SRC_ROOT set "SRC_ROOT=%%~fD"
if not defined SRC_ROOT goto SYNC_FAIL
if not exist "%SRC_ROOT%\patch\core\bite_detector.py" goto SYNC_FAIL
if not exist "%SRC_ROOT%\patch\core\pd_controller.py" goto SYNC_FAIL
if not exist "%SRC_ROOT%\patch\core\control_executor.py" goto SYNC_FAIL
if not exist "%SRC_ROOT%\patch\core\control_backends.py" goto SYNC_FAIL
if not exist "%SRC_ROOT%\patch\gui\app.py" goto SYNC_FAIL

set "PATCH_DIR=%EXE_DIR%patch"
set "PATCH_NEW=%EXE_DIR%patch.__new"
set "PATCH_OLD=%EXE_DIR%patch.__old"
if defined AUTOFISHER_LAUNCHER_TEST echo [TEST] PATCH_DIR=%PATCH_DIR%
if defined AUTOFISHER_LAUNCHER_TEST echo [TEST] PATCH_NEW=%PATCH_NEW%
if defined AUTOFISHER_LAUNCHER_TEST echo [TEST] SRC_ROOT=%SRC_ROOT%
if exist "%PATCH_NEW%" rmdir /s /q "%PATCH_NEW%"
if exist "%PATCH_OLD%" rmdir /s /q "%PATCH_OLD%"
mkdir "%PATCH_NEW%" >nul 2>nul
xcopy "%SRC_ROOT%\patch\*" "%PATCH_NEW%\" /E /I /Y /Q >nul

if not exist "%PATCH_NEW%\core\bite_detector.py" goto SYNC_FAIL_BEFORE_SWAP
if not exist "%PATCH_NEW%\core\pd_controller.py" goto SYNC_FAIL_BEFORE_SWAP
if not exist "%PATCH_NEW%\core\control_executor.py" goto SYNC_FAIL_BEFORE_SWAP
if not exist "%PATCH_NEW%\core\control_backends.py" goto SYNC_FAIL_BEFORE_SWAP
if not exist "%PATCH_NEW%\gui\app.py" goto SYNC_FAIL_BEFORE_SWAP
if defined AUTOFISHER_LAUNCHER_TEST dir /s /b "%PATCH_NEW%"

if exist "%PATCH_DIR%" move "%PATCH_DIR%" "%PATCH_OLD%" >nul
move "%PATCH_NEW%" "%PATCH_DIR%" >nul
if errorlevel 1 goto SWAP_ROLLBACK
if defined AUTOFISHER_LAUNCHER_TEST dir /s /b "%EXE_DIR%"

if exist "%PATCH_OLD%" rmdir /s /q "%PATCH_OLD%"
>"%PATCH_REF_FILE%" echo %REF%
if exist "%SRC_ROOT%\VERSION" type "%SRC_ROOT%\VERSION" >"%PATCH_VERSION_FILE%"

del /q "%PATCH_ZIP%" >nul 2>nul
if exist "%SRC_STAGE%" rmdir /s /q "%SRC_STAGE%"
echo [AutoFisher-VRC] Patch updated.
exit /b 0

:SWAP_ROLLBACK
if exist "%PATCH_DIR%" rmdir /s /q "%PATCH_DIR%"
if exist "%PATCH_OLD%" move "%PATCH_OLD%" "%PATCH_DIR%" >nul
goto SYNC_FAIL

:SYNC_FAIL_BEFORE_SWAP
if exist "%PATCH_NEW%" rmdir /s /q "%PATCH_NEW%"

:SYNC_FAIL
del /q "%PATCH_ZIP%" >nul 2>nul
if exist "%SRC_STAGE%" rmdir /s /q "%SRC_STAGE%"
exit /b 1
