#Requires -Version 5.1
# Builds a no-secret, offline-first test APK and Windows debug package.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

trap {
    Write-Host ''
    Write-Host ('TEST BUILD FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Project: ' + $Root)
    Write-Host 'The Android APK may already have been built before a Windows-toolchain error.'
    Write-Host 'No backend password, token, Firebase service key, or API URL is needed for this test build.'
    exit 1
}

$FlutterCandidates = @()
if ($env:FLUTTER_ROOT) { $FlutterCandidates += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat') }
if ($env:USERPROFILE) { $FlutterCandidates += (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat') }
$FlutterCandidates += @(
    'C:\src\flutter\bin\flutter.bat',
    'C:\Dev\Programs\PokolenieToolchain\Flutter-3.47.4\flutter\bin\flutter.bat'
)
$FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($FlutterCommand) { $FlutterCandidates += $FlutterCommand.Source }
$FlutterExe = $FlutterCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

if (-not $FlutterExe) {
    throw 'Flutter not found. Install Flutter or set FLUTTER_ROOT to its SDK directory.'
}
if (-not (Test-Path -LiteralPath (Join-Path $Root 'pubspec.yaml'))) {
    throw 'pubspec.yaml not found. Run this script from the repository copy, not from an empty folder.'
}

$env:Path = "$(Split-Path -Parent $FlutterExe);$env:Path"
# Empty API URL deliberately selects the offline-first build. Do not embed secrets in the client.
$env:POKOLENIE_API_BASE_URL = ''
$ApiDefine = '--dart-define=POKOLENIE_API_BASE_URL='

function Invoke-FlutterChecked {
    param([Parameter(Mandatory = $true)][string[]]$FlutterArguments)
    Write-Host ''
    Write-Host ('> flutter ' + ($FlutterArguments -join ' ')) -ForegroundColor Cyan
    & $FlutterExe @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw ('Flutter command failed with exit code ' + $LASTEXITCODE + ': ' + ($FlutterArguments -join ' '))
    }
}

Write-Host '===============================================' -ForegroundColor Cyan
Write-Host 'Offline-first test build: Android APK + Windows EXE' -ForegroundColor Cyan
Write-Host ('Flutter: ' + $FlutterExe)
Write-Host 'Backend URL: (empty; no server or secrets required)'
Write-Host '===============================================' -ForegroundColor Cyan

Invoke-FlutterChecked -FlutterArguments @('pub', 'get')
Invoke-FlutterChecked -FlutterArguments @('test')
Invoke-FlutterChecked -FlutterArguments @('analyze', '--no-fatal-infos', '--no-fatal-warnings')
Invoke-FlutterChecked -FlutterArguments @('build', 'apk', '--debug', $ApiDefine)

$Dist = Join-Path $Root 'dist\test'
$AndroidOut = Join-Path $Dist 'android'
New-Item -ItemType Directory -Force -Path $AndroidOut | Out-Null
$Apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path -LiteralPath $Apk) -or (Get-Item -LiteralPath $Apk).Length -le 0) {
    throw ('APK was not created: ' + $Apk)
}
$ApkDestination = Join-Path $AndroidOut 'Pokolenie-debug.apk'
Copy-Item -LiteralPath $Apk -Destination $ApkDestination -Force
Write-Host ('Android APK ready: ' + $ApkDestination) -ForegroundColor Green

Invoke-FlutterChecked -FlutterArguments @('config', '--enable-windows-desktop')
Invoke-FlutterChecked -FlutterArguments @('build', 'windows', '--debug', $ApiDefine)

$WindowsBuild = Join-Path $Root 'build\windows\x64\runner\Debug'
$WindowsExe = Join-Path $WindowsBuild 'pokolenie.exe'
if (-not (Test-Path -LiteralPath $WindowsExe)) {
    throw ('Windows EXE was not created at ' + $WindowsExe + '. Install Visual Studio 2022 Build Tools with Desktop development with C++ and ATL, then retry.')
}

$WindowsOut = Join-Path $Dist 'windows'
if (Test-Path -LiteralPath $WindowsOut) {
    Remove-Item -LiteralPath $WindowsOut -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WindowsOut | Out-Null
Copy-Item -Path (Join-Path $WindowsBuild '*') -Destination $WindowsOut -Recurse -Force
$Zip = Join-Path $Dist 'Pokolenie-Windows-Debug.zip'
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Compress-Archive -Path (Join-Path $WindowsOut '*') -DestinationPath $Zip -CompressionLevel Optimal

Write-Host ''
Write-Host 'TEST BUILDS SUCCEEDED' -ForegroundColor Green
Write-Host ('Android APK: ' + $ApkDestination) -ForegroundColor Green
Write-Host ('Windows EXE: ' + (Join-Path $WindowsOut 'pokolenie.exe')) -ForegroundColor Green
Write-Host ('Windows package: ' + $Zip) -ForegroundColor Green
Write-Host 'The Windows EXE must stay with its DLL files and data directory.'
Write-Host 'School SSO, server accounts, remote announcements and cloud push need separately configured school infrastructure.';
