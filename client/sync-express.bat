@echo off
setlocal enabledelayedexpansion

title DBF Sync Express - %COMPUTERNAME%

set SERVER_URL=https://dbf-sync.onrender.com
set CONERA=%COMPUTERNAME%
set DATA_DIR=C:\Bootdrv\AlohaQs\DATA
set NEWDATA_DIR=C:\Bootdrv\AlohaQs\NEWDATA
set VERSION_FILE=C:\Bootdrv\AlohaQs\version.txt
set IBERQS=C:\Bootdrv\AlohaQs\Bin\Iberqs.exe

if exist "%~dp0sync-config.txt" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0sync-config.txt") do (
        if /i "%%a"=="server_url" set SERVER_URL=%%b
        if /i "%%a"=="conera_name" set CONERA=%%b
        if /i "%%a"=="data_dir" set DATA_DIR=%%b
        if /i "%%a"=="newdata_dir" set NEWDATA_DIR=%%b
        if /i "%%a"=="version_file" set VERSION_FILE=%%b
    )
)

set CHROME=
for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set CHROME=%%~p
if "%CHROME%"=="" where chrome.exe >nul 2>nul && set CHROME=chrome.exe
if "%CHROME%"=="" (
    echo ERROR: No se encuentra Chrome
    echo Instale Google Chrome o use sync-conera.bat
    pause
    exit /b 1
)

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul

echo =============================================
echo   DBF Sync Express - %CONERA%
echo =============================================
echo.

REM ===== 1. VERSION =====
echo [1/3] Obteniendo version del servidor...

start /b /wait "" "%CHROME%" --headless --disable-gpu --no-sandbox --virtual-time-budget=10000 --dump-dom "%SERVER_URL%/api/version" > "%TEMP%\dbf_ver.txt" 2>nul

set VERSION=
for /f "tokens=2 delims=:,}" %%a in ('type "%TEMP%\dbf_ver.txt" 2^>nul ^| find "version"') do set "VERSION=%%~a"
if "%VERSION%"=="" (
    echo ERROR: No se pudo conectar al servidor
    echo %SERVER_URL%/api/version
    pause
    exit /b 1
)
echo Version servidor: %VERSION%

set LOCAL_VER=
if exist "%VERSION_FILE%" set /p LOCAL_VER=<"%VERSION_FILE%"
if "%LOCAL_VER%"=="%VERSION%" (
    echo Ya actualizado: %VERSION%
    goto run_iberqs
)
echo Version local: %LOCAL_VER%
echo.

REM ===== 2. DOWNLOAD =====
echo [2/3] Descargando %VERSION%...

set ZIP_FILE=%TEMP%\dbf_%VERSION%.zip
set DOWNLOADS=%USERPROFILE%\Downloads
del "%ZIP_FILE%" 2>nul

set CHROME_TEMP=%TEMP%\chrome_dl_%VERSION%
set CHROME_DL_DIR=!CHROME_TEMP!\downloads
set CHROME_UD_DIR=!CHROME_TEMP!\user-data
if exist "!CHROME_TEMP!" rmdir /s /q "!CHROME_TEMP!" 2>nul
md "!CHROME_DL_DIR!" 2>nul
md "!CHROME_UD_DIR!\Default" 2>nul

> "!CHROME_UD_DIR!\Default\Preferences" echo {"download":{"default_directory":"!CHROME_DL_DIR:\=\\!","prompt_for_download":false,"directory_upgrade":true},"safebrowsing":{"enabled":false},"browser":{"check_default_browser":false}}

echo   Chrome (perfil temporal, sin ventanas)...
taskkill /f /im chrome.exe >nul 2>nul
timeout /t 1 /nobreak >nul
start /min "" "%CHROME%" --user-data-dir="!CHROME_UD_DIR!" --no-sandbox --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --disable-features=DownloadBubble,InsecureDownloadWarnings --safebrowsing-disable-download-protection --new-window "%SERVER_URL%/api/download/%VERSION%"
timeout /t 20 /nobreak >nul
taskkill /f /im chrome.exe >nul 2>nul
timeout /t 1 /nobreak >nul

for /f "delims=" %%f in ('dir /a-d /s /b "!CHROME_DL_DIR!\*.zip" 2^>nul') do copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
if not exist "%ZIP_FILE%" (
    for /f "delims=" %%f in ('dir /a-d /s /b "%DOWNLOADS%\*%VERSION%*.zip" 2^>nul') do (
        copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
        del "%%f" 2>nul
    )
)

if not exist "%ZIP_FILE%" (
    echo.
    echo No se pudo descargar automaticamente.
    echo Abra Chrome y descargue:
    echo   %SERVER_URL%/api/download/%VERSION%
    echo Guarde el archivo y presione Enter para continuar...
    pause
    if not exist "%ZIP_FILE%" (
        echo Continuando sin actualizar...
        goto run_iberqs
    )
)
echo Zip descargado OK
echo.

REM ===== 3. EXTRACT =====
echo [3/3] Extrayendo archivos...

set EXTRACT_DIR=%TEMP%\dbf_extract
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%" 2>nul

powershell -ExecutionPolicy Bypass -Command "try { $s = New-Object -ComObject Shell.Application; $z = $s.NameSpace('%ZIP_FILE%'); $d = $s.NameSpace('%EXTRACT_DIR%'); $d.CopyHere($z.Items(), 20) } catch { exit 1 }"

if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" 2>nul
if not exist "%NEWDATA_DIR%" mkdir "%NEWDATA_DIR%" 2>nul

for /r "%EXTRACT_DIR%" %%f in (*.dbf) do (
    copy /y "%%f" "%DATA_DIR%\" >nul 2>nul
    copy /y "%%f" "%NEWDATA_DIR%\" >nul 2>nul
)

echo %VERSION% > "%VERSION_FILE%"
echo Actualizado a %VERSION%

del "%ZIP_FILE%" 2>nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul
rmdir /s /q "!CHROME_TEMP!" 2>nul

echo.

REM ===== RUN IBERQS =====
:run_iberqs
if exist "%IBERQS%" (
    echo Ejecutando Iberqs.exe...
    start "" "%IBERQS%"
) else (
    echo Aviso: No se encuentra %IBERQS%
)

echo.
echo Presione Enter para cerrar...
pause >nul
exit /b 0
