@echo off
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" /v DefaultSecureProtocols /t REG_DWORD /d 0xA00 /f
if %errorlevel% equ 0 (
    echo TLS 1.2 habilitado correctamente
) else (
    echo ERROR: No se pudo modificar el registro
    echo Ejecute este archivo como ADMINISTRADOR
)
pause
