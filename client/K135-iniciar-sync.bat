@echo off
title DBF Sync - K135
echo ====================================
echo   DBF Sync - Conera K135
echo   Consultando cada 5 minutos...
echo   Cierra esta ventana para detener
echo ====================================
cd /d "%~dp0"
wscript.exe "dbf-sync-client-xp.vbs"
pause
