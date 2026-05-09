Option Explicit

Dim strServerUrl, strConeraName, strDataDir, strNewDataDir, strVersionFile
Dim fso, shell, args

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

' Read config from sync-config.txt
Call LoadConfig()

If args.Count > 0 Then
    Select Case LCase(args(0))
        Case "version"
            Dim vj
            vj = GetVersionJson()
            If vj <> "" Then
                WScript.Echo HttpGetJsonValue(vj, "version")
            End If
        Case "register"
            Call RegisterConera()
        Case "checkin"
            If args.Count >= 2 Then
                Call Checkin(args(1))
            End If
        Case "download"
            If args.Count >= 2 Then
                WScript.Echo CStr(DownloadZip(args(1)))
            End If
    End Select
End If

Sub LoadConfig()
    Dim strConfigFile, ts, line, eqPos, key, value, loaded
    loaded = False
    strConfigFile = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "sync-config.txt")
    If fso.FileExists(strConfigFile) Then
        On Error Resume Next
        Set ts = fso.OpenTextFile(strConfigFile, 1)
        Do While ts.AtEndOfStream <> True
            line = Trim(ts.ReadLine())
            If line <> "" And Left(line, 1) <> "'" And Left(line, 1) <> "#" Then
                eqPos = InStr(line, "=")
                If eqPos > 0 Then
                    key = Trim(Left(line, eqPos - 1))
                    value = Trim(Mid(line, eqPos + 1))
                    Select Case LCase(key)
                        Case "server_url": strServerUrl = value: loaded = True
                        Case "conera_name": strConeraName = value
                        Case "data_dir": strDataDir = value
                        Case "newdata_dir": strNewDataDir = value
                        Case "version_file": strVersionFile = value
                    End Select
                End If
            End If
        Loop
        ts.Close
        On Error Goto 0
    End If
    If strServerUrl = "" Then strServerUrl = "https://dbf-sync.onrender.com"
    If strConeraName = "" Then strConeraName = "CONERA"
    If strDataDir = "" Then strDataDir = "C:\Bootdrv\AlohaQs\DATA"
    If strNewDataDir = "" Then strNewDataDir = "C:\Bootdrv\AlohaQs\NEWDATA"
    If strVersionFile = "" Then strVersionFile = "C:\Bootdrv\AlohaQs\version.txt"
End Sub

' Uses InternetExplorer.Application which has its own TLS stack (Trident engine)
Function IeFetch(url)
    Dim ie, resp
    On Error Resume Next
    Set ie = CreateObject("InternetExplorer.Application")
    If Err.Number <> 0 Then
        IeFetch = ""
        Exit Function
    End If
    ie.Visible = False
    ie.Silent = True
    ie.Navigate url
    Do While ie.Busy
        WScript.Sleep 100
    Loop
    WScript.Sleep 200
    If Err.Number = 0 And Not (ie.Document Is Nothing) Then
        On Error Resume Next
        resp = ie.Document.body.innerText
        If Err.Number <> 0 Then resp = ""
        On Error Goto 0
    Else
        resp = ""
    End If
    ie.Quit
    Set ie = Nothing
    On Error Goto 0
    IeFetch = resp
End Function

Function GetVersionJson()
    Dim url
    url = strServerUrl & "/api/version"
    GetVersionJson = IeFetch(url)
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

Sub RegisterConera()
    Dim url
    url = strServerUrl & "/api/conera/register?name=" & strConeraName
    IeFetch url
End Sub

Sub Checkin(version)
    Dim url
    url = strServerUrl & "/api/conera/checkin?name=" & strConeraName & "&version=" & version
    IeFetch url
End Sub

Function DownloadZip(version)
    Dim url, tmpZip, app, zipFolder, destFolder, f
    url = strServerUrl & "/api/download/" & version
    tmpZip = fso.GetSpecialFolder(2) & "\dbf_sync_" & version & ".zip"
    
    ' Download via bitsadmin (called from batch) or IE
    ' IE can navigate to trigger download
    Dim ie
    On Error Resume Next
    Set ie = CreateObject("InternetExplorer.Application")
    If Err.Number <> 0 Then
        DownloadZip = False
        Exit Function
    End If
    ie.Visible = False
    ie.Silent = True
    ie.Navigate url
    Do While ie.Busy
        WScript.Sleep 100
    Loop
    WScript.Sleep 2000
    ie.Quit
    Set ie = Nothing
    On Error Goto 0
    
    ' Check if downloaded to Downloads folder
    ' Fallback: assume the batch handled the download
    If fso.FileExists(tmpZip) Then
        ' Extract
        Set app = CreateObject("Shell.Application")
        On Error Resume Next
        Set zipFolder = app.NameSpace(tmpZip)
        If Not (zipFolder Is Nothing) Then
            If Not fso.FolderExists(strDataDir) Then fso.CreateFolder strDataDir
            If Not fso.FolderExists(strNewDataDir) Then fso.CreateFolder strNewDataDir
            Set destFolder = app.NameSpace(strDataDir)
            destFolder.CopyHere zipFolder.Items, 20
            Set destFolder = app.NameSpace(strNewDataDir)
            destFolder.CopyHere zipFolder.Items, 20
        End If
        On Error Goto 0
        
        ' Save version
        Dim vf
        Set vf = fso.CreateTextFile(strVersionFile, True)
        vf.WriteLine version
        vf.Close
        
        DownloadZip = True
    Else
        DownloadZip = False
    End If
End Function
