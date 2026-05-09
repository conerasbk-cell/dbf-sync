@echo off
setlocal enabledelayedexpansion

title DBF Sync - %COMPUTERNAME%

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

REM ===== PASO 2: VERSION =====
echo [2/6] Obteniendo version del servidor...
set VERSION=
cscript //nologo "%~dp0sync-download.vbs" version > "%TEMP%\dbf_version.txt" 2>nul
set /p VERSION=<"%TEMP%\dbf_version.txt"

if "%VERSION%"=="" (
    echo  Intentando PowerShell...
    powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $r = $w.DownloadString('%SERVER_URL%/api/version'); " ^
"$m = [regex]::Match($r, '\"\"version\"\":\s*\"\"([^\"]+)\"\"'); if($m.Success){$m.Groups[1].Value}else{''} " ^
"} catch { '' }" > "%TEMP%\dbf_version2.txt" 2>nul
    set /p VERSION=<"%TEMP%\dbf_version2.txt"
)

if "%VERSION%"=="" (
    echo  ERROR: No se pudo conectar al servidor
    echo.
    echo  Verifique internet y que el servidor este desplegado
    echo  %SERVER_URL%/api/version
    echo.
    echo  Cerrando en 10 segundos...
    timeout /t 10 /nobreak >nul
    exit /b 1
)
echo  OK: %VERSION%

REM ===== PASO 3: COMPARAR =====
echo [3/6] Verificando version local...
set LOCAL_VER=
if exist "%VERSION_FILE%" (
    set /p LOCAL_VER=<"%VERSION_FILE%"
)
if "%LOCAL_VER%"=="%VERSION%" (
    echo  Ya actualizado: %VERSION%
    goto checkin_and_loop
)
echo  Local: %LOCAL_VER% ^| Servidor: %VERSION%

REM ===== PASO 4: DESCARGAR =====
echo [4/6] Descargando...
set ZIP_FILE=%TEMP%\dbf_sync_%VERSION%.zip
set DOWNLOADS_DIR=%USERPROFILE%\Downloads
del "%ZIP_FILE%" 2>nul

REM Metodos silenciosos (sin ventanas):
echo   - bitsadmin...
bitsadmin /transfer dbfsync /download /priority high "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto extraer

echo   - certutil...
certutil -urlcache -split -f "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto extraer

echo   - PowerShell...
powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $w.DownloadFile('%SERVER_URL%/api/download/%VERSION%', '%ZIP_FILE%') } catch {}" >nul 2>nul
if exist "%ZIP_FILE%" goto extraer

REM Buscar Chrome por rutas comunes
set CHROME_PATH=
for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set CHROME_PATH=%%~p
if "%CHROME_PATH%"=="" where chrome.exe >nul 2>nul && set CHROME_PATH=chrome.exe

if not "%CHROME_PATH%"=="" (
    echo   - Chrome (perfil temporal)...

    REM Crear perfil temporal de Chrome con descarga automatica
    set CHROME_TEMP=%TEMP%\chrome_dl_%VERSION%
    set CHROME_DL_DIR=%CHROME_TEMP%\downloads
    set CHROME_UD_DIR=%CHROME_TEMP%\user-data
    if exist "%CHROME_TEMP%" rmdir /s /q "%CHROME_TEMP%" 2>nul
    md "%CHROME_DL_DIR%" 2>nul
    md "%CHROME_UD_DIR%\Default" 2>nul

    REM Preferences: descarga automatica sin preguntar
    powershell -ExecutionPolicy Bypass -Command ^
"$d='%CHROME_DL_DIR:\=\\'; " ^
"$j='{\"download\":{\"default_directory\":\"'+$d+'\",\"prompt_for_download\":false,\"directory_upgrade\":true},\"safebrowsing\":{\"enabled\":false},\"browser\":{\"check_default_browser\":false}}'; " ^
"[System.IO.File]::WriteAllText('%CHROME_UD_DIR%\Default\Preferences',$j)" >nul 2>nul

    taskkill /f /im chrome.exe >nul 2>nul
    timeout /t 1 /nobreak >nul
    start /min "" "%CHROME_PATH%" --user-data-dir="%CHROME_UD_DIR%" --no-sandbox --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --disable-features=DownloadBubble,InsecureDownloadWarnings --safebrowsing-disable-download-protection --new-window "%SERVER_URL%/api/download/%VERSION%" >nul 2>nul
    timeout /t 20 /nobreak >nul
    taskkill /f /im chrome.exe >nul 2>nul
    timeout /t 1 /nobreak >nul

    REM Buscar en el directorio de descargas configurado
    for /r "%CHROME_DL_DIR%" %%f in (*.zip) do (
        copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
    )
    REM Si no aparece, buscar en Downloads normal
    if not exist "%ZIP_FILE%" (
        for /r "%DOWNLOADS_DIR%" %%f in (*%VERSION%*.zip) do (
            copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
            del "%%f" 2>nul
        )
    )
    if exist "%ZIP_FILE%" goto extraer
)

REM Buscar Firefox
set FIREFOX_PATH=
for %%p in ("%PROGRAMFILES%\Mozilla Firefox\firefox.exe" "%PROGRAMFILES(X86)%\Mozilla Firefox\firefox.exe") do if exist "%%~p" set FIREFOX_PATH=%%~p
if "%FIREFOX_PATH%"=="" where firefox.exe >nul 2>nul && set FIREFOX_PATH=firefox.exe

if not "%FIREFOX_PATH%"=="" (
    echo   - Firefox (visible)...
    echo.
    echo  *****************************************************
    echo   Se abrira Firefox para descargar el ZIP.
    echo   Guarde el archivo, cierre Firefox y presione Enter.
    echo  *****************************************************
    echo.
    taskkill /f /im firefox.exe >nul 2>nul
    timeout /t 1 /nobreak >nul
    start "" "%FIREFOX_PATH%" --new-window "%SERVER_URL%/api/download/%VERSION%"
    pause
    taskkill /f /im firefox.exe >nul 2>nul
    for /r "%DOWNLOADS_DIR%" %%f in (*%VERSION%*.zip) do (
        copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
        del "%%f" 2>nul
    )
    if exist "%ZIP_FILE%" goto extraer
)

REM Nada funciono
echo.
echo  ERROR: No se pudo descargar automaticamente.
echo.
echo  Abra Chrome y navegue a:
echo  %SERVER_URL%/api/download/%VERSION%
echo.
echo  Guarde el archivo ZIP en:
echo  %ZIP_FILE%
echo.
echo  Luego presione Enter para continuar...
pause
if not exist "%ZIP_FILE%" (
    echo  Continuando sin actualizar...
    goto checkin_and_loop
)

:extraer
echo  ZIP descargado OK

REM ===== PASO 5: EXTRAER =====
echo [5/6] Extrayendo archivos...
set EXTRACT_DIR=%TEMP%\dbf_sync_extract
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%" 2>nul

powershell -ExecutionPolicy Bypass -Command ^
"try { $s = New-Object -ComObject Shell.Application; " ^
"$z = $s.NameSpace('%ZIP_FILE%'); $d = $s.NameSpace('%EXTRACT_DIR%'); $d.CopyHere($z.Items(), 20) } catch {}" >nul 2>nul

echo  Copiando a DATA y NEWDATA...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" 2>nul
if not exist "%NEWDATA_DIR%" mkdir "%NEWDATA_DIR%" 2>nul

for /r "%EXTRACT_DIR%" %%f in (*.dbf) do (
    copy /y "%%f" "%DATA_DIR%\" >nul 2>nul
    copy /y "%%f" "%NEWDATA_DIR%\" >nul 2>nul
)

echo %VERSION% > "%VERSION_FILE%"
echo  OK

REM ===== CHECK-IN =====
:checkin_and_loop
echo [6/6] Enviando check-in...

REM Intentar VBScript (multi-metodo COM)
cscript //nologo "%~dp0sync-download.vbs" register >nul 2>nul
cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >nul 2>nul

REM Fallback PowerShell (.NET con TLS 1.2)
powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $w.DownloadString('%SERVER_URL%/api/conera/register?name=%CONERA%') } catch {}; " ^
"try { $w.DownloadString('%SERVER_URL%/api/conera/checkin?name=%CONERA%&version=%VERSION%') } catch {}" >nul 2>nul

REM Buscar Chrome para check-in
set CHROME_PATH2=
for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set CHROME_PATH2=%%~p
if "%CHROME_PATH2%"=="" where chrome.exe >nul 2>nul && set CHROME_PATH2=chrome.exe
if not "%CHROME_PATH2%"=="" (
    start /min "" "%CHROME_PATH2%" --headless --disable-gpu --no-sandbox "%SERVER_URL%/api/conera/register?name=%CONERA%" >nul 2>nul
    start /min "" "%CHROME_PATH2%" --headless --disable-gpu --no-sandbox "%SERVER_URL%/api/conera/checkin?name=%CONERA%&version=%VERSION%" >nul 2>nul
)
timeout /t 3 /nobreak >nul
echo  OK

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

set TASK_NAME=DBF_Sync_%CONERA%
set TASK_SCRIPT="%~dp0sync-download.vbs"

REM Eliminar tarea anterior si existe
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>nul

REM Crear tarea cada 5 minutos
schtasks /create /tn "%TASK_NAME%" /tr "cscript //nologo \"%TASK_SCRIPT%\" checkin \"%VERSION%\"" /sc minute /mo 5 /f >nul 2>nul

if %errorlevel% equ 0 (
    echo  Tarea creada: %TASK_NAME% (cada 5 min)
) else (
    echo  [!] No se pudo crear tarea programada
    echo  El check-in automatico no estara activo
    pause
)

echo.
echo =============================================
echo   Actualizado: %VERSION%
echo   Check-in automatico cada 5 minutos
echo   Tarea: %TASK_NAME%
echo =============================================
echo.
echo  Presione Enter para cerrar...
pause >nul
exit /b 0
