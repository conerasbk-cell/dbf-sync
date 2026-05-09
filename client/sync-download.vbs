Option Explicit

Dim strServerUrl, strConeraName, strDataDir, strNewDataDir, strVersionFile
Dim fso, shell, args

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

Call LoadConfig()

If args.Count > 0 Then
    Select Case LCase(args(0))
        Case "version"
            Dim vj
            vj = FetchUrl(strServerUrl & "/api/version")
            If vj <> "" Then
                WScript.Echo ExtractJsonValue(vj, "version")
            End If
        Case "register"
            FetchUrl strServerUrl & "/api/conera/register?name=" & strConeraName
        Case "checkin"
            If args.Count >= 2 Then
                FetchUrl strServerUrl & "/api/conera/checkin?name=" & strConeraName & "&version=" & args(1)
            End If
        Case "download"
            If args.Count >= 2 Then
                WScript.Echo CStr(DownloadZip(args(1)))
            End If
    End Select
End If

Sub LoadConfig()
    Dim strConfigFile, ts, line, eqPos, key, value
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
                        Case "server_url": strServerUrl = value
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
    If strConeraName = "" Then
        On Error Resume Next
        strConeraName = shell.ExpandEnvironmentStrings("%COMPUTERNAME%")
        If strConeraName = "%COMPUTERNAME%" Then strConeraName = "CONERA"
        On Error Goto 0
    End If
    If strDataDir = "" Then strDataDir = "C:\Bootdrv\AlohaQs\DATA"
    If strNewDataDir = "" Then strNewDataDir = "C:\Bootdrv\AlohaQs\NEWDATA"
    If strVersionFile = "" Then strVersionFile = "C:\Bootdrv\AlohaQs\version.txt"
End Sub

' ============================================================
' FETCH URL - Intenta multiples metodos hasta que uno funcione
' ============================================================
Function FetchUrl(url)
    Dim result
    result = TryComMethods(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    result = TryPowerShell(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    result = TryIExplorer(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    result = TryWebBrowser(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    result = TryChrome(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    result = TryFirefox(url)
    If result <> "" Then
        FetchUrl = result
        Exit Function
    End If
    For i = 1 To 3
        WScript.Sleep 1000
        result = TryChrome(url)
        If result <> "" Then
            FetchUrl = result
            Exit Function
        End If
    Next
    FetchUrl = ""
End Function

' ============================================================
' METODO 1: 13 COM objects en secuencia (WinHTTP/ServerXMLHTTP/XMLHTTP)
' ============================================================
Function TryComMethods(url)
    Dim methods, i, methodName, obj
    methods = Array( _
        "WinHttp.WinHttpRequest.5.1", _
        "MSXML2.ServerXMLHTTP.6.0", _
        "MSXML2.ServerXMLHTTP.3.0", _
        "MSXML2.ServerXMLHTTP", _
        "MSXML2.XMLHTTP.6.0", _
        "MSXML2.XMLHTTP.3.0", _
        "MSXML2.XMLHTTP", _
        "Microsoft.XMLHTTP", _
        "MSXML2.ServerXMLHTTP.5.0", _
        "MSXML2.ServerXMLHTTP.4.0", _
        "MSXML2.XMLHTTP.5.0", _
        "MSXML2.XMLHTTP.4.0", _
        "WinHttp.WinHttpRequest" _
    )
    On Error Resume Next
    For i = 0 To UBound(methods)
        methodName = methods(i)
        Set obj = Nothing
        Set obj = CreateObject(methodName)
        If Err.Number = 0 Then
            If InStr(methodName, "WinHttp") > 0 Then obj.Option(9) = 4096
            obj.Open "GET", url, False
            obj.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
            obj.Send
            If Err.Number = 0 And obj.Status = 200 Then
                TryComMethods = obj.ResponseText
                Set obj = Nothing
                On Error Goto 0
                Exit Function
            End If
        End If
        Err.Clear
    Next
    On Error Goto 0
    TryComMethods = ""
End Function

' ============================================================
' METODO 2: PowerShell (NET WebClient con TLS 1.2)
' ============================================================
Function TryPowerShell(url)
    Dim dataFile, resultFile, psContent, result
    dataFile = fso.GetSpecialFolder(2) & "\dbf_ps_data.txt"
    resultFile = fso.GetSpecialFolder(2) & "\dbf_ps_result.txt"
    psContent = "$url = '" & url & "'" & vbCrLf & _
                "$resultFile = '" & resultFile & "'" & vbCrLf & _
                "Try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } Catch { }" & vbCrLf & _
                "Try { $r = (New-Object Net.WebClient).DownloadString($url); $r | Out-File $resultFile -Encoding UTF8 } Catch { }"
    Dim psFile
    psFile = fso.GetSpecialFolder(2) & "\dbf_ps.ps1"
    WriteFile psFile, psContent
    On Error Resume Next
    shell.Run "powershell -ExecutionPolicy Bypass -File """ & psFile & """", 0, True
    On Error Goto 0
    If fso.FileExists(resultFile) Then
        Dim inFile
        Set inFile = fso.OpenTextFile(resultFile, 1)
        result = inFile.ReadAll()
        inFile.Close
        fso.DeleteFile resultFile, True
    End If
    fso.DeleteFile psFile, True
    TryPowerShell = result
End Function

' ============================================================
' METODO 3: InternetExplorer.Application
' ============================================================
Function TryIExplorer(url)
    Dim ie, resp
    On Error Resume Next
    Set ie = CreateObject("InternetExplorer.Application")
    If Err.Number <> 0 Then
        TryIExplorer = ""
        Exit Function
    End If
    ie.Visible = False
    ie.Silent = True
    ie.Navigate url
    Do While ie.Busy
        WScript.Sleep 100
    Loop
    WScript.Sleep 200
    If Not (ie.Document Is Nothing) Then
        On Error Resume Next
        resp = ie.Document.body.innerText
        If Err.Number <> 0 Then resp = ""
        On Error Goto 0
    End If
    ie.Quit
    Set ie = Nothing
    On Error Goto 0
    TryIExplorer = resp
End Function

' ============================================================
' METODO 4: Shell.Explorer.2 (WebBrowser control, disponible incluso sin IE)
' ============================================================
Function TryWebBrowser(url)
    Dim wb, resp
    On Error Resume Next
    Set wb = CreateObject("Shell.Explorer.2")
    If Err.Number <> 0 Then
        TryWebBrowser = ""
        Exit Function
    End If
    wb.Navigate url
    Dim waitCount
    waitCount = 0
    Do While wb.Busy And waitCount < 50
        WScript.Sleep 200
        waitCount = waitCount + 1
    Loop
    WScript.Sleep 500
    If Not (wb.Document Is Nothing) Then
        On Error Resume Next
        resp = wb.Document.body.innerText
        If Err.Number <> 0 Then resp = ""
        On Error Goto 0
    End If
    Set wb = Nothing
    On Error Goto 0
    TryWebBrowser = resp
End Function

' ============================================================
' METODO 5: Google Chrome headless
' ============================================================
Function FindChrome()
    Dim paths, i
    paths = Array( _
        shell.ExpandEnvironmentStrings("%PROGRAMFILES%\Google\Chrome\Application\chrome.exe"), _
        shell.ExpandEnvironmentStrings("%PROGRAMFILES(X86)%\Google\Chrome\Application\chrome.exe"), _
        shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"), _
        "C:\Program Files\Google\Chrome\Application\chrome.exe", _
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" _
    )
    On Error Resume Next
    For i = 0 To UBound(paths)
        If fso.FileExists(paths(i)) Then
            FindChrome = paths(i)
            Exit Function
        End If
    Next
    ' Try registry
    Dim regPath
    regPath = shell.RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe\")
    If Err.Number = 0 And regPath <> "" Then
        FindChrome = regPath
        Exit Function
    End If
    Err.Clear
    On Error Goto 0
    FindChrome = ""
End Function

Function TryChrome(url)
    Dim chromePath, tmpFile, cmd, result
    chromePath = FindChrome()
    If chromePath = "" Then
        TryChrome = ""
        Exit Function
    End If
    tmpFile = fso.GetSpecialFolder(2) & "\dbf_chrome_output.html"
    cmd = """" & chromePath & """ --headless --disable-gpu --virtual-time-budget=10000 --dump-dom """ & url & """ > """ & tmpFile & """ 2>nul"
    On Error Resume Next
    shell.Run cmd, 0, True
    On Error Goto 0
    If fso.FileExists(tmpFile) Then
        Dim inFile
        Set inFile = fso.OpenTextFile(tmpFile, 1)
        result = inFile.ReadAll()
        inFile.Close
        fso.DeleteFile tmpFile, True
        ' Chrome --dump-dom wraps in HTML, extract the body text
        result = ExtractBodyText(result)
    End If
    TryChrome = result
End Function

' ============================================================
' METODO 6: Mozilla Firefox headless
' ============================================================
Function FindFirefox()
    Dim paths, i
    paths = Array( _
        shell.ExpandEnvironmentStrings("%PROGRAMFILES%\Mozilla Firefox\firefox.exe"), _
        shell.ExpandEnvironmentStrings("%PROGRAMFILES(X86)%\Mozilla Firefox\firefox.exe"), _
        "C:\Program Files\Mozilla Firefox\firefox.exe", _
        "C:\Program Files (x86)\Mozilla Firefox\firefox.exe" _
    )
    On Error Resume Next
    For i = 0 To UBound(paths)
        If fso.FileExists(paths(i)) Then
            FindFirefox = paths(i)
            Exit Function
        End If
    Next
    Dim regPath
    regPath = shell.RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe\")
    If Err.Number = 0 And regPath <> "" Then
        FindFirefox = regPath
        Exit Function
    End If
    Err.Clear
    On Error Goto 0
    FindFirefox = ""
End Function

Function TryFirefox(url)
    Dim fxPath, tmpFile, cmd, result
    fxPath = FindFirefox()
    If fxPath = "" Then
        TryFirefox = ""
        Exit Function
    End If
    tmpFile = fso.GetSpecialFolder(2) & "\dbf_fx_output.html"
    cmd = """" & fxPath & """ --headless --window-size 1,1 """ & url & """ > """ & tmpFile & """ 2>nul"
    On Error Resume Next
    shell.Run cmd, 0, True
    On Error Goto 0
    If fso.FileExists(tmpFile) Then
        Dim inFile
        Set inFile = fso.OpenTextFile(tmpFile, 1)
        result = inFile.ReadAll()
        inFile.Close
        fso.DeleteFile tmpFile, True
        result = ExtractBodyText(result)
    End If
    TryFirefox = result
End Function

' ============================================================
' HELPERS
' ============================================================
Sub WriteFile(path, content)
    Dim f
    Set f = fso.CreateTextFile(path, True)
    f.Write content
    f.Close
End Sub

Function ExtractJsonValue(jsonText, key)
    Dim re, matches
    Set re = New RegExp
    re.Pattern = """" & key & """\s*:\s*""([^""]+)"""
    re.IgnoreCase = True
    Set matches = re.Execute(jsonText)
    If matches.Count > 0 Then
        ExtractJsonValue = matches(0).SubMatches(0)
    Else
        ExtractJsonValue = ""
    End If
End Function

Function ExtractBodyText(html)
    Dim re, text
    text = html
    ' Remove HTML tags
    Set re = New RegExp
    re.Global = True
    re.Pattern = "<[^>]+>"
    text = re.Replace(text, "")
    ' Remove extra whitespace
    re.Pattern = "\s+"
    text = re.Replace(text, " ")
    ' Find JSON-like content (starts with {)
    Dim start, endPos
    start = InStr(text, "{")
    If start > 0 Then
        endPos = InStrRev(text, "}")
        If endPos > start Then
            ExtractBodyText = Mid(text, start, endPos - start + 1)
            Exit Function
        End If
    End If
    ExtractBodyText = Trim(text)
End Function

' ============================================================
' DOWNLOAD ZIP - multiple methods
' ============================================================
Function DownloadZip(version)
    Dim url, tmpZip
    url = strServerUrl & "/api/download/" & version
    tmpZip = fso.GetSpecialFolder(2) & "\dbf_sync_" & version & ".zip"
    
    ' Try bitsadmin via shell
    On Error Resume Next
    shell.Run "bitsadmin /transfer dbfsync /download /priority high """ & url & """ """ & tmpZip & """", 0, True
    If fso.FileExists(tmpZip) And fso.GetFile(tmpZip).Size > 0 Then
        DownloadZip = ExtractAndInstall(tmpZip, version)
        Exit Function
    End If
    
    ' Try certutil
    shell.Run "certutil -urlcache -split -f """ & url & """ """ & tmpZip & """", 0, True
    If fso.FileExists(tmpZip) And fso.GetFile(tmpZip).Size > 0 Then
        DownloadZip = ExtractAndInstall(tmpZip, version)
        Exit Function
    End If
    
    ' Try PowerShell
    Dim psScript, psFile
    psScript = "Try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } Catch { }" & vbCrLf & _
               "Try { (New-Object Net.WebClient).DownloadFile('" & url & "', '" & tmpZip & "') } Catch { }"
    psFile = fso.GetSpecialFolder(2) & "\dbf_dl.ps1"
    WriteFile psFile, psScript
    shell.Run "powershell -ExecutionPolicy Bypass -File """ & psFile & """", 0, True
    fso.DeleteFile psFile, True
    On Error Goto 0
    If fso.FileExists(tmpZip) And fso.GetFile(tmpZip).Size > 0 Then
        DownloadZip = ExtractAndInstall(tmpZip, version)
        Exit Function
    End If
    
    ' Try Chrome with temp profile (auto-download, hidden)
    Dim browserPath
    browserPath = FindChrome()
    If browserPath <> "" Then
        Dim chromeTemp, chromeDlDir, chromeUdDir, prefsFile, prefsJson
        chromeTemp = fso.GetSpecialFolder(2) & "\chrome_dl_" & version
        chromeDlDir = chromeTemp & "\downloads"
        chromeUdDir = chromeTemp & "\user-data"
        If fso.FolderExists(chromeTemp) Then fso.DeleteFolder chromeTemp, True
        fso.CreateFolder chromeDlDir
        fso.CreateFolder chromeUdDir & "\Default"
        ' Write Preferences file for auto-download
        prefsFile = chromeUdDir & "\Default\Preferences"
        prefsJson = "{""download"":{""default_directory"":""" & Replace(chromeDlDir, "\", "\\") & """,""prompt_for_download"":false,""directory_upgrade"":true},""safebrowsing"":{""enabled"":false},""browser"":{""check_default_browser"":false}}"
        WriteFile prefsFile, prefsJson
        ' Launch Chrome hidden with temp profile
        Dim chromeCmd
        chromeCmd = """" & browserPath & """ --user-data-dir=""" & chromeUdDir & """ --no-sandbox --disable-gpu --no-first-run --no-default-browser-check --disable-extensions --disable-features=DownloadBubble,InsecureDownloadWarnings --safebrowsing-disable-download-protection --new-window """ & url & """"
        shell.Run chromeCmd, 0, False
        WScript.Sleep 20000
        ' Kill Chrome
        On Error Resume Next
        shell.Run "taskkill /f /im chrome.exe", 0, True
        On Error Goto 0
        WScript.Sleep 1000
        ' Look for downloaded zip in custom dir and Downloads
        Dim dlFile
        dlFile = chromeDlDir & "\" & version & ".zip"
        If fso.FileExists(dlFile) Then
            fso.CopyFile dlFile, tmpZip, True
        Else
            ' Search recursively in the download dir
            Dim f, fc
            Set fc = fso.GetFolder(chromeDlDir).Files
            For Each f In fc
                If LCase(fso.GetExtensionName(f.Name)) = "zip" Then
                    fso.CopyFile f.Path, tmpZip, True
                End If
            Next
        End If
        If fso.FileExists(tmpZip) And fso.GetFile(tmpZip).Size > 0 Then
            DownloadZip = ExtractAndInstall(tmpZip, version)
            Exit Function
        End If
    End If
    
    ' Try Firefox with temp profile (auto-download, hidden)
    Dim fxPath
    fxPath = FindFirefox()
    If fxPath <> "" Then
        Dim fxTemp, fxDlDir, fxProfileDir, fxPrefs, fxCmd
        fxTemp = fso.GetSpecialFolder(2) & "\fx_dl_" & version
        fxDlDir = fxTemp & "\downloads"
        fxProfileDir = fxTemp & "\profile"
        If fso.FolderExists(fxTemp) Then fso.DeleteFolder fxTemp, True
        fso.CreateFolder fxDlDir
        fso.CreateFolder fxProfileDir
        ' Write user.js for auto-download
        fxPrefs = fxProfileDir & "\user.js"
        Dim prefsLines
        prefsLines = "user_pref(""browser.download.folderList"", 2);" & vbCrLf & _
                     "user_pref(""browser.download.dir"", """ & Replace(fxDlDir, "\", "\\") & """);" & vbCrLf & _
                     "user_pref(""browser.download.useDownloadDir"", true);" & vbCrLf & _
                     "user_pref(""browser.helperApps.neverAsk.saveToDisk"", ""application/zip,application/x-zip,application/x-zip-compressed"");" & vbCrLf & _
                     "user_pref(""browser.download.manager.showWhenStarting"", false);" & vbCrLf & _
                     "user_pref(""browser.download.manager.focusWhenStarting"", false);" & vbCrLf & _
                     "user_pref(""browser.download.manager.showAlertOnComplete"", false);" & vbCrLf & _
                     "user_pref(""browser.shell.checkDefaultBrowser"", false);" & vbCrLf & _
                     "user_pref(""browser.shell.skipDefaultBrowserCheckOnFirstRun"", true);"
        WriteFile fxPrefs, prefsLines
        ' Launch Firefox hidden with temp profile
        fxCmd = """" & fxPath & """ --profile """ & fxProfileDir & """ --no-remote --new-window """ & url & """"
        shell.Run fxCmd, 0, False
        WScript.Sleep 20000
        ' Kill Firefox
        On Error Resume Next
        shell.Run "taskkill /f /im firefox.exe", 0, True
        On Error Goto 0
        WScript.Sleep 1000
        ' Look for downloaded zip in custom dir and Downloads
        Dim fxDlFile, fxF, fxFC
        fxDlFile = fxDlDir & "\" & version & ".zip"
        If fso.FileExists(fxDlFile) Then
            fso.CopyFile fxDlFile, tmpZip, True
        Else
            Set fxFC = fso.GetFolder(fxDlDir).Files
            For Each fxF In fxFC
                If LCase(fso.GetExtensionName(fxF.Name)) = "zip" Then
                    fso.CopyFile fxF.Path, tmpZip, True
                End If
            Next
        End If
        If fso.FileExists(tmpZip) And fso.GetFile(tmpZip).Size > 0 Then
            DownloadZip = ExtractAndInstall(tmpZip, version)
            Exit Function
        End If
    End If

    DownloadZip = False
End Function

Function ExtractAndInstall(zipPath, version)
    Dim app, zipFolder, destFolder
    Set app = CreateObject("Shell.Application")
    On Error Resume Next
    Set zipFolder = app.NameSpace(zipPath)
    If zipFolder Is Nothing Then
        ExtractAndInstall = False
        Exit Function
    End If
    If Not fso.FolderExists(strDataDir) Then fso.CreateFolder strDataDir
    If Not fso.FolderExists(strNewDataDir) Then fso.CreateFolder strNewDataDir
    Set destFolder = app.NameSpace(strDataDir)
    destFolder.CopyHere zipFolder.Items, 20
    Set destFolder = app.NameSpace(strNewDataDir)
    destFolder.CopyHere zipFolder.Items, 20
    On Error Goto 0
    Dim vf
    Set vf = fso.CreateTextFile(strVersionFile, True)
    vf.WriteLine version
    vf.Close
    fso.DeleteFile zipPath, True
    ExtractAndInstall = True
End Function
