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

REM ===== MENU DE NAVEGADOR =====
:MENU
cls
echo =============================================
echo   Seleccione el navegador a usar:
echo =============================================
echo.
echo   1. Google Chrome
echo   2. Mozilla Firefox
echo   3. Automatico (prueba todo)
echo.
set BROWSER=
set /p BROWSER="Opcion (1-3): "
if "%BROWSER%"=="1" goto browser_chrome
if "%BROWSER%"=="2" goto browser_firefox
if "%BROWSER%"=="3" goto browser_auto
goto MENU

:browser_chrome
echo.
echo  [Chrome] Verificando que este instalado...
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" >nul 2>nul
if errorlevel 1 (
    echo  ERROR: Chrome no encontrado en el registro
    echo  Presione Enter para volver al menu...
    pause >nul
    goto MENU
)
set BROWSER_MODE=chrome
goto step1

:browser_firefox
echo.
echo  [Firefox] Verificando que este instalado...
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe" >nul 2>nul
if errorlevel 1 (
    echo  ERROR: Firefox no encontrado en el registro
    echo  Presione Enter para volver al menu...
    pause >nul
    goto MENU
)
set BROWSER_MODE=firefox
goto step1

:browser_auto
set BROWSER_MODE=auto
goto step1

REM ===== PASO 1: TLS =====
:step1
cls
echo =============================================
echo   DBF Sync - %CONERA%
echo   Modo: %BROWSER_MODE%
echo =============================================
echo.
echo [1/6] Activando TLS 1.2 en el sistema...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul
echo  OK

goto step2_%BROWSER_MODE%

REM ===== PASO 2: VERSION =====
:step2_auto
:step2_chrome
:step2_firefox
echo [2/6] Obteniendo version del servidor...
set VERSION=
cscript //nologo "%~dp0sync-download.vbs" version > "%TEMP%\dbf_version.txt" 2>nul
set /p VERSION=<"%TEMP%\dbf_version.txt"

if "%VERSION%"=="" (
    powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $r = $w.DownloadString('%SERVER_URL%/api/version'); " ^
"$m = [regex]::Match($r, '\"\"version\"\":\s*\"\"([^\"]+)\"\"'); if($m.Success){$m.Groups[1].Value}else{''} " ^
"} catch { '' }" > "%TEMP%\dbf_version2.txt" 2>nul
    set /p VERSION=<"%TEMP%\dbf_version2.txt"
)

if "%VERSION%"=="" (
    cls
    echo =============================================
    echo   ERROR: No se pudo conectar al servidor
    echo =============================================
    echo.
    echo  Verifique que la conera tenga acceso a internet.
    echo  Si el navegador funciona, puede descargar manualmente:
    echo.
    echo  %SERVER_URL%/api/download
    echo.
    pause
    exit /b 1
)
echo  Version encontrada: %VERSION%

REM ===== PASO 3: VERSION LOCAL =====
echo [3/6] Verificando version local...
set LOCAL_VER=
if exist "%VERSION_FILE%" (
    set /p LOCAL_VER=<"%VERSION_FILE%"
)
if "%LOCAL_VER%"=="%VERSION%" (
    echo  Ya esta actualizado (version: %VERSION%)
    echo.
    cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >nul 2>nul
    echo  Check-in enviado
    echo.
    echo =============================================
    echo   Conera actualizada al %date% %time%
    echo =============================================
    pause
    exit /b 0
)
echo  Local: %LOCAL_VER% ^| Servidor: %VERSION%

REM ===== PASO 4: DESCARGAR =====
echo [4/6] Descargando actualizacion...
set ZIP_FILE=%TEMP%\dbf_sync_%VERSION%.zip
del "%ZIP_FILE%" 2>nul

if "%BROWSER_MODE%"=="chrome" goto dl_chrome
if "%BROWSER_MODE%"=="firefox" goto dl_firefox
goto dl_auto

:dl_auto
echo  Intentando bitsadmin...
bitsadmin /transfer dbfsync /download /priority high "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok
echo  Intentando certutil...
certutil -urlcache -split -f "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok
echo  Intentando PowerShell...
powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $w.DownloadFile('%SERVER_URL%/api/download/%VERSION%', '%ZIP_FILE%') } catch {}" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok
:dl_chrome
echo  Intentando Chrome...
for %%X in (chrome.exe) do (set FOUND=%%~$PATH:X)
if not "!FOUND!"=="" (
    start /wait "" chrome --headless --disable-gpu --no-sandbox "%SERVER_URL%/api/download/%VERSION%" >nul 2>nul
    timeout /t 5 /nobreak >nul
    for /r "%USERPROFILE%\Downloads" %%f in (*%VERSION%*.zip) do (
        copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
        if exist "!ZIP_FILE!" goto download_ok
    )
)
:dl_firefox
echo  Intentando Firefox...
for %%X in (firefox.exe) do (set FOUND=%%~$PATH:X)
if not "!FOUND!"=="" (
    start /wait "" firefox --headless "%SERVER_URL%/api/download/%VERSION%" >nul 2>nul
    timeout /t 5 /nobreak >nul
    for /r "%USERPROFILE%\Downloads" %%f in (*%VERSION%*.zip) do (
        copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
        if exist "!ZIP_FILE!" goto download_ok
    )
)
echo  Intentando VBScript...
cscript //nologo "%~dp0sync-download.vbs" download "%VERSION%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok

cls
echo =============================================
echo   ERROR: No se pudo descargar
echo =============================================
echo.
echo  Abra el navegador manualmente y pegue esta URL:
echo.
echo  %SERVER_URL%/api/download/%VERSION%
echo.
echo  Luego copie el ZIP a esta carpeta y ejecute de nuevo
echo.
pause
exit /b 1

:download_ok
echo  Descargado OK

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
echo  Archivos copiados OK

REM ===== PASO 6: CHECK-IN =====
echo [6/6] Enviando check-in al servidor...
cscript //nologo "%~dp0sync-download.vbs" register >nul 2>nul
cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >nul 2>nul
echo  OK

del "%ZIP_FILE%" 2>nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul
del "%TEMP%\dbf_version.txt" "%TEMP%\dbf_version2.txt" 2>nul

echo.
echo =============================================
echo   ACTUALIZACION COMPLETADA
echo   Version: %VERSION%
echo   Fecha: %date% %time%
echo =============================================
pause
