@echo off
setlocal enabledelayedexpansion

set SILENT=0
if /i "%1"=="/silent" set SILENT=1

if %SILENT% equ 1 (
    set LOG_FILE=%TEMP%\dbf_sync_%COMPUTERNAME%.log
    echo [%date% %time%] INICIO SILENT > "%LOG_FILE%"
    goto :SILENT_START
)

title DBF Sync - %COMPUTERNAME%
set LOG_FILE=%TEMP%\dbf_sync_%COMPUTERNAME%.log
echo [%date% %time%] INICIO > "%LOG_FILE%"

echo =============================================
echo   DBF Sync Conera - Actualizacion Manual
echo =============================================
echo.

:SILENT_START

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
echo [1/7] Activando TLS 1.2...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>nul
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v Enabled /t REG_DWORD /d 1 /f >nul 2>nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v DisabledByDefault /t REG_DWORD /d 0 /f >nul 2>nul
echo  OK
echo [%date% %time%] PASO1 TLS OK >> "%LOG_FILE%"

REM ===== PASO 2: REGISTRO (siempre ejecutar para que aparezca en el panel) =====
echo [2/7] Registrando conera en el servidor...
echo [%date% %time%] PASO2 REGISTRO >> "%LOG_FILE%"

REM Generar VBS auxiliar para registro via COM objects (WinHttp/ServerXMLHTTP)
> "%TEMP%\dbf_register.vbs" echo Option Explicit
>>"%TEMP%\dbf_register.vbs" echo Dim url
>>"%TEMP%\dbf_register.vbs" echo url = WScript.Arguments(0)
>>"%TEMP%\dbf_register.vbs" echo Dim methods, i, obj
>>"%TEMP%\dbf_register.vbs" echo methods = Array("WinHttp.WinHttpRequest.5.1", "MSXML2.ServerXMLHTTP.6.0", "MSXML2.ServerXMLHTTP.3.0", "MSXML2.XMLHTTP.6.0", "MSXML2.XMLHTTP.3.0", "Microsoft.XMLHTTP")
>>"%TEMP%\dbf_register.vbs" echo On Error Resume Next
>>"%TEMP%\dbf_register.vbs" echo For i = 0 To UBound(methods)
>>"%TEMP%\dbf_register.vbs" echo     Set obj = Nothing
>>"%TEMP%\dbf_register.vbs" echo     Set obj = CreateObject(methods(i))
>>"%TEMP%\dbf_register.vbs" echo     If Err.Number = 0 Then
>>"%TEMP%\dbf_register.vbs" echo         If InStr(methods(i), "WinHttp") > 0 Then obj.Option(9) = 4096
>>"%TEMP%\dbf_register.vbs" echo         obj.Open "GET", url, False
>>"%TEMP%\dbf_register.vbs" echo         obj.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
>>"%TEMP%\dbf_register.vbs" echo         obj.Send
>>"%TEMP%\dbf_register.vbs" echo         If Err.Number = 0 And obj.Status = 200 Then WScript.Quit 0
>>"%TEMP%\dbf_register.vbs" echo     End If
>>"%TEMP%\dbf_register.vbs" echo     Err.Clear
>>"%TEMP%\dbf_register.vbs" echo Next
>>"%TEMP%\dbf_register.vbs" echo WScript.Quit 1

echo   - PowerShell...
powershell -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; (New-Object Net.WebClient).DownloadString('%SERVER_URL%/api/conera/register?name=%CONERA%') | Out-Null" 2>>"%LOG_FILE%"
if %errorlevel% equ 0 (
    echo  OK (PowerShell)
    echo [%date% %time%] REGISTRO PowerShell OK >> "%LOG_FILE%"
) else (
    echo   - COM objects...
    cscript //nologo "%TEMP%\dbf_register.vbs" "%SERVER_URL%/api/conera/register?name=%CONERA%" >>"%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        echo  OK (COM)
        echo [%date% %time%] REGISTRO COM OK >> "%LOG_FILE%"
    ) else (
        echo  [!] No se pudo registrar
        echo [%date% %time%] REGISTRO FALLIDO >> "%LOG_FILE%"
    )
)

REM ===== PASO 3: VERSION =====
echo [3/7] Obteniendo version del servidor...
set VERSION=

REM VBScript auxiliar para extraer version del JSON
> "%TEMP%\getver.vbs" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%TEMP%\getver.vbs" echo data = fso.OpenTextFile(WScript.Arguments(0)).ReadAll()
>> "%TEMP%\getver.vbs" echo p = InStr(data, """version"":""")
>> "%TEMP%\getver.vbs" echo If p ^> 0 Then
>> "%TEMP%\getver.vbs" echo     s = Mid(data, p + 11)
>> "%TEMP%\getver.vbs" echo     q = InStr(s, """")
>> "%TEMP%\getver.vbs" echo     If q ^> 0 Then WScript.Echo Left(s, q - 1)
>> "%TEMP%\getver.vbs" echo End If

REM VBScript que obtiene version via COM objects (WinHttp/ServerXMLHTTP) directamente
> "%TEMP%\getver_com.vbs" echo Option Explicit
>>"%TEMP%\getver_com.vbs" echo Dim url, methods, i, obj, result
>>"%TEMP%\getver_com.vbs" echo url = WScript.Arguments(0)
>>"%TEMP%\getver_com.vbs" echo methods = Array("WinHttp.WinHttpRequest.5.1", "MSXML2.ServerXMLHTTP.6.0", "MSXML2.ServerXMLHTTP.3.0", "MSXML2.XMLHTTP.6.0", "MSXML2.XMLHTTP.3.0", "Microsoft.XMLHTTP")
>>"%TEMP%\getver_com.vbs" echo On Error Resume Next
>>"%TEMP%\getver_com.vbs" echo For i = 0 To UBound(methods)
>>"%TEMP%\getver_com.vbs" echo     Set obj = Nothing
>>"%TEMP%\getver_com.vbs" echo     Set obj = CreateObject(methods(i))
>>"%TEMP%\getver_com.vbs" echo     If Err.Number = 0 Then
>>"%TEMP%\getver_com.vbs" echo         If InStr(methods(i), "WinHttp") > 0 Then obj.Option(9) = 4096
>>"%TEMP%\getver_com.vbs" echo         obj.Open "GET", url, False
>>"%TEMP%\getver_com.vbs" echo         obj.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
>>"%TEMP%\getver_com.vbs" echo         obj.Send
>>"%TEMP%\getver_com.vbs" echo         If Err.Number = 0 And obj.Status = 200 Then
>>"%TEMP%\getver_com.vbs" echo             result = obj.ResponseText
>>"%TEMP%\getver_com.vbs" echo             Dim p, s, q
>>"%TEMP%\getver_com.vbs" echo             p = InStr(result, """version"":""")
>>"%TEMP%\getver_com.vbs" echo             If p ^> 0 Then
>>"%TEMP%\getver_com.vbs" echo                 s = Mid(result, p + 11)
>>"%TEMP%\getver_com.vbs" echo                 q = InStr(s, """")
>>"%TEMP%\getver_com.vbs" echo                 If q ^> 0 Then WScript.Echo Left(s, q - 1)
>>"%TEMP%\getver_com.vbs" echo             End If
>>"%TEMP%\getver_com.vbs" echo             WScript.Quit 0
>>"%TEMP%\getver_com.vbs" echo         End If
>>"%TEMP%\getver_com.vbs" echo     End If
>>"%TEMP%\getver_com.vbs" echo     Err.Clear
>>"%TEMP%\getver_com.vbs" echo Next
>>"%TEMP%\getver_com.vbs" echo WScript.Quit 1

REM METODO 1: COM objects (WinHttp/ServerXMLHTTP - funcionaban antes en K124)
echo   COM objects...
for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver_com.vbs" "%SERVER_URL%/api/version" 2^>nul') do set "VERSION=%%v"
echo [%date% %time%] COM VERSION: %VERSION% >> "%LOG_FILE%"

REM METODO 2: bitsadmin (WinHTTP con TLS 1.2)
if "%VERSION%"=="" (
    echo   bitsadmin...
    bitsadmin /transfer dbfsyncver /download /priority high "%SERVER_URL%/api/version" "%TEMP%\dbf_version.txt" >nul 2>nul
    for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver.vbs" "%TEMP%\dbf_version.txt" 2^>nul') do set "VERSION=%%v"
)

if "%VERSION%"=="" (
    echo  Intentando certutil...
    certutil -urlcache -split -f "%SERVER_URL%/api/version" "%TEMP%\dbf_version2.txt" >nul 2>nul
    for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver.vbs" "%TEMP%\dbf_version2.txt" 2^>nul') do set "VERSION=%%v"
)

if "%VERSION%"=="" (
    echo  Intentando PowerShell...
    powershell -ExecutionPolicy Bypass -Command ^
"try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " ^
"try { $w = New-Object Net.WebClient; $r = $w.DownloadString('%SERVER_URL%/api/version'); " ^
"$m = [regex]::Match($r, '\"\"version\"\":\s*\"\"([^\"]+)\"\"'); if($m.Success){$m.Groups[1].Value}else{''} " ^
"} catch { '' }" > "%TEMP%\dbf_version3.txt" 2>>"%LOG_FILE%"
    set /p VERSION=<"%TEMP%\dbf_version3.txt"
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
echo [%date% %time%] PASO3 VERSION: %VERSION% >> "%LOG_FILE%"

REM ===== PASO 4: COMPARAR =====
echo [4/7] Verificando version local...
set LOCAL_VER=
if exist "%VERSION_FILE%" (
    set /p LOCAL_VER=<"%VERSION_FILE%"
)
if "%LOCAL_VER%"=="%VERSION%" (
    echo  Ya actualizado: %VERSION%
    echo [%date% %time%] PASO4 Ya actualizado >> "%LOG_FILE%"
    goto checkin_and_loop
)
echo  Local: %LOCAL_VER% ^| Servidor: %VERSION%
echo [%date% %time%] PASO4 Local: %LOCAL_VER% Servidor: %VERSION% >> "%LOG_FILE%"

REM ===== PASO 5: DESCARGAR =====
echo [5/7] Descargando...
title DBF Sync - %CONERA% - descargando...
set ZIP_FILE=%TEMP%\dbf_sync_%VERSION%.zip
set DOWNLOADS_DIR=%USERPROFILE%\Downloads
del "%ZIP_FILE%" 2>nul
echo [%date% %time%] PASO5 INICIO >> "%LOG_FILE%"

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
if %SILENT% equ 1 (
    echo  En modo automatico, continuando sin actualizar...
    echo [%date% %time%] ERROR descarga en modo silent >> "%LOG_FILE%"
    goto checkin_and_loop
)
echo  Guarde el archivo en %ZIP_FILE%, luego presione Enter...
pause
if not exist "%ZIP_FILE%" (
    echo  Continuando sin actualizar...
    goto checkin_and_loop
)

:extraer
echo  ZIP descargado OK
echo [%date% %time%] PASO5 DESCARGA OK >> "%LOG_FILE%"

REM ===== PASO 6: EXTRAER =====
echo [6/7] Extrayendo archivos...
echo [%date% %time%] PASO6 EXTRACCION >> "%LOG_FILE%"
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
echo [%date% %time%] PASO6 OK >> "%LOG_FILE%"
echo  OK

REM ===== CHECK-IN =====
:checkin_and_loop
echo [7/7] Enviando check-in...
echo [%date% %time%] PASO7 CHECKIN >> "%LOG_FILE%"

REM Check-in via PowerShell
echo   - PowerShell...
powershell -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; (New-Object Net.WebClient).DownloadString('%SERVER_URL%/api/conera/checkin?name=%CONERA%&version=%VERSION%') | Out-Null" 2>>"%LOG_FILE%"
if %errorlevel% equ 0 (
    echo  OK
    echo [%date% %time%] CHECKIN PowerShell OK >> "%LOG_FILE%"
) else (
    echo   - COM objects...
    cscript //nologo "%TEMP%\dbf_register.vbs" "%SERVER_URL%/api/conera/checkin?name=%CONERA%&version=%VERSION%" >>"%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        echo  OK (COM)
        echo [%date% %time%] CHECKIN COM OK >> "%LOG_FILE%"
    ) else (
        echo  [!] Check-in fallo
        echo [%date% %time%] CHECKIN FALLIDO >> "%LOG_FILE%"
    )
)

if defined ZIP_FILE del "%ZIP_FILE%" 2>nul
del "%TEMP%\dbf_version.txt" "%TEMP%\dbf_version2.txt" "%TEMP%\dbf_version3.txt" 2>nul
del "%TEMP%\getver.vbs" "%TEMP%\getver_com.vbs" "%TEMP%\dbf_register.vbs" 2>nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul

echo.
echo =============================================
echo   Actualizado: %VERSION%
echo   Hora: %date% %time%
echo =============================================
echo.

REM En modo silent, no recrear la tarea (ya existe desde la ejecucion manual)
if %SILENT% equ 1 (
    echo [%date% %time%] SILENT: tarea ya existe, saltando >> "%LOG_FILE%"
    goto skip_schtasks
)

REM ===== CREAR TAREA PROGRAMADA =====
echo.
echo  Creando tarea programada para check-in cada 5 minutos...
echo  (La ventana se cerrara, la tarea corre en segundo plano)
echo.
echo [%date% %time%] Creando schtask... >> "%LOG_FILE%"

set TASK_NAME=DBF_Sync_%CONERA%
set TASK_WRAPPER=%TEMP%\dbf_sync_%CONERA%_checkin.bat

REM Crear wrapper batch que ejecuta sync-conera.bat /silent (ciclo completo)
>"%TASK_WRAPPER%" echo @echo off
>>"%TASK_WRAPPER%" echo @"%~dp0sync-conera.bat" /silent
>>"%TASK_WRAPPER%" echo exit /b 0

REM Eliminar tarea anterior si existe
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>>"%LOG_FILE%"

REM Crear tarea cada 5 minutos (ejecuta el ciclo completo: version, descarga, check-in)
schtasks /create /tn "%TASK_NAME%" /tr "%TASK_WRAPPER%" /sc minute /mo 5 /f >>"%LOG_FILE%" 2>&1

if %errorlevel% equ 0 (
    echo  Tarea creada: %TASK_NAME% (cada 5 min)
    echo [%date% %time%] schtask OK >> "%LOG_FILE%"
) else (
    echo  [!] No se pudo crear tarea programada
    echo [%date% %time%] schtask ERROR >> "%LOG_FILE%"
    if %SILENT% equ 1 (
        echo [%date% %time%] schtask ERROR en modo silent >> "%LOG_FILE%"
    ) else (
        pause
    )
)

:skip_schtasks
echo.
echo =============================================
echo   Actualizado: %VERSION%
echo   Hora: %date% %time%
echo =============================================
echo.
echo  Log: %LOG_FILE%
echo.
if %SILENT% equ 1 exit /b 0
echo  Presione Enter para cerrar...
pause >nul
exit /b 0
