$src = Join-Path $PSScriptRoot "client"
$dst = Join-Path $PSScriptRoot "zips"
$files = "dbf-sync-client-xp.vbs","sync-download.vbs","sync-conera.bat","sync-express.bat","sync-config.txt"
$coneras = @("K109","K110","K112","K113","K114","K115","K117","K118","K119","K120","K121","K124","K125","K126","K127","K128","K129","K132","K133","K135","K136","K137","K139","K140","K143","K144")

foreach ($k in $coneras) {
    $zip = Join-Path $dst "$k.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    $fullPaths = $files | ForEach-Object { Join-Path $src $_ }
    Compress-Archive -Path $fullPaths -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "$k.zip"
}
Write-Host "OK: $($coneras.Count) zips"
