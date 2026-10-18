#Requires -Version 5.1
# Bootstrap for a clean Windows 10/11 x64 machine. Run PowerShell as Administrator.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$FlutterVersion = '3.47.4'
$RepoName = 'Tikhon-prog/Navigator'
$RepoDirectory = Join-Path $env:USERPROFILE 'source\Pokolenie'
$ToolRoot = Join-Path $env:LOCALAPPDATA 'Programs\PokolenieToolchain'
$FlutterParent = Join-Path $ToolRoot ("Flutter-" + $FlutterVersion)
$FlutterSdk = Join-Path $FlutterParent 'flutter'
$AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Windows PowerShell/Terminal with Run as administrator, then rerun. UAC is needed for Visual Studio C++ Build Tools.'
}
if (-not [Environment]::Is64BitOperatingSystem) { throw 'This setup supports Windows x64 only.' }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is missing. Install/update App Installer from Microsoft Store, reboot, then rerun.'
}
$driveName = $env:SystemDrive.Substring(0, 1)
$systemDrive = Get-PSDrive -Name $driveName
$freeGiB = [math]::Round($systemDrive.Free / 1GB, 1)
Write-Host ("Free space on " + $env:SystemDrive + ": " + $freeGiB + ' GiB')
if ($systemDrive.Free -lt 25GB) { throw 'At least 25 GiB free space is recommended for Flutter, Android SDK, Visual Studio and builds.' }

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}
function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $entries = @($userPath -split ';') + @($machinePath -split ';') + @($env:Path -split ';')
    $env:Path = ($entries | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique) -join ';'
}
function Add-UserPath {
    param([string[]]$Paths)
    $old = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ -and $_.Trim() })
    $new = @()
    foreach ($item in $Paths) {
        if (-not $item) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($item).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $duplicate = $false
        foreach ($known in ($new + $old)) { if ($known.TrimEnd('\') -ieq $p) { $duplicate = $true; break } }
        if (-not $duplicate) { $new += $p }
    }
    [Environment]::SetEnvironmentVariable('Path', (($new + $old) -join ';'), 'User')
    Refresh-Path
}
function Set-UserVariable {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path ("Env:" + $Name) -Value $Value
}
function Install-WingetPackage {
    param([string]$Id, [string]$Override)
    $listed = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>$null | Out-String)
    if ($listed -match [regex]::Escape($Id)) {
        Write-Host ("Already installed: " + $Id) -ForegroundColor DarkGray
        return
    }
    Write-Step ("Installing " + $Id)
    $wingetArgs = @('install', '--id', $Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements')
    if ($Override) { $wingetArgs += @('--override', $Override) } else { $wingetArgs += '--silent' }
    & winget @args
    $code = $LASTEXITCODE
    Refresh-Path
    if ($code -ne 0) {
        $check = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>$null | Out-String)
        if ($check -notmatch [regex]::Escape($Id)) { throw ("winget failed to install " + $Id + " (exit " + $code + ").") }
        Write-Warning ("winget returned " + $code + ", but the package is installed. Continuing.")
    }
}
function Invoke-Checked {
    param([string]$File, [string[]]$Arguments)
    Write-Host ''
    Write-Host ("> " + $File + ' ' + ($Arguments -join ' ')) -ForegroundColor Cyan
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw ("Command failed (exit " + $LASTEXITCODE + "): " + $File) }
}

Write-Step 'Installing Git, GitHub CLI, Python 3.12, JDK 21 and Inno Setup'
try { & winget source update --name winget } catch { Write-Warning 'Could not update winget sources; continuing.' }
Install-WingetPackage -Id 'Git.Git'
Install-WingetPackage -Id 'GitHub.cli'
Install-WingetPackage -Id 'Python.Python.3.12'
Install-WingetPackage -Id 'Microsoft.OpenJDK.21'
Install-WingetPackage -Id 'JRSoftware.InnoSetup'

# Install or repair the native C++ toolchain, including ATL used by secure storage.
$pf64 = [Environment]::GetEnvironmentVariable('ProgramFiles')
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$vsInstallerDir = Join-Path $pf86 'Microsoft Visual Studio\Installer'
$vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    $vsOverride = '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL --add Microsoft.VisualStudio.Component.Windows10SDK.19041'
    Install-WingetPackage -Id 'Microsoft.VisualStudio.2022.BuildTools' -Override $vsOverride
    Refresh-Path
}
$vsInstaller = Join-Path $vsInstallerDir 'vs_installer.exe'
if (-not (Test-Path -LiteralPath $vswhere) -or -not (Test-Path -LiteralPath $vsInstaller)) {
    throw 'Visual Studio Installer tools were not found. Open Visual Studio Installer and repair Visual Studio 2022 Build Tools.'
}
$vsPath = (& $vswhere -latest -products '*' -version '[17.0,18.0)' -property installationPath 2>$null | Select-Object -First 1)
if (-not $vsPath) { $vsPath = (& $vswhere -latest -products '*' -property installationPath 2>$null | Select-Object -First 1) }
if (-not $vsPath) { throw 'Could not locate Visual Studio Build Tools.' }
Write-Step 'Ensuring Visual Studio C++ / ATL / Windows SDK components'
$vsArgs = @('modify', '--installPath', $vsPath, '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended', '--add', 'Microsoft.VisualStudio.Component.VC.ATL', '--add', 'Microsoft.VisualStudio.Component.Windows10SDK.19041', '--quiet', '--wait', '--norestart')
& $vsInstaller @vsArgs
$vsCode = $LASTEXITCODE
if (($vsCode -ne 0) -and ($vsCode -ne 3010) -and ($vsCode -ne 1641)) { throw ("Visual Studio installer failed with exit code " + $vsCode) }
if (($vsCode -eq 3010) -or ($vsCode -eq 1641)) { Write-Warning 'Windows may need a restart before the Windows desktop build works.' }
Refresh-Path

# Make the installed Python/Git folders take priority over WindowsApps aliases.
$gitPaths = @()
if ($pf64) { $gitPaths += (Join-Path $pf64 'Git\cmd') }
if ($pf86) { $gitPaths += (Join-Path $pf86 'Git\cmd') }
$pythonBases = @()
if ($env:LOCALAPPDATA) { $pythonBases += (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312') }
if ($pf64) { $pythonBases += (Join-Path $pf64 'Python312') }
if ($pf86) { $pythonBases += (Join-Path $pf86 'Python312') }
$pythonPaths = @()
foreach ($base in $pythonBases) {
    if (Test-Path -LiteralPath (Join-Path $base 'python.exe')) {
        $pythonPaths += $base
        $pythonPaths += (Join-Path $base 'Scripts')
    }
}
Add-UserPath -Paths ($gitPaths + $pythonPaths)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git was not found after installation. Reopen PowerShell and rerun.' }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'Python was not found after installation. Reopen PowerShell and rerun.' }
$pythonVersion = (& python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" | Out-String).Trim()
if ($pythonVersion -notmatch '^3\.12\.') { throw ("Expected Python 3.12, selected python reports " + $pythonVersion) }

# GitHub sign-in uses the official CLI browser/device flow, not a pasted password/token.
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
$gh = $null
if ($ghCmd) { $gh = $ghCmd.Source }
if (-not $gh) {
    $ghCandidate = Join-Path $pf64 'GitHub CLI\gh.exe'
    if (Test-Path -LiteralPath $ghCandidate) { $gh = $ghCandidate }
}
if (-not $gh) { throw 'GitHub CLI was not found after installation.' }
& $gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Step 'Log into GitHub in the browser'
    Write-Host 'Follow the one-time device-code instructions displayed in this terminal.'
    & $gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { throw 'GitHub login did not complete. Rerun after authorization.' }
}
Invoke-Checked -File $gh -Arguments @('auth', 'setup-git', '--hostname', 'github.com')

# Find JDK 21 and add JAVA_HOME persistently.
$jdkCandidates = @()
if ($pf64) {
    $jdkRoot = Join-Path $pf64 'Microsoft'
    if (Test-Path -LiteralPath $jdkRoot) {
        $jdkCandidates = @(Get-ChildItem -LiteralPath $jdkRoot -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Sort-Object -Property Name -Descending)
    }
}
$javaHome = $null
foreach ($candidate in $jdkCandidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate.FullName 'bin\java.exe')) { $javaHome = $candidate.FullName; break }
}
if (-not $javaHome) { throw 'Microsoft OpenJDK 21 was not found. Repair the JDK installation and rerun.' }
Set-UserVariable -Name 'JAVA_HOME' -Value $javaHome
Add-UserPath -Paths @((Join-Path $javaHome 'bin'))

# Install Android command-line SDK; no Android Studio first-run wizard is needed.
Write-Step 'Preparing Android SDK'
New-Item -ItemType Directory -Force -Path $AndroidSdk | Out-Null
Set-UserVariable -Name 'ANDROID_HOME' -Value $AndroidSdk
Set-UserVariable -Name 'ANDROID_SDK_ROOT' -Value $AndroidSdk
$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) {
    $toolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip'
    $toolsSha = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
    $downloadDir = Join-Path $env:TEMP 'PokolenieBootstrap'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $toolsZip = Join-Path $downloadDir 'android-commandline-tools.zip'
    $toolsExtract = Join-Path $downloadDir 'android-commandline-tools-extract'
    if (Test-Path -LiteralPath $toolsZip) { Remove-Item -LiteralPath $toolsZip -Force }
    if (Test-Path -LiteralPath $toolsExtract) { Remove-Item -LiteralPath $toolsExtract -Recurse -Force }
    Invoke-WebRequest -UseBasicParsing -Uri $toolsUrl -OutFile $toolsZip
    $gotSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolsZip).Hash.ToLowerInvariant()
    if ($gotSha -ne $toolsSha) { throw 'Android command-line tools checksum mismatch; refusing to install.' }
    Expand-Archive -LiteralPath $toolsZip -DestinationPath $toolsExtract -Force
    $extracted = Join-Path $toolsExtract 'cmdline-tools'
    if (-not (Test-Path -LiteralPath (Join-Path $extracted 'bin\sdkmanager.bat'))) { throw 'Android tools archive structure was unexpected.' }
    $target = Join-Path $AndroidSdk 'cmdline-tools\latest'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -Path (Join-Path $extracted '*') -Destination $target -Recurse -Force
    Remove-Item -LiteralPath $toolsZip -Force
    Remove-Item -LiteralPath $toolsExtract -Recurse -Force
}
if (-not (Test-Path -LiteralPath $sdkManager)) { throw 'Android sdkmanager.bat was not installed correctly.' }
Add-UserPath -Paths @((Join-Path $AndroidSdk 'platform-tools'), (Join-Path $AndroidSdk 'cmdline-tools\latest\bin'))
Write-Host 'Installing platform-tools, Android API 36 and build-tools 36.0.0...'
& $sdkManager "--sdk_root=$AndroidSdk" --install 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
if ($LASTEXITCODE -ne 0) { throw 'Android sdkmanager failed to install required SDK packages.' }
& $sdkManager "--sdk_root=$AndroidSdk" --licenses
if ($LASTEXITCODE -ne 0) { throw 'Android SDK license acceptance failed.' }

# Fetch the exact Flutter release from Google's manifest and verify its SHA-256.
Write-Step ("Installing Flutter " + $FlutterVersion)
$flutterExe = Join-Path $FlutterSdk 'bin\flutter.bat'
$hasFlutter = $false
if (Test-Path -LiteralPath $flutterExe) {
    $oldVersion = (& $flutterExe --version 2>&1 | Out-String)
    if ($oldVersion -match [regex]::Escape($FlutterVersion)) { $hasFlutter = $true }
}
if (-not $hasFlutter) {
    $manifest = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' -TimeoutSec 120
    $release = $manifest.releases | Where-Object { $_.version -eq $FlutterVersion -and $_.channel -eq 'stable' } | Select-Object -First 1
    if (-not $release -or -not $release.archive -or -not $release.sha256) { throw ("Flutter stable " + $FlutterVersion + ' was not found in the official manifest.') }
    $baseUrl = $manifest.base_url
    if (-not $baseUrl) { $baseUrl = 'https://storage.googleapis.com/flutter_infra_release/releases' }
    $flutterUrl = $baseUrl.TrimEnd('/') + '/' + $release.archive.TrimStart('/')
    $flutterZip = Join-Path $env:TEMP ("flutter_windows_" + $FlutterVersion + '-stable.zip')
    if (Test-Path -LiteralPath $FlutterParent) { Remove-Item -LiteralPath $FlutterParent -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $FlutterParent | Out-Null
    Write-Host ("Downloading " + $flutterUrl)
    Invoke-WebRequest -UseBasicParsing -Uri $flutterUrl -OutFile $flutterZip
    $actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $flutterZip).Hash.ToLowerInvariant()
    if ($actualSha -ne $release.sha256.ToLowerInvariant()) { throw 'Flutter SDK checksum mismatch against official manifest; refusing to install.' }
    Expand-Archive -LiteralPath $flutterZip -DestinationPath $FlutterParent -Force
    Remove-Item -LiteralPath $flutterZip -Force
}
if (-not (Test-Path -LiteralPath $flutterExe)) { throw 'flutter.bat was not found after SDK extraction.' }
Add-UserPath -Paths @((Join-Path $FlutterSdk 'bin'))
Invoke-Checked -File $flutterExe -Arguments @('--version')
Invoke-Checked -File $flutterExe -Arguments @('config', '--enable-windows-desktop')
& $flutterExe doctor --android-licenses
if ($LASTEXITCODE -ne 0) { throw 'Flutter could not validate Android SDK licenses.' }
Invoke-Checked -File $flutterExe -Arguments @('precache', '--android', '--windows')

# Clone/update repository without discarding local modifications.
Write-Step 'Downloading or updating repository'
if (Test-Path -LiteralPath $RepoDirectory) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDirectory '.git'))) { throw ("Directory exists but is not a Git repository: " + $RepoDirectory + '. Move/rename it and rerun.') }
    $origin = (& git -C $RepoDirectory remote get-url origin 2>$null | Select-Object -First 1)
    if ($origin -notmatch 'github\.com[:/]Tikhon-prog/Navigator(?:\.git)?$') { throw ("Existing repository has unexpected origin: " + $origin) }
    $changes = (& git -C $RepoDirectory status --porcelain --untracked-files=all | Out-String).Trim()
    if ($changes) { throw ("Local edits exist in " + $RepoDirectory + '. Commit/stash or move them first; the script will not delete edits.') }
    Invoke-Checked -File (Get-Command git).Source -Arguments @('-C', $RepoDirectory, 'switch', 'main')
    Invoke-Checked -File (Get-Command git).Source -Arguments @('-C', $RepoDirectory, 'pull', '--ff-only', 'origin', 'main')
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RepoDirectory) | Out-Null
    Invoke-Checked -File $gh -Arguments @('repo', 'clone', $RepoName, $RepoDirectory)
}

# This URL is public configuration, not a password/token.
$apiBase = [Environment]::GetEnvironmentVariable('POKOLENIE_API_BASE_URL')
if ([string]::IsNullOrWhiteSpace($apiBase)) { $apiBase = Read-Host 'School backend HTTPS URL (press Enter for offline-only build)' }
if (-not [string]::IsNullOrWhiteSpace($apiBase)) {
    if (($apiBase -notmatch '^https://[^/\s]+(?:/.*)?$') -or $apiBase.Contains('@')) { throw 'API URL must be public HTTPS, without credentials or whitespace.' }
    $env:POKOLENIE_API_BASE_URL = $apiBase.Trim().TrimEnd('/')
} else {
    Remove-Item Env:POKOLENIE_API_BASE_URL -ErrorAction SilentlyContinue
}

Write-Step 'Building and testing Android APK + Windows EXE'
Set-Location $RepoDirectory
$buildScript = Join-Path $RepoDirectory 'build_all_release.ps1'
if (-not (Test-Path -LiteralPath $buildScript)) { throw 'build_all_release.ps1 is missing.' }
& $buildScript
if ($LASTEXITCODE -ne 0) { throw 'build_all_release.ps1 reported an error.' }

$dist = Join-Path $RepoDirectory 'dist'
Write-Step 'Outputs'
Get-ChildItem -LiteralPath $dist -Force | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host ("Repository: " + $RepoDirectory) -ForegroundColor Green
Write-Host ("Output folder: " + $dist) -ForegroundColor Green
Write-Host 'Use Pokolenie-Setup-*.exe to install Windows. Keep the whole Pokolenie-Windows-Portable-* folder together for portable launch.'
Write-Host 'Without a permanent release signing key, the Android APK is a test build.'
Write-Host 'This script does not deploy a public school server, register school SSO, import private school data or configure Firebase server credentials.'
