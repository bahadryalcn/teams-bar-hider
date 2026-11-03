$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler is required on the build computer.' }
$dist = Join-Path $projectRoot 'dist/windows'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$applicationSource = Join-Path $PSScriptRoot 'TeamsBarHider.cs'
$applicationOutput = Join-Path $dist 'TeamsBarHider.exe'
$applicationIcon = Join-Path $projectRoot 'assets/app.ico'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/win32icon:$applicationIcon" "/resource:$applicationIcon,TeamsBarHider.AppIcon.ico" "/out:$applicationOutput" $applicationSource
if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed.' }
$checks = Join-Path $projectRoot 'temp/verification'
New-Item -ItemType Directory -Force -Path $checks | Out-Null
$testOutput = Join-Path $checks 'WindowsTests.exe'
$testSource = Join-Path $projectRoot 'tests\WindowsTests.cs'
& $compiler /nologo /target:exe /main:WindowsTests /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/resource:$applicationIcon,TeamsBarHider.AppIcon.ico" "/out:$testOutput" $applicationSource $testSource
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
# The test executable creates a hidden native fixture; no interactive console is opened.
$test = Start-Process -FilePath "$checks/WindowsTests.exe" -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$checks/windows-tests.log" -RedirectStandardError "$checks/windows-tests-error.log"
if ($test.ExitCode -ne 0) { throw "Tests failed: $checks/windows-tests-error.log" }
Get-Content "$checks/windows-tests.log"
Copy-Item -LiteralPath "$PSScriptRoot/Install.ps1","$PSScriptRoot/Uninstall.ps1" -Destination $dist
Copy-Item -LiteralPath "$projectRoot/README.md","$projectRoot/LICENSE","$projectRoot/THIRD-PARTY-NOTICES.md" -Destination $dist
Write-Output "Built $dist/TeamsBarHider.exe"
