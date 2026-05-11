param([string]$conera = "K119")
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot "zips\$conera.zip"))
foreach ($e in $z.Entries) { Write-Host ("  " + $e.Name + " - " + $e.Length + " bytes") }
$c = $z.GetEntry("sync-config.txt")
if ($c) {
    $r = New-Object System.IO.StreamReader $c.Open()
    $content = $r.ReadToEnd()
    $r.Close()
    Write-Host "--- sync-config.txt ---"
    Write-Host $content
}
$z.Dispose()
