<#
.SYNOPSIS
  One-click build for Ukraine Air Defense (UAD).

.DESCRIPTION
  1. Finds Godot 4.7.2 (tools\ or $env:GODOT); downloads it from the official GitHub release if missing.
  2. Installs the export templates into %APPDATA%\Godot\export_templates\4.7.2.stable
     (from tools\templates.tpz, downloading it if missing).
  3. Stamps the next build number: scripts\build_info.gd (BUILD, date, commit), the Windows file
     version and the Android versionCode / versionName in export_presets.cfg. People see the
     version name "v1.0.N Alpha" (VERSION and STAGE in build_info.gd).
  4. Imports the project headlessly and exports the requested targets. Release APKs are signed with
     the project key in %USERPROFILE%\.uad (created on the first release build — back it up: an
     update signed with another key will not install over the old app).
  5. With -Publish: commits the stamp, pushes, creates the GitHub release v1.0.N-alpha with the .exe and
     the .apk, and writes the newest build into the database (uad/release) — every game that is
     older offers the update in its main menu.

.EXAMPLE
  .\build.ps1                          # Windows .exe  -> build\windows\UAD.exe
  .\build.ps1 -Target apk              # Android .apk  -> build\android\UAD.apk
  .\build.ps1 -Target all -Publish -Notes "Общие налёты в сети"
  .\build.ps1 -NoBump                  # rebuild without a new number
#>
param(
    [ValidateSet('windows', 'apk', 'aab', 'all')]
    [string]$Target = 'windows',
    [switch]$DebugBuild,
    [switch]$Publish,
    [switch]$NoBump,
    [string]$Notes = ''
)

# 'Continue': Godot prints warnings to stderr, which must not abort the script.
# Success is verified by checking that each output file exists.
$ErrorActionPreference = 'Continue'
$Root      = $PSScriptRoot
$Version   = '4.7.2'
$Tag       = "$Version-stable"
$Tools     = Join-Path $Root 'tools'
$BaseUrl   = "https://github.com/godotengine/godot/releases/download/$Tag"
$Templates = Join-Path $env:APPDATA "Godot\export_templates\$Version.stable"
$Repo      = 'MikeLiashenko/UAD'
$Site      = 'https://mikeliashenko.github.io/UAD/'
$Database  = 'https://dream-journal-93835-default-rtdb.firebaseio.com'
$Utf8      = New-Object System.Text.UTF8Encoding($false)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Text($path, $text) { [System.IO.File]::WriteAllText($path, $text, $Utf8) }

if ($Publish -and $Target -eq 'windows') { $Target = 'all' }  # a release ships both files

New-Item -ItemType Directory -Force $Tools | Out-Null
# Keep Godot from scanning the 1+ GB of tool binaries as project resources.
if (-not (Test-Path "$Tools\.gdignore")) { New-Item -ItemType File "$Tools\.gdignore" | Out-Null }
New-Item -ItemType Directory -Force (Join-Path $Root 'build') | Out-Null
if (-not (Test-Path "$Root\build\.gdignore")) { New-Item -ItemType File "$Root\build\.gdignore" | Out-Null }

# --- 1. Godot editor ----------------------------------------------------------------
$Godot = $env:GODOT
if (-not $Godot) { $Godot = Join-Path $Tools "Godot_v$($Tag)_win64_console.exe" }
if (-not (Test-Path $Godot)) {
    Step "Downloading Godot $Tag editor (~82 MB)"
    $zip = Join-Path $Tools 'godot.zip'
    curl.exe -L --fail -o $zip "$BaseUrl/Godot_v$($Tag)_win64.exe.zip"
    if ($LASTEXITCODE -ne 0) { throw 'Godot download failed' }
    Expand-Archive -Force $zip -DestinationPath $Tools
}
Step "Using Godot: $Godot"

# --- 2. Export templates ----------------------------------------------------------------
if (-not (Test-Path (Join-Path $Templates 'windows_release_x86_64.exe'))) {
    $tpz = Join-Path $Tools 'templates.tpz'
    if (-not (Test-Path $tpz)) {
        Step "Downloading export templates (~1.2 GB)"
        curl.exe -L --fail -o $tpz "$BaseUrl/Godot_v$($Tag)_export_templates.tpz"
        if ($LASTEXITCODE -ne 0) { throw 'Template download failed' }
    }
    Step "Installing export templates into $Templates"
    New-Item -ItemType Directory -Force $Templates | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.Name
            if ($name -eq '' ) { continue }
            if ($name -match '^(windows_|android_|version\.txt)') {
                $dest = Join-Path $Templates $name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                Write-Host "    $name"
            }
        }
    } finally { $archive.Dispose() }
}

# --- 3. Build number ----------------------------------------------------------------------------
$InfoPath = Join-Path $Root 'scripts\build_info.gd'
$info = [System.IO.File]::ReadAllText($InfoPath)
$Build = [int]([regex]::Match($info, 'const BUILD := (\d+)').Groups[1].Value)
if (-not $NoBump) { $Build += 1 }
# the version people see: v<VERSION>.<build> <STAGE> ("v1.0.8 Alpha"), both from build_info.gd
$Base = [regex]::Match($info, 'const VERSION := "([^"]+)"').Groups[1].Value
if (-not $Base) { $Base = '1.0' }
$Stage = [regex]::Match($info, 'const STAGE := "([^"]*)"').Groups[1].Value
$AppVersion = "$Base.$Build"
$VersionName = ("v$AppVersion $Stage").Trim()
$Date = Get-Date -Format 'yyyy-MM-dd'
$Commit = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
    $Commit = (git -C $Root rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $Commit = '' }
}
Step "$VersionName (build $Build, $Date)"
$info = [regex]::Replace($info, 'const BUILD := \d+', "const BUILD := $Build")
$info = [regex]::Replace($info, 'const DATE := "[^"]*"', "const DATE := `"$Date`"")
$info = [regex]::Replace($info, 'const COMMIT := "[^"]*"', "const COMMIT := `"$Commit`"")
Write-Text $InfoPath $info
$parts = @($AppVersion.Split('.'))
while ($parts.Count -lt 4) { $parts += '0' }
$FileVersion = ($parts[0..3] -join '.')
$PresetsPath = Join-Path $Root 'export_presets.cfg'
$presets = [System.IO.File]::ReadAllText($PresetsPath)
$presets = [regex]::Replace($presets, 'application/file_version="[^"]*"', "application/file_version=`"$FileVersion`"")
$presets = [regex]::Replace($presets, 'application/product_version="[^"]*"', "application/product_version=`"$FileVersion`"")
$presets = [regex]::Replace($presets, 'version/code=\d+', "version/code=$Build")
$presets = [regex]::Replace($presets, 'version/name="[^"]*"', "version/name=`"$("$AppVersion $Stage".Trim())`"")
Write-Text $PresetsPath $presets

# --- 4. Android signing key ---------------------------------------------------------------------
$KeyDir = Join-Path $env:USERPROFILE '.uad'
$KeyInfo = Join-Path $KeyDir 'signing.json'
if ($Target -in 'apk', 'aab', 'all' -and -not $DebugBuild) {
    if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
        if (-not (Test-Path $KeyInfo)) {
            Step "Creating the project signing key in $KeyDir (keep a backup of this folder!)"
            New-Item -ItemType Directory -Force $KeyDir | Out-Null
            $keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { 'keytool' }
            $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
            $pass = -join (1..24 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
            $store = Join-Path $KeyDir 'uad-release.keystore'
            & $keytool -genkeypair -v -keystore $store -alias uad -keyalg RSA -keysize 2048 -validity 10000 `
                -storepass $pass -keypass $pass -dname 'CN=Ukraine Air Defense, O=UAD Team, C=UA' | Out-Host
            if (-not (Test-Path $store)) { throw 'keytool failed to create the signing key' }
            Write-Text $KeyInfo (@{ keystore = $store; alias = 'uad'; password = $pass } | ConvertTo-Json)
        }
        $key = Get-Content $KeyInfo -Raw | ConvertFrom-Json
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $key.keystore
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $key.alias
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $key.password
    }
}

# --- 5. Import + export ------------------------------------------------------------------------
Step 'Importing project'
& $Godot --headless --path $Root --import | Out-Host

$mode = if ($DebugBuild) { '--export-debug' } else { '--export-release' }

function Export-Preset($preset, $out, [string[]]$extra = @()) {
    New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    if (Test-Path $out) { Remove-Item $out -Force }
    Step "Exporting '$preset' -> $out"
    & $Godot --headless --path $Root @extra $mode $preset $out | Out-Host
    if (-not (Test-Path $out)) { throw "Export failed: $out was not created (see log above)" }
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "    OK: $out ($mb MB)" -ForegroundColor Green
}

if ($Target -in 'windows', 'all') {
    Export-Preset 'Windows Desktop' (Join-Path $Root 'build\windows\UAD.exe')
}
if ($Target -in 'apk', 'aab', 'all') {
    if ($Target -in 'apk', 'all') { Export-Preset 'Android APK' (Join-Path $Root 'build\android\UAD.apk') }
    if ($Target -eq 'aab') {
        # .aab requires the Gradle build template (android/build); Godot installs it during export.
        $extra = @()
        if (-not (Test-Path (Join-Path $Root 'android\build\build.gradle'))) { $extra = @('--install-android-build-template') }
        Export-Preset 'Android AAB' (Join-Path $Root 'build\android\UAD.aab') $extra
        # Stop the Gradle daemon so it doesn't keep the console/pipe busy after the build.
        $gradlew = Join-Path $Root 'android\build\gradlew.bat'
        if (Test-Path $gradlew) { & $gradlew -p (Join-Path $Root 'android\build') --stop | Out-Null }
    }
}

# --- 6. Publish ---------------------------------------------------------------------------------
if ($Publish) {
    $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
    if (-not $gh) { $gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe' }
    if (-not (Test-Path $gh)) { throw 'GitHub CLI (gh) is needed to publish: winget install GitHub.cli' }
    $exe = Join-Path $Root 'build\windows\UAD.exe'
    $apk = Join-Path $Root 'build\android\UAD.apk'
    foreach ($f in $exe, $apk) { if (-not (Test-Path $f)) { throw "Nothing to publish: $f is missing" } }
    $tagName = if ($Stage) { "v$AppVersion-$($Stage.ToLower())" } else { "v$AppVersion" }
    if (-not $Notes) { $Notes = $VersionName }

    Step "Committing the build stamp and pushing"
    git -C $Root add scripts/build_info.gd export_presets.cfg | Out-Host
    git -C $Root commit -m "$VersionName" | Out-Host
    git -C $Root push | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }

    Step "GitHub release $tagName"
    $body = "$Notes`n`n**Windows:** UAD.exe · **Android:** UAD.apk`n`nСайт: $Site"
    & $gh release view $tagName --repo $Repo *> $null
    if ($LASTEXITCODE -eq 0) {
        # a second -Publish of the same number (-NoBump) replaces the files
        & $gh release upload $tagName $exe $apk --repo $Repo --clobber | Out-Host
    } else {
        & $gh release create $tagName $exe $apk --repo $Repo --title "UAD $VersionName" --notes $body --latest | Out-Host
    }
    if ($LASTEXITCODE -ne 0) { throw 'gh release failed' }

    Step 'Telling the games about it (database: uad/release)'
    $release = [ordered]@{
        build   = $Build
        version = $AppVersion
        name    = $VersionName
        date    = $Date
        notes   = $Notes
        exe     = "https://github.com/$Repo/releases/download/$tagName/UAD.exe"
        apk     = "https://github.com/$Repo/releases/download/$tagName/UAD.apk"
        site    = $Site
        exe_mb  = [math]::Round((Get-Item $exe).Length / 1MB, 1)
        apk_mb  = [math]::Round((Get-Item $apk).Length / 1MB, 1)
    }
    $json = $release | ConvertTo-Json
    # firebase/database.rules.json lets nobody but the owner write uad/release: put the database
    # secret (Firebase console -> Project settings -> Service accounts -> Database secrets) into
    # %USERPROFILE%\.uad\firebase_secret.txt. Without it the write only works while the rules are open.
    $uri = "$Database/uad/release.json"
    $SecretFile = Join-Path $KeyDir 'firebase_secret.txt'
    if (Test-Path $SecretFile) { $uri += '?auth=' + (Get-Content $SecretFile -Raw).Trim() }
    try {
        Invoke-RestMethod -Method Put -Uri $uri -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' | Out-Null
    } catch {
        throw "The release is on GitHub, but the database refused uad/release ($($_.Exception.Message)). Put the database secret into $SecretFile and run: .\build.ps1 -Publish -NoBump"
    }
    Write-Host "    Published ${VersionName}: https://github.com/$Repo/releases/tag/$tagName" -ForegroundColor Green
}
Step 'Done'
