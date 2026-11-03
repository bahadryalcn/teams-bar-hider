$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'TeamsBarHider.exe'
if (-not (Test-Path -LiteralPath $source)) { throw 'Keep Install.ps1 next to TeamsBarHider.exe.' }
$destination = Join-Path $env:LOCALAPPDATA 'TeamsBarHider'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$target = Join-Path $destination 'TeamsBarHider.exe'
if (Test-Path -LiteralPath $target) {
    $stop = Start-Process -FilePath $target -ArgumentList '--stop' -WindowStyle Hidden -Wait -PassThru
    Start-Sleep -Milliseconds 1600
}
if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $destination
Start-Process -FilePath $target -ArgumentList '--install' -WindowStyle Hidden
Write-Output "Teams Bar Hider installed and started: $target"
