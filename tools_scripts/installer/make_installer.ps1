# Builds the Windows installer UAD_Setup.exe around an exported UAD.exe (called by build.ps1).
#   make_installer.ps1 -Exe build\windows\UAD.exe -Out build\windows\UAD_Setup.exe -Label "v1.3.16 Alpha" -Number 1.3.16
# Compiles Setup.cs twice with the .NET Framework's own C# compiler (always on Windows 10/11): the
# installer (with the header picture and the game's icon) and the uninstaller. Then the game and
# the uninstaller are gzipped onto the end of the installer's file: [entries][start][count]["UADSETUP"].
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Out,
    [Parameter(Mandatory)] [string]$Label,
    [Parameter(Mandatory)] [string]$Number
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'The .NET Framework 4 C# compiler (csc.exe) was not found' }
$Exe = (Resolve-Path $Exe).Path
$tmp = Join-Path $Root 'build\installer_tmp'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force $tmp | Out-Null

# the version, in the code and in the files' properties
$four = ($Number -split '\.') + @('0', '0', '0', '0') | Select-Object -First 4
$v4 = $four -join '.'
@"
using System.Reflection;
#if UNINSTALLER
[assembly: AssemblyTitle("Ukraine Air Defense - uninstaller")]
#else
[assembly: AssemblyTitle("Ukraine Air Defense - setup")]
#endif
[assembly: AssemblyProduct("Ukraine Air Defense")]
[assembly: AssemblyCompany("Mike Liashenko")]
[assembly: AssemblyCopyright("Mike Liashenko")]
[assembly: AssemblyVersion("$v4")]
[assembly: AssemblyFileVersion("$v4")]
[assembly: AssemblyInformationalVersion("$Label")]
static class AppVersion
{
	public const string Label = "$Label";
	public const string Number = "$Number";
}
"@ | Set-Content (Join-Path $tmp 'AppVersion.cs') -Encoding UTF8

$src = Join-Path $PSScriptRoot 'Setup.cs'
$icon = Join-Path $Root 'icon.ico'
$hero = Join-Path $Root 'art\installer_hero.png'
$common = @('/nologo', '/target:winexe', '/codepage:65001', '/optimize+', "/win32icon:$icon",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll')
$stub = Join-Path $tmp 'setup_stub.exe'
$uninst = Join-Path $tmp 'Uninstall UAD.exe'
& $csc @common "/resource:$hero,hero.png" "/out:$stub" $src (Join-Path $tmp 'AppVersion.cs') | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'compiling the installer failed' }
& $csc @common '/define:UNINSTALLER' "/out:$uninst" $src (Join-Path $tmp 'AppVersion.cs') | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'compiling the uninstaller failed' }

# the installer's file: the stub, then each payload entry gzipped, then the trailer
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
Copy-Item $stub $Out -Force
$o = [IO.File]::Open($Out, [IO.FileMode]::Append)
$w = New-Object IO.BinaryWriter($o)
$start = $o.Position
$entries = @(@{ Name = 'UAD.exe'; Path = $Exe }, @{ Name = 'Uninstall UAD.exe'; Path = $uninst })
foreach ($e in $entries) {
    $packed = Join-Path $tmp ($e.Name + '.gz')
    $in = [IO.File]::OpenRead($e.Path)
    $po = [IO.File]::Create($packed)
    $gz = New-Object IO.Compression.GZipStream($po, [IO.Compression.CompressionLevel]::Optimal)
    $in.CopyTo($gz, 1MB)
    $gz.Dispose(); $po.Dispose(); $in.Dispose()
    $name = [Text.Encoding]::UTF8.GetBytes($e.Name)
    $w.Write([int]$name.Length); $w.Write($name)
    $w.Write([long](Get-Item $e.Path).Length)
    $w.Write([long](Get-Item $packed).Length)
    $w.Flush()
    $pi = [IO.File]::OpenRead($packed); $pi.CopyTo($o, 1MB); $pi.Dispose()
}
$w.Write([long]$start)
$w.Write([int]$entries.Count)
$w.Write([Text.Encoding]::ASCII.GetBytes('UADSETUP'))
$w.Dispose()
Remove-Item $tmp -Recurse -Force
$mb = [math]::Round((Get-Item $Out).Length / 1MB, 1)
$exeMb = [math]::Round((Get-Item $Exe).Length / 1MB, 1)
Write-Host "    OK: $Out ($mb MB; the game itself $exeMb MB)" -ForegroundColor Green
