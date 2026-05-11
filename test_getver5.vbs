Set fso = CreateObject("Scripting.FileSystemObject")
data = fso.OpenTextFile(WScript.Arguments(0)).ReadAll()
p = InStr(data, """version"":""")
If p = 0 Then p = InStr(data, """version"": """)
If p > 0 Then
    s = Mid(data, p + 11)
    If Left(s, 1) = " " Then s = Mid(s, 2)
    q = InStr(s, """")
    If q > 0 Then WScript.Echo Left(s, q - 1)
End If
