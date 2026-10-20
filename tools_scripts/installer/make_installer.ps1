# Builds the Windows installer UAD_Setup.exe around an exported UAD.exe (called by build.ps1).
#   make_installer.ps1 -Exe build\windows\UAD.exe -Out build\windows\UAD_Setup.exe -Label "v1.3.19 Alpha" -Number 1.3.19
# Compiles uad.iss with Inno Setup 6 (ISCC.exe): $env:ISCC, or a per-user or machine-wide install.
# Get it once with: winget install --id JRSoftware.InnoSetup --scope user
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Out,
    [Parameter(Mandatory)] [string]$Label,
    [Parameter(Mandatory)] [string]$Number
)
$ErrorActionPreference = 'Stop'
$iscc = @($env:ISCC,
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is needed for the installer: winget install --id JRSoftware.InnoSetup --scope user' }
$Exe = (Resolve-Path $Exe).Path
$Out = [IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
if (Test-Path $Out) { Remove-Item $Out -Force }

# the version in the file's properties wants four numbers
$v4 = (($Number -split '\.') + @('0', '0', '0', '0') | Select-Object -First 4) -join '.'
& $iscc /Q "/DSrcExe=$Exe" "/DAppVer=$Number" "/DAppVer4=$v4" "/DAppLabel=$Label" `
    "/O$(Split-Path $Out)" "/F$([IO.Path]::GetFileNameWithoutExtension($Out))" (Join-Path $PSScriptRoot 'uad.iss') | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Out)) { throw "Inno Setup failed ($LASTEXITCODE)" }
$mb = [math]::Round((Get-Item $Out).Length / 1MB, 1)
$exeMb = [math]::Round((Get-Item $Exe).Length / 1MB, 1)
Write-Host "    OK: $Out ($mb MB; the game itself $exeMb MB)" -ForegroundColor Green
