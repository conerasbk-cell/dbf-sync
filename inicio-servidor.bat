@echo off
title DBF SYNC - Servidor + Tunnel

cls
echo =====================================================
echo   DBF SYNC SERVER v1.0
echo =====================================================
echo.
echo  [1/3] Iniciando servidor Flask en puerto 8080...
echo.
start /B "" "%~dp0dbf-sync-server.exe"
timeout /t 2 /nobreak >nul

echo  [2/3] Iniciando tunnel Cloudflare...
echo.
echo  Esperando conexion...
echo.

"%~dp0cloudflared.exe" tunnel --protocol http2 --url http://localhost:8080

pause
