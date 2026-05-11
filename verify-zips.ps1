Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot "zips\K119.zip"))
foreach ($e in $z.Entries) { Write-Host ("  " + $e.Name + " - " + $e.Length + " bytes") }
$z.Dispose()
