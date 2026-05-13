Option Explicit
Dim url, shell, fso, psFile, psContent
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
url = WScript.Arguments(0)
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
