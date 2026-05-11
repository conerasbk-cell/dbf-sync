Set fso = CreateObject("Scripting.FileSystemObject")
data = fso.OpenTextFile(WScript.Arguments(0)).ReadAll()
WScript.Echo "Data length: " & Len(data)
p = InStr(data, """version"":""")
WScript.Echo "Position: " & p
If p > 0 Then
    s = Mid(data, p + 11)
    q = InStr(s, """")
    If q > 0 Then WScript.Echo Left(s, q - 1)
End If
