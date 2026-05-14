Option Explicit
Dim url, shell, fso, methods, i, obj, psFile, psContent
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
url = WScript.Arguments(0)

' METODO 1: COM objects (WinHttp/ServerXMLHTTP - sin ventanas)
methods = Array("WinHttp.WinHttpRequest.5.1", "MSXML2.ServerXMLHTTP.6.0", "MSXML2.ServerXMLHTTP.3.0", "MSXML2.XMLHTTP.6.0", "MSXML2.XMLHTTP.3.0", "Microsoft.XMLHTTP")
On Error Resume Next
For i = 0 To UBound(methods)
    Set obj = Nothing
    Set obj = CreateObject(methods(i))
    If Err.Number = 0 Then
        If InStr(methods(i), "WinHttp") > 0 Then obj.Option(9) = 4096
        obj.Open "GET", url, False
        obj.SetRequestHeader "User-Agent", "DBF-Sync-Client/1.0"
        obj.Send
        If Err.Number = 0 And obj.Status = 200 Then
            On Error Goto 0
            WScript.Quit 0
        End If
    End If
    Err.Clear
Next
On Error Goto 0

' METODO 2: PowerShell (Net.WebClient con TLS 1.2)
psFile = fso.GetSpecialFolder(2) & "\dbf_ci.ps1"
psContent = "try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}; " & _
            "try { $w = New-Object Net.WebClient; $w.DownloadString('" & url & "') } catch {}"
Call WriteFile(psFile, psContent)
shell.Run "powershell -ExecutionPolicy Bypass -File """ & psFile & """", 0, True
fso.DeleteFile psFile, True

Sub WriteFile(path, content)
    Dim ts
    Set ts = fso.CreateTextFile(path, True)
    ts.Write content
    ts.Close
End Sub
