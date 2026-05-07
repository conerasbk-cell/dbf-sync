' DBF Sync Client for Windows XP/7/10
' Silencioso - solo muestra popup en actualizacion manual

Option Explicit

Const CHECK_INTERVAL = 300 ' 5 minutos
Dim strServerUrl, strConeraName, strDataDir, strNewDataDir, strVersionFile, strLogFile
Dim strForceAppliedFile, strIBERQSPath, strLocalVersion
Dim fso, shell

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' ===========================================
' CONFIGURACION - Lee de archivo externo
' ===========================================
' Priority: sync-config.txt > variables abajo
' Edite sync-config.txt (junto al .vbs) con:
'   server_url=https://tunel.trycloudflare.com
'   conera_name=K135
' ===========================================

' Valores por defecto (si no hay sync-config.txt)
strServerUrl = "https://ejemplo.trycloudflare.com"
strConeraName = "NOMBRE-DE-LA-CONERA"
strDataDir = "C:\Bootdrv\AlohaQs\DATA"
strNewDataDir = "C:\Bootdrv\AlohaQs\NEWDATA"
strVersionFile = "C:\Bootdrv\AlohaQs\version.txt"
strLogFile = "C:\Bootdrv\AlohaQs\sync-log.txt"
strForceAppliedFile = "C:\Bootdrv\AlohaQs\force-applied.txt"
strIBERQSPath = "C:\BootDrv\AlohaQS\BIN\IBERQS.exe"

' Cargar config desde archivo externo si existe
Dim strConfigFile
strConfigFile = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "sync-config.txt")
If fso.FileExists(strConfigFile) Then
    On Error Resume Next
    Dim ts, line, eqPos, key, value
    Set ts = fso.OpenTextFile(strConfigFile, 1)
    Do While ts.AtEndOfStream <> True
        line = Trim(ts.ReadLine())
        If line <> "" And Left(line, 1) <> "'" And Left(line, 1) <> "#" Then
            eqPos = InStr(line, "=")
            If eqPos > 0 Then
                key = Trim(Left(line, eqPos - 1))
                value = Trim(Mid(line, eqPos + 1))
                Select Case LCase(key)
                    Case "server_url":  strServerUrl = value
                    Case "conera_name": strConeraName = value
                    Case "data_dir":    strDataDir = value
                    Case "newdata_dir": strNewDataDir = value
                    Case "version_file": strVersionFile = value
                    Case "log_file":    strLogFile = value
                    Case "iberqs_path": strIBERQSPath = value
                End Select
            End If
        End If
    Loop
    ts.Close
    On Error Goto 0
End If

' ===========================================
' SINGLE INSTANCE - Evita duplicados
' ===========================================
Dim strLockFile
strLockFile = fso.BuildPath(fso.GetSpecialFolder(2), "dbf-sync-" & strConeraName & ".lock")
On Error Resume Next
' Si el lock existe y tiene mas de 5 min, se ignora (la instancia anterior murio)
If fso.FileExists(strLockFile) Then
    If DateDiff("s", fso.GetFile(strLockFile).DateLastModified, Now) > 300 Then
        fso.DeleteFile strLockFile, True
    Else
        WScript.Quit ' Otra instancia corriendo
    End If
End If
Dim lockFile
Set lockFile = fso.CreateTextFile(strLockFile, True)
lockFile.WriteLine Now
lockFile.Close
On Error Goto 0

' ===========================================
' FUNCIONES
' ===========================================

Sub CleanupLock()
    On Error Resume Next
    fso.DeleteFile strLockFile, True
    On Error Goto 0
End Sub

Sub Log(msg)
    Dim logLine
    logLine = Now & " [INFO] " & msg
    On Error Resume Next
    Dim outFile
    Set outFile = fso.OpenTextFile(strLogFile, 8, True)
    outFile.WriteLine logLine
    outFile.Close
    On Error Goto 0
End Sub

Sub LogError(msg)
    Dim logLine
    logLine = Now & " [ERROR] " & msg
    On Error Resume Next
    Dim outFile
    Set outFile = fso.OpenTextFile(strLogFile, 8, True)
    outFile.WriteLine logLine
    outFile.Close
    On Error Goto 0
End Sub

Function ReadLocalVersion()
    On Error Resume Next
    Dim file
    If fso.FileExists(strVersionFile) Then
        Set file = fso.OpenTextFile(strVersionFile, 1)
        ReadLocalVersion = Trim(file.ReadLine())
        file.Close
    Else
        ReadLocalVersion = ""
    End If
    On Error Goto 0
End Function

Sub WriteLocalVersion(version)
    On Error Resume Next
    Dim folderPath
    folderPath = fso.GetParentFolderName(strVersionFile)
    If Not fso.FolderExists(folderPath) Then
        fso.CreateFolder folderPath
    End If
    Dim file
    Set file = fso.CreateTextFile(strVersionFile, True)
    file.WriteLine version
    file.Close
    On Error Goto 0
End Sub

Function ReadForceApplied()
    On Error Resume Next
    Dim file
    If fso.FileExists(strForceAppliedFile) Then
        Set file = fso.OpenTextFile(strForceAppliedFile, 1)
        ReadForceApplied = Trim(file.ReadLine())
        file.Close
    Else
        ReadForceApplied = ""
    End If
    On Error Goto 0
End Function

Sub WriteForceApplied(version)
    On Error Resume Next
    Dim folderPath
    folderPath = fso.GetParentFolderName(strForceAppliedFile)
    If Not fso.FolderExists(folderPath) Then
        fso.CreateFolder folderPath
    End If
    Dim file
    Set file = fso.CreateTextFile(strForceAppliedFile, True)
    file.WriteLine version
    file.Close
    On Error Goto 0
End Sub

Function CreateHttp()
    Dim obj
    On Error Resume Next
    Set obj = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    If Err.Number <> 0 Then
        Set obj = CreateObject("WinHttp.WinHttpRequest.5.1")
    End If
    If Err.Number <> 0 Then
        Set obj = CreateObject("MSXML2.XMLHTTP.3.0")
    End If
    On Error Goto 0
    Set CreateHttp = obj
End Function

Function HttpGet(url)
    Dim http
    Set http = CreateHttp()
    On Error Resume Next
    http.Open "GET", url, False
    http.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
    http.Send
    If Err.Number <> 0 Then
        HttpGet = ""
        Exit Function
    End If
    On Error Goto 0
    If http.Status = 200 Then
        HttpGet = http.ResponseText
    Else
        HttpGet = ""
    End If
End Function

Function HttpGetJsonValue(jsonText, key)
    Dim re, matches
    Set re = New RegExp
    re.Pattern = """" & key & """\s*:\s*""([^""]+)"""
    re.IgnoreCase = True
    Set matches = re.Execute(jsonText)
    If matches.Count > 0 Then
        HttpGetJsonValue = matches(0).SubMatches(0)
    Else
        HttpGetJsonValue = ""
    End If
End Function

Function HttpGetJsonBool(jsonText, key)
    Dim re, matches
    Set re = New RegExp
    re.Pattern = """" & key & """\s*:\s*(true|false)"
    re.IgnoreCase = True
    Set matches = re.Execute(jsonText)
    If matches.Count > 0 Then
        HttpGetJsonBool = (matches(0).SubMatches(0) = "true")
    Else
        HttpGetJsonBool = False
    End If
End Function

Function HttpGetBinary(url, savePath)
    Dim http, ado
    Set http = CreateHttp()
    On Error Resume Next
    http.Open "GET", url, False
    http.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
    http.Send
    If Err.Number <> 0 Then
        HttpGetBinary = False
        Exit Function
    End If
    On Error Goto 0
    If http.Status <> 200 Then
        HttpGetBinary = False
        Exit Function
    End If
    Set ado = CreateObject("ADODB.Stream")
    ado.Type = 1
    ado.Open
    ado.Write http.ResponseBody
    ado.SaveToFile savePath, 2
    ado.Close
    HttpGetBinary = True
End Function

Sub ExtractZip(zipPath, destPath)
    Dim app
    Set app = CreateObject("Shell.Application")
    On Error Resume Next
    Dim zipFolder, destFolder
    Set zipFolder = app.NameSpace(zipPath)
    Set destFolder = app.NameSpace(destPath)
    If Err.Number = 0 Then
        destFolder.CopyHere zipFolder.Items, 20
    End If
    On Error Goto 0
End Sub

Sub CopyDbfFiles(sourceFolder, destFolder)
    Dim f, src
    Set src = fso.GetFolder(sourceFolder)
    If Not fso.FolderExists(destFolder) Then
        fso.CreateFolder destFolder
    End If
    For Each f In src.Files
        If LCase(fso.GetExtensionName(f.Name)) = "dbf" Then
            On Error Resume Next
            fso.CopyFile f.Path, destFolder & "\" & f.Name, True
            If Err.Number <> 0 Then
                LogError "Error copiando " & f.Name & ": " & Err.Description
            End If
            On Error Goto 0
        End If
    Next
End Sub

Sub RunAction(action)
    Log "Ejecutando accion: " & action
    If action = "restart" And strIBERQSPath <> "" Then
        If fso.FileExists(strIBERQSPath) Then
            shell.Run "taskkill /f /im IBERQS.exe", 0, True
            WScript.Sleep 2000
            shell.Run """" & strIBERQSPath & """", 1, False
            Log "IBERQS reiniciado"
        Else
            LogError "IBERQS no encontrado en: " & strIBERQSPath
        End If
    ElseIf action = "logoff" Then
        shell.Run "shutdown /l /f", 0, False
        Log "Cerrando sesion..."
    End If
End Sub

Function DownloadAndInstall(bForce)
    Dim versionUrl, versionResponse, serverVersion, localVer
    Dim downloadUrl, tmpDir, tmpZip, extractDir

    versionUrl = strServerUrl & "/api/version"
    versionResponse = HttpGet(versionUrl)
    If versionResponse = "" Then
        LogError "No se pudo conectar al servidor"
        DownloadAndInstall = False
        Exit Function
    End If

    serverVersion = HttpGetJsonValue(versionResponse, "version")
    If serverVersion = "" Or serverVersion = "ninguna" Then
        Log "Servidor: No hay version disponible"
        DownloadAndInstall = False
        Exit Function
    End If

    localVer = ReadLocalVersion()

    If localVer = serverVersion And Not bForce Then
        DownloadAndInstall = False
        Exit Function
    End If

    If bForce Then
        Log "FORZANDO descarga: " & serverVersion
    Else
        Log "Nueva version: " & serverVersion & " (actual: " & localVer & ")"
    End If

    downloadUrl = strServerUrl & "/api/download"
    tmpDir = fso.GetSpecialFolder(2)
    tmpZip = tmpDir & "\dbf_sync_" & serverVersion & ".zip"

    If Not HttpGetBinary(downloadUrl, tmpZip) Then
        LogError "Error al descargar"
        DownloadAndInstall = False
        Exit Function
    End If

    Log "Descargado: " & fso.GetFile(tmpZip).Size & " bytes"
    extractDir = tmpDir & "\dbf_sync_extract_" & serverVersion
    If fso.FolderExists(extractDir) Then fso.DeleteFolder extractDir, True
    fso.CreateFolder extractDir
    ExtractZip tmpZip, extractDir
    CopyDbfFiles extractDir, strDataDir
    CopyDbfFiles extractDir, strNewDataDir
    WriteLocalVersion serverVersion
    Log "Actualizacion completada: " & serverVersion

    On Error Resume Next
    fso.DeleteFile tmpZip, True
    fso.DeleteFolder extractDir, True
    On Error Goto 0

    DownloadAndInstall = True
End Function

Function CheckForceUpdate()
    Dim url, resp, forceActive, forceAction, forceVersion, downloaded
    url = strServerUrl & "/api/force-update-status?conera_name=" & strConeraName
    resp = HttpGet(url)
    If resp = "" Then
        CheckForceUpdate = False
        Exit Function
    End If

    forceActive = HttpGetJsonBool(resp, "active")
    If Not forceActive Then
        CheckForceUpdate = False
        Exit Function
    End If

    forceVersion = HttpGetJsonValue(resp, "version")
    forceAction = HttpGetJsonValue(resp, "action")

    ' Skip if already applied
    If ReadForceApplied() = forceVersion Then
        CheckForceUpdate = False
        Exit Function
    End If

    Log "Orden forzada: version=" & forceVersion & " action=" & forceAction

    downloaded = DownloadAndInstall(True)
    If downloaded Then
        WriteForceApplied forceVersion
        RunAction forceAction
    Else
        LogError "Fallo la descarga forzada"
    End If

    Dim ackData
    ackData = "{""name"":""" & strConeraName & """,""status"":""" & CStr(downloaded) & """}"
    Dim http
    Set http = CreateHttp()
    On Error Resume Next
    http.Open "POST", strServerUrl & "/api/force-update-ack", False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send ackData
    On Error Goto 0

    CheckForceUpdate = True
End Function

Sub CheckIn(version)
    Dim url, http
    url = strServerUrl & "/api/conera/checkin"
    Set http = CreateHttp()
    On Error Resume Next
    http.Open "POST", url, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send "{""name"":""" & strConeraName & """,""version"":""" & version & """}"
    If Err.Number = 0 And http.Status = 200 Then
        Log "Check-in enviado: " & version
    Else
        LogError "Error en check-in: " & Err.Description
    End If
    On Error Goto 0
End Sub

Sub Register()
    Dim url, http
    url = strServerUrl & "/api/conera/register"
    Set http = CreateHttp()
    On Error Resume Next
    http.Open "POST", url, False
    http.SetRequestHeader "Content-Type", "application/json"
    http.Send "{""name"":""" & strConeraName & """}"
    If Err.Number = 0 And http.Status = 200 Then
        Log "Registrado en servidor"
    Else
        LogError "Error al registrar: " & Err.Description
    End If
    On Error Goto 0
End Sub

' ===========================================
' MAIN
' ===========================================

' Hide console if running as .vbs (wscript)
If LCase(Right(WScript.FullName, 11)) = "wscript.exe" Then
    ' running as wscript - no console
End If

Log "============================================"
Log "DBF Sync Client iniciado - " & strConeraName
Log "Servidor: " & strServerUrl
Log "DATA: " & strDataDir
Log "NEWDATA: " & strNewDataDir
Log "Intervalo: " & CHECK_INTERVAL & "s"
Log "============================================"

Call Register()

Dim normalCycle
normalCycle = 0

Do While True
    ' Every cycle, check for force update
    Dim forced
    forced = CheckForceUpdate()
    If Not forced Then
        ' Check for normal update every cycle
        normalCycle = normalCycle + 1
        If normalCycle >= 1 Then
            Dim updated
            updated = DownloadAndInstall(False)
            If updated Then
                Log "Version actualizada automaticamente"
            End If
            normalCycle = 0
        End If
    End If
    ' Always send check-in to keep status updated
    CheckIn ReadLocalVersion()
    WScript.Sleep CHECK_INTERVAL * 1000
Loop
