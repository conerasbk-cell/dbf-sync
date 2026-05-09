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

REM Leer sync-config.txt
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

REM ===== STEP 1: INTENTAR ACTIVAR TLS 1.2 =====
echo [1/6] Activando TLS 1.2 en el sistema...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul
echo  OK

REM ===== STEP 2: OBTENER VERSION DEL SERVIDOR =====
echo [2/6] Obteniendo version del servidor...
set VERSION=

REM Method A: VBScript helper (IE COM object)
cscript //nologo "%~dp0sync-download.vbs" version > "%TEMP%\dbf_version.txt" 2>nul
set /p VERSION=<"%TEMP%\dbf_version.txt"

if "%VERSION%"=="" (
    REM Method B: PowerShell
    powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $r = $w.DownloadString('%SERVER_URL%/api/version'); " ^
"$m = [regex]::Match($r, '\"\"version\"\":\s*\"\"([^\"]+)\"\"'); if($m.Success){$m.Groups[1].Value}else{''} " ^
"} catch { '' }" > "%TEMP%\dbf_version2.txt" 2>nul
    set /p VERSION=<"%TEMP%\dbf_version2.txt"
)

if "%VERSION%"=="" (
    echo  ERROR: No se pudo conectar al servidor
    echo  NOTA: Si el navegador Chrome funciona en esta maquina,
    echo  abra manualmente la siguiente URL y descargue el archivo:
    echo  %SERVER_URL%/api/download
    pause
    exit /b 1
)
echo  Version encontrada: %VERSION%

REM ===== STEP 3: VERIFICAR VERSION LOCAL =====
echo [3/6] Verificando version local...
set LOCAL_VER=
if exist "%VERSION_FILE%" (
    set /p LOCAL_VER=<"%VERSION_FILE%"
)
if "%LOCAL_VER%"=="%VERSION%" (
    echo  Ya esta actualizado (version: %VERSION%)
    echo.
    echo [5/6] Enviando check-in...
    cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >nul 2>nul
    echo  OK
    echo.
    echo =============================================
    echo   Conera actualizada al %date% %time%
    echo =============================================
    pause
    exit /b 0
)
echo  Local: %LOCAL_VER% ^| Servidor: %VERSION%

REM ===== STEP 4: DESCARGAR ZIP =====
echo [4/6] Descargando actualizacion...
set ZIP_FILE=%TEMP%\dbf_sync_%VERSION%.zip
del "%ZIP_FILE%" 2>nul

REM Method 1: bitsadmin
echo  Intentando bitsadmin...
bitsadmin /transfer dbfsync /download /priority high "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok

REM Method 2: certutil
echo  Intentando certutil...
certutil -urlcache -split -f "%SERVER_URL%/api/download/%VERSION%" "%ZIP_FILE%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok

REM Method 3: PowerShell
echo  Intentando PowerShell...
powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $w.DownloadFile('%SERVER_URL%/api/download/%VERSION%', '%ZIP_FILE%') } catch {}" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok

REM Method 4: VBScript (IE COM)
echo  Intentando Internet Explorer...
cscript //nologo "%~dp0sync-download.vbs" download "%VERSION%" >nul 2>nul
if exist "%ZIP_FILE%" goto download_ok

echo  ERROR: No se pudo descargar el archivo
echo.
echo  Intente descargar manualmente desde Chrome:
echo  %SERVER_URL%/api/download/%VERSION%
pause
exit /b 1

:download_ok
echo  Descargado OK

REM ===== STEP 5: EXTRAER Y COPIAR =====
echo [5/6] Extrayendo archivos...
set EXTRACT_DIR=%TEMP%\dbf_sync_extract
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%" 2>nul

REM Extraer ZIP con PowerShell (o VBScript)
powershell -ExecutionPolicy Bypass -Command ^
"try { $s = New-Object -ComObject Shell.Application; " ^
"$z = $s.NameSpace('%ZIP_FILE%'); $d = $s.NameSpace('%EXTRACT_DIR%'); $d.CopyHere($z.Items(), 20) } catch {}" >nul 2>nul

REM Copiar archivos .dbf
echo  Copiando a DATA y NEWDATA...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" 2>nul
if not exist "%NEWDATA_DIR%" mkdir "%NEWDATA_DIR%" 2>nul

for /r "%EXTRACT_DIR%" %%f in (*.dbf) do (
    copy /y "%%f" "%DATA_DIR%\" >nul 2>nul
    copy /y "%%f" "%NEWDATA_DIR%\" >nul 2>nul
)

REM Guardar version
echo %VERSION% > "%VERSION_FILE%"

echo  Archivos copiados OK

REM ===== STEP 6: REGISTRAR Y CHECK-IN =====
echo [6/6] Enviando check-in al servidor...
cscript //nologo "%~dp0sync-download.vbs" register >nul 2>nul
cscript //nologo "%~dp0sync-download.vbs" checkin "%VERSION%" >nul 2>nul
echo  OK

REM ===== LIMPIEZA =====
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
