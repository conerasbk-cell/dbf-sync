@echo off
setlocal enabledelayedexpansion

title DBF Sync - %COMPUTERNAME%
set LOG_FILE=%TEMP%\dbf_sync_%COMPUTERNAME%.log
echo [%date% %time%] INICIO > "%LOG_FILE%"

echo =============================================
echo   DBF Sync Conera - Actualizacion Manual
echo =============================================
echo.

REM ===== CONFIG =====
set SERVER_URL=https://dbf-sync.onrender.com
set CONERA=%COMPUTERNAME%
set DATA_DIR=C:\Bootdrv\AlohaQs\DATA
set NEWDATA_DIR=C:\Bootdrv\AlohaQs\NEWDATA
set VERSION_FILE=C:\Bootdrv\AlohaQs\version.txt

if exist "%~dp0sync-config.txt" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0sync-config.txt") do (
        if /i "%%a"=="server_url" set SERVER_URL=%%b
        if /i "%%a"=="conera_name" set CONERA=%%b
        if /i "%%a"=="data_dir" set DATA_DIR=%%b
        if /i "%%a"=="newdata_dir" set NEWDATA_DIR=%%b
        if /i "%%a"=="version_file" set VERSION_FILE=%%b
    )
)

echo Conera: %CONERA%
echo Servidor: %SERVER_URL%
echo DATA: %DATA_DIR%
echo NEWDATA: %NEWDATA_DIR%
echo.
echo [%date% %time%] CONFIG: %CONERA% %SERVER_URL% >> "%LOG_FILE%"

REM ===== MAIN UPDATE CYCLE =====
:UPDATE_CYCLE
cls
echo =============================================
echo   DBF Sync - %CONERA%
echo =============================================
echo.

REM ===== PASO 1: TLS =====
echo [1/6] Activando TLS 1.2...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul
echo  OK
echo [%date% %time%] PASO1 TLS OK >> "%LOG_FILE%"

REM ===== PASO 2: VERSION =====
echo [2/6] Obteniendo version del servidor...
set VERSION=
cscript //nologo "%~dp0sync-download.vbs" version > "%TEMP%\dbf_version.txt" 2>>"%LOG_FILE%"
set /p VERSION=<"%TEMP%\dbf_version.txt"

if "%VERSION%"=="" (
    echo  Intentando PowerShell...
    powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $r = $w.DownloadString('%SERVER_URL%/api/version'); " ^
"$m = [regex]::Match($r, '\"\"version\"\":\s*\"\"([^\"]+)\"\"'); if($m.Success){$m.Groups[1].Value}else{''} " ^
"} catch { '' }" > "%TEMP%\dbf_version2.txt" 2>>"%LOG_FILE%"
    set /p VERSION=<"%TEMP%\dbf_version2.txt"
)

if "%VERSION%"=="" (
    echo  ERROR: No se pudo conectar al servidor
    echo [%date% %time%] ERROR: No se obtuvo version >> "%LOG_FILE%"
    echo.
    echo  Verifique internet y que el servidor este desplegado
    echo  %SERVER_URL%/api/version
    echo.
    echo  Cerrando en 10 segundos...
    timeout /t 10 /nobreak >nul
    exit /b 1
)
echo  OK: %VERSION%
echo [%date% %time%] PASO2 VERSION: %VERSION% >> "%LOG_FILE%"

REM ===== PASO 3: COMPARAR =====
echo [3/6] Verificando version local...
set LOCAL_VER=
if exist "%VERSION_FILE%" (
    set /p LOCAL_VER=<"%VERSION_FILE%"
)
if "%LOCAL_VER%"=="%VERSION%" (
    echo  Ya actualizado: %VERSION%
    echo [%date% %time%] PASO3 Ya actualizado >> "%LOG_FILE%"
    goto checkin_and_loop
)
echo  Local: %LOCAL_VER% ^| Servidor: %VERSION%
echo [%date% %time%] PASO3 Local: %LOCAL_VER% Servidor: %VERSION% >> "%LOG_FILE%"

REM ===== PASO 4: DESCARGAR =====
echo [4/6] Descargando...
title DBF Sync - %CONERA% - descargando...
set ZIP_FILE=%TEMP%\dbf_sync_%VERSION%.zip
set DOWNLOADS_DIR=%USERPROFILE%\Downloads
del "%ZIP_FILE%" 2>nul
echo [%date% %time%] PASO4 INICIO >> "%LOG_FILE%"

REM ===== METODO 1: CHROME =====
set CHROME_PATH=
for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set CHROME_PATH=%%~p
if "%CHROME_PATH%"=="" where chrome.exe >nul 2>nul && set CHROME_PATH=chrome.exe
echo [%date% %time%] CHROME PATH: %CHROME_PATH% >> "%LOG_FILE%"

if not "%CHROME_PATH%"=="" (
    echo   - Chrome...
    title DBF Sync - %CONERA% - Chrome...

    set CHROME_TEMP=%TEMP%\chrome_dl_%VERSION%
    set CHROME_DL_DIR=!CHROME_TEMP!\downloads
    set CHROME_UD_DIR=!CHROME_TEMP!\user-data
    if exist "!CHROME_TEMP!" rmdir /s /q "!CHROME_TEMP!" 2>nul
    md "!CHROME_DL_DIR!" 2>nul
    md "!CHROME_UD_DIR!\Default" 2>nul

    > "!CHROME_UD_DIR!\Default\Preferences" echo {"download":{"default_directory":"!CHROME_DL_DIR:\=\\!","prompt_for_download":false,"directory_upgrade":true},"safebrowsing":{"enabled":false},"browser":{"check_default_browser":false}}

    taskkill /f /im chrome.exe >nul 2>nul
    timeout /t 1 /nobreak >nul
    start /min "" "%CHROME_PATH%" --user-data-dir="!CHROME_UD_DIR!" --no-sandbox --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --disable-features=DownloadBubble,InsecureDownloadWarnings --safebrowsing-disable-download-protection --new-window "%SERVER_URL%/api/download/%VERSION%"
    timeout /t 20 /nobreak >nul
    taskkill /f /im chrome.exe >nul 2>nul
    timeout /t 1 /nobreak >nul

    for /f "delims=" %%f in ('dir /a-d /s /b "!CHROME_DL_DIR!\*.zip" 2^>nul') do copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
    if not exist "%ZIP_FILE%" (
        for /f "delims=" %%f in ('dir /a-d /s /b "%DOWNLOADS_DIR%\*%VERSION%*.zip" 2^>nul') do (
            copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
            del "%%f" 2>nul
        )
    )
    if exist "%ZIP_FILE%" (
        echo [%date% %time%] CHROME OK: encontrado >> "%LOG_FILE%"
        goto extraer
    )
    echo [%date% %time%] CHROME: no encontro ZIP >> "%LOG_FILE%"
)

REM ===== METODO 2: FIREFOX =====
set FIREFOX_PATH=
for %%p in ("%PROGRAMFILES%\Mozilla Firefox\firefox.exe" "%PROGRAMFILES(X86)%\Mozilla Firefox\firefox.exe") do if exist "%%~p" set FIREFOX_PATH=%%~p
if "%FIREFOX_PATH%"=="" where firefox.exe >nul 2>nul && set FIREFOX_PATH=firefox.exe
echo [%date% %time%] FIREFOX PATH: %FIREFOX_PATH% >> "%LOG_FILE%"

if not "%FIREFOX_PATH%"=="" (
    echo   - Firefox (perfil temp)...
    title DBF Sync - %CONERA% - Firefox...

    set FX_TEMP=%TEMP%\fx_dl_%VERSION%
    set FX_DL_DIR=!FX_TEMP!\downloads
    set FX_PROFILE_DIR=!FX_TEMP!\profile
    if exist "!FX_TEMP!" rmdir /s /q "!FX_TEMP!" 2>nul
    md "!FX_DL_DIR!" 2>nul
    md "!FX_PROFILE_DIR!" 2>nul

    (
    echo user_pref("browser.download.folderList", 2^);
    echo user_pref("browser.download.dir", "!FX_DL_DIR:\=\\!"^);
    echo user_pref("browser.download.useDownloadDir", true^);
    echo user_pref("browser.helperApps.neverAsk.saveToDisk", "application/zip,application/x-zip,application/x-zip-compressed"^);
    echo user_pref("browser.download.manager.showWhenStarting", false^);
    echo user_pref("browser.download.manager.focusWhenStarting", false^);
    echo user_pref("browser.download.manager.showAlertOnComplete", false^);
    echo user_pref("browser.shell.checkDefaultBrowser", false^);
    echo user_pref("browser.shell.skipDefaultBrowserCheckOnFirstRun", true^);
    ) > "!FX_PROFILE_DIR!\user.js"

    taskkill /f /im firefox.exe >nul 2>nul
    timeout /t 1 /nobreak >nul
    start /min "" "%FIREFOX_PATH%" --profile "!FX_PROFILE_DIR!" --no-remote --new-window "%SERVER_URL%/api/download/%VERSION%"
    timeout /t 20 /nobreak >nul
    taskkill /f /im firefox.exe >nul 2>nul
    timeout /t 1 /nobreak >nul

    for /f "delims=" %%f in ('dir /a-d /s /b "!FX_DL_DIR!\*.zip" 2^>nul') do copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
    if not exist "%ZIP_FILE%" (
        for /f "delims=" %%f in ('dir /a-d /s /b "%DOWNLOADS_DIR%\*%VERSION%*.zip" 2^>nul') do (
            copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
            del "%%f" 2>nul
        )
    )
    if exist "%ZIP_FILE%" (
        echo [%date% %time%] FIREFOX OK >> "%LOG_FILE%"
        goto extraer
    )
    echo [%date% %time%] FIREFOX: no encontro ZIP >> "%LOG_FILE%"
)

REM ===== METODO 3: bitsadmin (fallback) =====
echo   - bitsadmin...
echo [%date% %time%] bitsadmin intentando... >> "%LOG_FILE%"
bitsadmin /transfer dbfsync /download /priority high "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>>"%LOG_FILE%"
if exist "%ZIP_FILE%" (
    echo [%date% %time%] bitsadmin OK >> "%LOG_FILE%"
    goto extraer
)

REM ===== METODO 4: certutil (fallback) =====
echo   - certutil...
echo [%date% %time%] certutil intentando... >> "%LOG_FILE%"
certutil -urlcache -split -f "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>>"%LOG_FILE%"
if exist "%ZIP_FILE%" (
    echo [%date% %time%] certutil OK >> "%LOG_FILE%"
    goto extraer
)

REM ===== NADA FUNCIONO =====
echo [%date% %time%] ERROR: todos los metodos fallaron >> "%LOG_FILE%"
title DBF Sync - %CONERA% - ERROR descarga
echo.
echo  ERROR: No se pudo descargar automaticamente.
echo  Revise el log: %LOG_FILE%
echo.
echo  Abra Chrome y navegue a:
echo  %SERVER_URL%/api/download/%VERSION%
echo.
echo  Guarde el archivo en %ZIP_FILE%, luego presione Enter...
pause
if not exist "%ZIP_FILE%" (
    echo  Continuando sin actualizar...
    goto checkin_and_loop
)

:extraer
echo  ZIP descargado OK
echo [%date% %time%] PASO4 DESCARGA OK >> "%LOG_FILE%"

REM ===== PASO 5: EXTRAER =====
echo [5/6] Extrayendo archivos...
echo [%date% %time%] PASO5 EXTRACCION >> "%LOG_FILE%"
set EXTRACT_DIR=%TEMP%\dbf_sync_extract
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%" 2>nul

REM Extraer ZIP (Expand-Archive PS5+, fallback Shell.Application)
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) { Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force } else { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%EXTRACT_DIR%') } } catch { try { $s = New-Object -ComObject Shell.Application; $z = $s.NameSpace('%ZIP_FILE%'); $d = $s.NameSpace('%EXTRACT_DIR%'); $d.CopyHere($z.Items(), 20) } catch { exit 1 } }" >>"%LOG_FILE%" 2>&1

REM Quitar Zone.Identifier (archivos bloqueados por Windows)
powershell -ExecutionPolicy Bypass -Command "Get-ChildItem '%EXTRACT_DIR%' -Recurse -Force | ForEach-Object { Remove-Item ($_.FullName + ':Zone.Identifier') -ErrorAction SilentlyContinue }" >>"%LOG_FILE%" 2>&1

echo  Copiando a DATA y NEWDATA...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" 2>nul
if not exist "%NEWDATA_DIR%" mkdir "%NEWDATA_DIR%" 2>nul

for /r "%EXTRACT_DIR%" %%f in (*.dbf) do (
    copy /y "%%f" "%DATA_DIR%\" >nul 2>nul
    copy /y "%%f" "%NEWDATA_DIR%\" >nul 2>nul
)

echo %VERSION% > "%VERSION_FILE%" 2>>"%LOG_FILE%"
echo [%date% %time%] PASO5 OK >> "%LOG_FILE%"
echo  OK

REM ===== CHECK-IN =====
:checkin_and_loop
echo [6/6] Enviando check-in...
echo [%date% %time%] PASO6 CHECKIN >> "%LOG_FILE%"

REM VBScript checkin (usa Chrome fallback via FetchUrl, no se cuelga)
cscript //nologo "%~dp0sync-download.vbs" register >>"%LOG_FILE%" 2>&1
cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >>"%LOG_FILE%" 2>&1

REM Chrome headless checkin (rapido, TLS propio)
set CHROME_PATH2=
for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set CHROME_PATH2=%%~p
if "%CHROME_PATH2%"=="" where chrome.exe >nul 2>nul && set CHROME_PATH2=chrome.exe
if not "%CHROME_PATH2%"=="" (
    start /min "" "%CHROME_PATH2%" --headless --disable-gpu --no-sandbox "%SERVER_URL%/api/conera/register?name=%CONERA%"
    start /min "" "%CHROME_PATH2%" --headless --disable-gpu --no-sandbox "%SERVER_URL%/api/conera/checkin?name=%CONERA%&version=%VERSION%"
)
timeout /t 3 /nobreak >nul
echo  OK
echo [%date% %time%] PASO6 OK >> "%LOG_FILE%"

del "%ZIP_FILE%" "%TEMP%\dbf_version.txt" "%TEMP%\dbf_version2.txt" 2>nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul

echo.
echo =============================================
echo   Actualizado: %VERSION%
echo   Hora: %date% %time%
echo =============================================
echo.

REM ===== CREAR TAREA PROGRAMADA =====
echo.
echo  Creando tarea programada para check-in cada 5 minutos...
echo  (La ventana se cerrara, la tarea corre en segundo plano)
echo.
echo [%date% %time%] Creando schtask... >> "%LOG_FILE%"

set TASK_NAME=DBF_Sync_%CONERA%
set TASK_SCRIPT="%~dp0sync-download.vbs"

REM Eliminar tarea anterior si existe
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>>"%LOG_FILE%"

REM Crear tarea cada 5 minutos
schtasks /create /tn "%TASK_NAME%" /tr "cscript //nologo \"%TASK_SCRIPT%\" checkin \"%VERSION%\"" /sc minute /mo 5 /f >>"%LOG_FILE%" 2>&1

if %errorlevel% equ 0 (
    echo  Tarea creada: %TASK_NAME% (cada 5 min)
    echo [%date% %time%] schtask OK >> "%LOG_FILE%"
) else (
    echo  [!] No se pudo crear tarea programada
    echo [%date% %time%] schtask ERROR >> "%LOG_FILE%"
    pause
)

echo.
echo =============================================
echo   Actualizado: %VERSION%
echo   Check-in automatico cada 5 minutos
echo   Tarea: %TASK_NAME%
echo =============================================
echo.
echo  Log: %LOG_FILE%
echo.
echo  Presione Enter para cerrar...
pause >nul
exit /b 0
