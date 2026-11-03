$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'TeamsBarHider/TeamsBarHider.exe'
if (Test-Path -LiteralPath $target) {
    Start-Process -FilePath $target -ArgumentList '--uninstall' -WindowStyle Hidden -Wait
    Write-Output 'Background helper stopped; automatic startup removed. Application files retained for reuse.'
}
