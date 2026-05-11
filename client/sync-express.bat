@echo off
setlocal enabledelayedexpansion

title DBF Sync Express - %COMPUTERNAME%
set LOG_FILE=%TEMP%\dbf_express_%COMPUTERNAME%.log
echo [%date% %time%] INICIO > "%LOG_FILE%"

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

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f >nul 2>nul

REM ===== DETECTAR NAVEGADOR =====
set BROWSER=
set BROWSER_NAME=
set BROWSER_CHROME=0
set BROWSER_FIREFOX=0

for %%p in ("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe" "%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe" "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") do if exist "%%~p" set BROWSER=%%~p & set BROWSER_NAME=Chrome & set BROWSER_CHROME=1
if "%BROWSER%"=="" where chrome.exe >nul 2>nul && set BROWSER=chrome.exe & set BROWSER_NAME=Chrome & set BROWSER_CHROME=1

if "%BROWSER%"=="" (
    for %%p in ("%PROGRAMFILES%\Mozilla Firefox\firefox.exe" "%PROGRAMFILES(X86)%\Mozilla Firefox\firefox.exe") do if exist "%%~p" set BROWSER=%%~p & set BROWSER_NAME=Firefox & set BROWSER_FIREFOX=1
    if "!BROWSER!"=="" where firefox.exe >nul 2>nul && set BROWSER=firefox.exe & set BROWSER_NAME=Firefox & set BROWSER_FIREFOX=1
)

if "%BROWSER%"=="" (
    echo ERROR: No se encuentra Chrome ni Firefox
    pause
    exit /b 1
)

echo =============================================
echo   DBF Sync Express - %CONERA%
echo   Navegador: %BROWSER_NAME%
echo   Log: %LOG_FILE%
echo =============================================
echo.
echo [%date% %time%] INICIO: %CONERA% %BROWSER_NAME% >> "%LOG_FILE%"

REM ===== 1. VERSION =====
echo [1/3] Obteniendo version del servidor...

del "%TEMP%\dbf_ver.txt" 2>nul

if %BROWSER_CHROME% equ 1 (
    start /min "" "%BROWSER%" --headless --disable-gpu --no-sandbox --dump-dom "%SERVER_URL%/api/version" > "%TEMP%\dbf_ver.txt" 2>nul
) else (
    start /min "" "%BROWSER%" --headless --window-size 1,1 "%SERVER_URL%/api/version" > "%TEMP%\dbf_ver.txt" 2>nul
)

set WAIT_COUNT=0
:WAIT_VER
timeout /t 1 /nobreak >nul
set /a WAIT_COUNT+=1
set BROWSER_EXE=chrome.exe
if %BROWSER_FIREFOX% equ 1 set BROWSER_EXE=firefox.exe
tasklist /fi "imagename eq !BROWSER_EXE!" 2>nul | find /i "!BROWSER_EXE!" >nul
if not errorlevel 1 if !WAIT_COUNT! lss 30 goto WAIT_VER
taskkill /f /im !BROWSER_EXE! >nul 2>nul

REM === Extraer version con VBScript (busca "version":" en HTML/JSON) ===
> "%TEMP%\getver.vbs" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%TEMP%\getver.vbs" echo data = fso.OpenTextFile(WScript.Arguments(0)).ReadAll()
>> "%TEMP%\getver.vbs" echo p = InStr(data, """version"":""")
>> "%TEMP%\getver.vbs" echo If p ^> 0 Then
>> "%TEMP%\getver.vbs" echo     s = Mid(data, p + 11)
>> "%TEMP%\getver.vbs" echo     q = InStr(s, """")
>> "%TEMP%\getver.vbs" echo     If q ^> 0 Then WScript.Echo Left(s, q - 1)
>> "%TEMP%\getver.vbs" echo End If

for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver.vbs" "%TEMP%\dbf_ver.txt"') do set "VERSION=%%v"

if "%VERSION%"=="" (
    echo  Reintentando con bitsadmin...
    bitsadmin /transfer dbfver /download /priority high "%SERVER_URL%/api/version" "%TEMP%\dbf_ver2.txt" >nul 2>nul
    for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver.vbs" "%TEMP%\dbf_ver2.txt"') do set "VERSION=%%v"
)

if "%VERSION%"=="" (
    echo  Reintentando con certutil...
    certutil -urlcache -split -f "%SERVER_URL%/api/version" "%TEMP%\dbf_ver3.txt" >nul 2>nul
    for /f "delims=" %%v in ('cscript //nologo "%TEMP%\getver.vbs" "%TEMP%\dbf_ver3.txt"') do set "VERSION=%%v"
)

if "%VERSION%"=="" (
    echo ERROR: No se pudo conectar al servidor
    echo %SERVER_URL%/api/version
    echo.
    echo Revise que el servidor este desplegado en Render
    echo y que la conera tenga conexion a internet.
    pause
    exit /b 1
)
echo Version servidor: %VERSION%
echo [%date% %time%] VERSION: %VERSION% >> "%LOG_FILE%"

set LOCAL_VER=
if exist "%VERSION_FILE%" set /p LOCAL_VER=<"%VERSION_FILE%"
if "%LOCAL_VER%"=="%VERSION%" (
    echo Ya actualizado: %VERSION%
    echo [%date% %time%] YA ACTUALIZADO: %VERSION% >> "%LOG_FILE%"
    goto run_iberqs
)
echo Version local: %LOCAL_VER%
echo [%date% %time%] LOCAL: %LOCAL_VER% SERVIDOR: %VERSION% >> "%LOG_FILE%"
echo.

REM ===== 2. DOWNLOAD =====
echo [2/3] Descargando %VERSION%...

set ZIP_FILE=%TEMP%\dbf_%VERSION%.zip
set DOWNLOADS=%USERPROFILE%\Downloads
del "%ZIP_FILE%" 2>nul

if %BROWSER_CHROME% equ 1 (
    REM === Chrome temp profile ===
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
    start /min "" "%BROWSER%" --user-data-dir="!CHROME_UD_DIR!" --no-sandbox --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --disable-features=DownloadBubble,InsecureDownloadWarnings --safebrowsing-disable-download-protection --new-window "%SERVER_URL%/api/download/%VERSION%"
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
) else (
    REM === Firefox temp profile ===
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

    echo   Firefox (perfil temporal, sin ventanas)...
    taskkill /f /im firefox.exe >nul 2>nul
    timeout /t 1 /nobreak >nul
    start /min "" "%BROWSER%" --profile "!FX_PROFILE_DIR!" --no-remote --new-window "%SERVER_URL%/api/download/%VERSION%"
    timeout /t 20 /nobreak >nul
    taskkill /f /im firefox.exe >nul 2>nul
    timeout /t 1 /nobreak >nul

    for /f "delims=" %%f in ('dir /a-d /s /b "!FX_DL_DIR!\*.zip" 2^>nul') do copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
    if not exist "%ZIP_FILE%" (
        for /f "delims=" %%f in ('dir /a-d /s /b "%DOWNLOADS%\*%VERSION%*.zip" 2^>nul') do (
            copy /y "%%f" "%ZIP_FILE%" >nul 2>nul
            del "%%f" 2>nul
        )
    )
)

if not exist "%ZIP_FILE%" (
    echo [%date% %time%] ERROR: No se pudo descargar automaticamente >> "%LOG_FILE%"
    echo.
    echo No se pudo descargar automaticamente.
    echo Abra %BROWSER_NAME% y descargue:
    echo   %SERVER_URL%/api/download/%VERSION%
    echo Guarde el archivo y presione Enter para continuar...
    pause
    if not exist "%ZIP_FILE%" (
        echo Continuando sin actualizar...
        goto run_iberqs
    )
)
echo Zip descargado OK
echo [%date% %time%] DESCARGA OK >> "%LOG_FILE%"
echo.

REM ===== 3. EXTRACT =====
echo [3/3] Extrayendo archivos...
echo [%date% %time%] EXTRACCION >> "%LOG_FILE%"

set EXTRACT_DIR=%TEMP%\dbf_extract
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%" 2>nul

REM Extraer ZIP (Expand-Archive PS5+, fallback Shell.Application)
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) { Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force } else { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%EXTRACT_DIR%') } } catch { try { $s = New-Object -ComObject Shell.Application; $z = $s.NameSpace('%ZIP_FILE%'); $d = $s.NameSpace('%EXTRACT_DIR%'); $d.CopyHere($z.Items(), 20) } catch {} }"

REM Quitar Zone.Identifier (archivos bloqueados por Windows)
powershell -ExecutionPolicy Bypass -Command "Get-ChildItem '%EXTRACT_DIR%' -Recurse -Force | ForEach-Object { Remove-Item ($_.FullName + ':Zone.Identifier') -ErrorAction SilentlyContinue }" >>"%LOG_FILE%" 2>&1

if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" 2>nul
if not exist "%NEWDATA_DIR%" mkdir "%NEWDATA_DIR%" 2>nul

for /r "%EXTRACT_DIR%" %%f in (*.dbf) do (
    copy /y "%%f" "%DATA_DIR%\" >nul 2>nul
    copy /y "%%f" "%NEWDATA_DIR%\" >nul 2>nul
)

echo %VERSION% > "%VERSION_FILE%"
echo Actualizado a %VERSION%
echo [%date% %time%] ACTUALIZADO: %VERSION% >> "%LOG_FILE%"

del "%ZIP_FILE%" 2>nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul
if defined CHROME_TEMP rmdir /s /q "!CHROME_TEMP!" 2>nul
if defined FX_TEMP rmdir /s /q "!FX_TEMP!" 2>nul

echo.

REM ===== RUN IBERQS =====
:run_iberqs
if exist "%IBERQS%" (
    echo Ejecutando Iberqs.exe...
    echo [%date% %time%] IBERQS: %IBERQS% >> "%LOG_FILE%"
    start "" "%IBERQS%"
) else (
    echo Aviso: No se encuentra %IBERQS%
    echo [%date% %time%] IBERQS NO ENCONTRADO: %IBERQS% >> "%LOG_FILE%"
)

echo.
echo Presione Enter para cerrar...
pause >nul
exit /b 0
