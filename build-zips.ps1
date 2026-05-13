$src = Join-Path $PSScriptRoot "client"
$dst = Join-Path $PSScriptRoot "zips"
$files = "dbf-sync-client-xp.vbs","sync-download.vbs","sync-conera.bat","sync-express.bat","sync-checkin.vbs","sync-config.txt"
$coneras = @("K109","K110","K112","K113","K114","K115","K117","K118","K119","K120","K121","K124","K125","K126","K127","K128","K129","K132","K133","K135","K136","K137","K139","K140","K143","K144")

foreach ($k in $coneras) {
    $zip = Join-Path $dst "$k.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }

    $tmp = Join-Path $PSScriptRoot "_tmp_$k"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    foreach ($f in $files) {
        Copy-Item (Join-Path $src $f) (Join-Path $tmp $f) -Force
    }

    $configPath = Join-Path $tmp "sync-config.txt"
    $line1 = [System.IO.File]::ReadAllLines((Join-Path $src "sync-config.txt"))[0]
    [System.IO.File]::WriteAllLines($configPath, @($line1, "conera_name=$k"), [System.Text.Encoding]::ASCII)

    Compress-Archive -Path "$tmp\*" -DestinationPath $zip -CompressionLevel Optimal
    Remove-Item $tmp -Recurse -Force
    Write-Host "$k.zip"
}
Write-Host "OK: $($coneras.Count) zips"
