$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# Prevent two local release builds from competing for the same Gradle locks.
$BuildMutex = [System.Threading.Mutex]::new($false, 'Local\PokolenieReleaseBuild')
if (-not $BuildMutex.WaitOne(0)) {
    $BuildMutex.Dispose()
    throw 'A «Поколение» release build is already running. Wait for it to finish before starting another.'
}

try {
function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )
    Write-Host ""
    Write-Host ("> {0} {1}" -f $CommandName, ($ArgumentList -join ' ')) -ForegroundColor Cyan
    & $CommandName @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $CommandName)
    }
}

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH. See BUILD_INSTRUCTIONS.md."
    }
}

Write-Host '===============================================' -ForegroundColor Cyan
Write-Host 'Pokolenie - full local release APK + EXE' -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan

Require-Command 'flutter'
Require-Command 'python'

$pythonVersionText = (& python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Python version check failed.' }
$pythonVersion = [version]$pythonVersionText
if ($pythonVersion -lt [version]'3.12') {
    throw "Python 3.12 or newer is required for backend checks. Detected: $pythonVersionText"
}

$versionLine = Get-Content -LiteralPath 'pubspec.yaml' |
    Where-Object { $_ -match '^version:' } |
    Select-Object -First 1
if (-not $versionLine) { throw 'Could not find version in pubspec.yaml.' }
$AppVersion = ($versionLine -split ':', 2)[1].Trim().Trim("'").Trim('"')
if (-not $AppVersion) { throw 'Application version in pubspec.yaml is empty.' }
if ($AppVersion -notmatch '^\d+\.\d+\.\d+\+\d+$') {
    throw 'Set both app version and monotonically increasing build number in pubspec.yaml, for example 0.2.1+6.'
}
$apiBase = [Environment]::GetEnvironmentVariable('POKOLENIE_API_BASE_URL')
if ([string]::IsNullOrWhiteSpace($apiBase)) {
    $apiBase = ''
    Write-Host 'API URL not supplied: building the offline-first configuration.' -ForegroundColor Yellow
} elseif ($apiBase -notmatch '^https://[^/\s]+(?:/.*)?$' -or $apiBase.Contains('@')) {
    throw 'POKOLENIE_API_BASE_URL must be a public HTTPS URL without credentials or whitespace.'
}

$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$pf64 = [Environment]::GetEnvironmentVariable('ProgramFiles')
$isccCandidates = @()
$commandIscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if ($commandIscc -and $commandIscc.Source) { $isccCandidates += $commandIscc.Source }
if ($pf64) {
    $isccCandidates += (Join-Path $pf64 'Inno Setup 7\ISCC.exe')
    $isccCandidates += (Join-Path $pf64 'Inno Setup 6\ISCC.exe')
}
if ($pf86) {
    $isccCandidates += (Join-Path $pf86 'Inno Setup 7\ISCC.exe')
    $isccCandidates += (Join-Path $pf86 'Inno Setup 6\ISCC.exe')
}
$registryRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($registryRoot in $registryRoots) {
    foreach ($entry in (Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue)) {
        # Registry uninstall entries are not guaranteed to expose these optional fields.
        # Access them through PSObject.Properties so StrictMode does not terminate the build.
        $displayNameProperty = $entry.PSObject.Properties['DisplayName']
        $installLocationProperty = $entry.PSObject.Properties['InstallLocation']
        if ($displayNameProperty -and $installLocationProperty -and
            $displayNameProperty.Value -match '^Inno Setup' -and
            -not [string]::IsNullOrWhiteSpace([string]$installLocationProperty.Value)) {
            $isccCandidates += (Join-Path ([string]$installLocationProperty.Value) 'ISCC.exe')
        }
    }
}
$iscc = $isccCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -First 1
if (-not $iscc) {
    throw 'Inno Setup 7 or 6 compiler (ISCC.exe) was not found. Run setup_and_build.ps1 to install it.'
}

Write-Host ("Version: {0}" -f $AppVersion)
Write-Host ("Python:  {0}" -f $pythonVersionText)
Write-Host ("API URL: {0}" -f $(if ($apiBase) { $apiBase } else { '(offline)' }))
$androidSigningConfig = Join-Path $Root 'android\key.properties'
if (-not (Test-Path -LiteralPath $androidSigningConfig -PathType Leaf)) {
    Write-Warning 'Android release APK will use the local debug key. This is for testing only; configure a dedicated persistent release key before distribution.'
}

Write-Host ''
Write-Host 'Cleaning stale Flutter/CMake generated artifacts before the release build...' -ForegroundColor Yellow
Invoke-CheckedCommand 'flutter' @('clean')

Invoke-CheckedCommand 'python' @('-m', 'pip', 'install', '-r', 'backend/requirements.txt')
Invoke-CheckedCommand 'python' @('backend/security_check.py')
Invoke-CheckedCommand 'python' @('-m', 'unittest', 'discover', '-s', 'backend/tests', '-v')

Invoke-CheckedCommand 'flutter' @('config', '--enable-windows-desktop')
Write-Host ''
Write-Host '> flutter doctor -v (diagnostic; actual build steps are authoritative)' -ForegroundColor Cyan
flutter doctor -v
if ($LASTEXITCODE -ne 0) { Write-Warning 'flutter doctor reported warnings; continuing so tests/builds can show the specific missing components.' }
Invoke-CheckedCommand 'flutter' @('pub', 'get')
Invoke-CheckedCommand 'flutter' @('test')
Invoke-CheckedCommand 'flutter' @('analyze', '--no-fatal-infos', '--no-fatal-warnings')

$dartDefine = "POKOLENIE_API_BASE_URL=$apiBase"
# llm_llamacpp ships Android arm64-v8a and x86_64 native binaries, not 32-bit ARM.
Invoke-CheckedCommand 'flutter' @('build', 'apk', '--release', '--target-platform', 'android-arm64,android-x64', "--dart-define=$dartDefine")
Invoke-CheckedCommand 'flutter' @('build', 'windows', '--release', "--dart-define=$dartDefine")

$apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
$releaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
$exe = Join-Path $releaseDir 'pokolenie.exe'
$requiredWindowsFiles = @(
    $exe,
    (Join-Path $releaseDir 'flutter_windows.dll'),
    (Join-Path $releaseDir 'data\flutter_assets\AssetManifest.bin'),
    (Join-Path $releaseDir 'data\flutter_assets\assets\maps\floor1.webp')
)
if (-not (Test-Path -LiteralPath $apk) -or (Get-Item -LiteralPath $apk).Length -le 0) {
    throw "APK output was not created: $apk"
}
foreach ($file in $requiredWindowsFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required Windows runtime file was not created: $file"
    }
}

$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$apkName = "Pokolenie-$AppVersion.apk"
$apkDestination = Join-Path $dist $apkName
Copy-Item -LiteralPath $apk -Destination $apkDestination -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkDestination).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$apkDestination.sha256" -Value "$hash  $apkName" -Encoding ascii

$portableName = "Pokolenie-Windows-Portable-$AppVersion"
$portableDir = Join-Path $dist $portableName
if (Test-Path -LiteralPath $portableDir) {
    Remove-Item -LiteralPath $portableDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
Copy-Item -Path (Join-Path $releaseDir '*') -Destination $portableDir -Recurse -Force

Invoke-CheckedCommand -CommandName $iscc -ArgumentList @("/DMyAppVersion=$AppVersion", 'windows/installer.iss')

$installer = Join-Path $dist "Pokolenie-Setup-$AppVersion.exe"
if (-not (Test-Path -LiteralPath $installer) -or (Get-Item -LiteralPath $installer).Length -le 0) {
    throw "Windows installer was not created: $installer"
}

Write-Host ''
Write-Host 'BUILD SUCCEEDED' -ForegroundColor Green
Write-Host ("APK:              {0}" -f $apkDestination)
Write-Host ("APK SHA-256:      {0}" -f "$apkDestination.sha256")
Write-Host ("Windows installer: {0}" -f $installer)
Write-Host ("Portable Windows:  {0}" -f $portableDir)
Write-Host 'Run the installer EXE for normal Windows installation. Do not separate pokolenie.exe from its DLLs and data folder.'
} finally {
    $BuildMutex.ReleaseMutex()
    $BuildMutex.Dispose()
}
