#Requires -Version 5.1
# One-file setup: installs toolchains, SDKs, caches and source under C:\Dev.
$ErrorActionPreference = 'Stop'
$script:TranscriptStarted = $false
trap {
    $fatalMessage = $_.Exception.Message
    Write-Host ''
    Write-Host ("SETUP FAILED: " + $fatalMessage) -ForegroundColor Red
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
        $script:TranscriptStarted = $false
    }
    Write-Host 'Подробный журнал сохранён в C:\Dev\Logs (если запись журнала успела начаться).' -ForegroundColor Yellow
    Read-Host 'Нажми Enter, чтобы закрыть окно'
    exit 1
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Request elevation automatically, so no separate administrator command is needed.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (-not $PSCommandPath -or -not (Test-Path -LiteralPath $PSCommandPath)) { throw 'Не удалось определить путь к установщику. Скачай setup_and_build.ps1 и запусти файл напрямую.' }
    Write-Host 'Запрашиваю права администратора Windows...' -ForegroundColor Yellow
    $elevatedArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    $elevated = Start-Process -FilePath 'powershell.exe' -ArgumentList $elevatedArgs -Verb RunAs -Wait -PassThru
    exit $elevated.ExitCode
}
if (-not [Environment]::Is64BitOperatingSystem) { throw 'This setup supports Windows x64 only.' }
# Diagnose centrally enforced script policies before doing any installation.
$policyList = Get-ExecutionPolicy -List
$forcedPolicy = $policyList | Where-Object { $_.Scope -in @('MachinePolicy','UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' } | Select-Object -First 1
if ($forcedPolicy -and $forcedPolicy.ExecutionPolicy -in @('Restricted','AllSigned','RemoteSigned')) {
    Write-Host 'Обнаружена политика PowerShell, заданная администратором:' -ForegroundColor Yellow
    $policyList | Format-Table Scope, ExecutionPolicy -AutoSize | Out-Host
    Write-Host 'Команда с -ExecutionPolicy Bypass не может переопределить MachinePolicy/UserPolicy. Не меняй корпоративную политику самостоятельно; запусти скрипт на личном ПК или попроси администратора разрешить его.' -ForegroundColor Red
    Read-Host 'Нажми Enter для выхода'
    exit 1
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Не найден winget. Нужен App Installer из Microsoft Store; после его установки запусти этот файл снова.' }
$FlutterVersion = '3.47.4'
$RepoName = 'Tikhon-prog/Navigator'
$DevRoot = 'C:\Dev'
$RepoDirectory = Join-Path $DevRoot 'Pokolenie'
$ToolRoot = Join-Path $DevRoot 'Programs\PokolenieToolchain'
$FlutterParent = Join-Path $ToolRoot ("Flutter-" + $FlutterVersion)
$FlutterSdk = Join-Path $FlutterParent 'flutter'
$AndroidSdk = Join-Path $DevRoot 'Android\Sdk'
$GradleHome = Join-Path $DevRoot 'Gradle'
$PubCache = Join-Path $DevRoot 'PubCache'
$BuildTemp = Join-Path $DevRoot 'Temp'
$LogRoot = Join-Path $DevRoot 'Logs'
$logPath = Join-Path $LogRoot ("setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$pf64 = [Environment]::GetEnvironmentVariable('ProgramFiles')
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$vsInstallerDir = Join-Path $pf86 'Microsoft Visual Studio\Installer'
$vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
$requiredVsComponents = @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64','Microsoft.VisualStudio.Component.VC.ATL','Microsoft.VisualStudio.Component.Windows10SDK.19041')
$vsQueryArgs = @('-latest','-products','*','-version','[17.0,18.0)','-requires') + $requiredVsComponents + @('-property','installationPath')
$vsToolchainPath = $null
if (Test-Path -LiteralPath $vswhere) { $vsToolchainPath = (& $vswhere @vsQueryArgs 2>$null | Select-Object -First 1) }
$cDrive = Get-PSDrive -Name C -ErrorAction Stop
$cFreeGiB = [math]::Round($cDrive.Free / 1GB,1)
$minimumFreeBytes = if ($vsToolchainPath) { 20GB } else { 35GB }
Write-Host ("Свободно на C:: " + $cFreeGiB + ' GiB')
if ($cDrive.Free -lt $minimumFreeBytes) { $minimumGiB=[math]::Round($minimumFreeBytes/1GB,0); throw ("На C: свободно " + $cFreeGiB + ' GiB. Требуется не менее ' + $minimumGiB + ' GiB. Освободи место и запусти файл повторно.') }
if ($cDrive.Free -lt 25GB) { Write-Warning 'После установки и сборки свободного места станет меньше; рекомендуется освободить дополнительное место.' }
New-Item -ItemType Directory -Force -Path $DevRoot,$ToolRoot,$AndroidSdk,$GradleHome,$PubCache,$BuildTemp,$LogRoot | Out-Null
try { Start-Transcript -Path $logPath -Force | Out-Null; $script:TranscriptStarted=$true; Write-Host ("Журнал установки: "+$logPath) -ForegroundColor DarkGray } catch { Write-Warning 'Не удалось включить журналирование; установка продолжится.' }
foreach ($pair in @(@('GRADLE_USER_HOME',$GradleHome),@('PUB_CACHE',$PubCache))) { [Environment]::SetEnvironmentVariable($pair[0],$pair[1],'User'); Set-Item -Path ("Env:"+$pair[0]) -Value $pair[1] }

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
    & winget @wingetArgs
    $code = $LASTEXITCODE
    Refresh-Path
    if ($code -ne 0) {
        $check = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>$null | Out-String)
        if ($check -notmatch [regex]::Escape($Id)) { throw ("winget failed to install " + $Id + " (exit " + $code + ").") }
        Write-Warning ("winget returned " + $code + ", but the package is installed. Continuing.")
    }
}
function Find-Jdk21Home {
    $candidateList = @()
    if ($env:JAVA_HOME) { $candidateList += $env:JAVA_HOME }

    $searchRoots = @()
    if ($pf64) { $searchRoots += (Join-Path $pf64 'Microsoft') }
    $searchRoots += $ToolRoot
    if ($env:LOCALAPPDATA) { $searchRoots += (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft') }

    foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            $candidateList += @(Get-ChildItem -LiteralPath $root -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
    }

    foreach ($candidate in ($candidateList | Where-Object { $_ } | Select-Object -Unique)) {
        $javaExe = Join-Path $candidate 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $javaExe)) { continue }
        $versionText = (& $javaExe -version 2>&1 | Out-String)
        if ($versionText -match 'version "21(\.|")') { return $candidate }
    }
    return $null
}

function Install-Jdk21Portable {
    $existing = Find-Jdk21Home
    if ($existing) {
        Write-Host ("Using existing Java 21: " + $existing) -ForegroundColor DarkGray
        return
    }

    Write-Step 'Downloading verified Microsoft OpenJDK 21 ZIP'
    # Use Microsoft's official portable ZIP and its published SHA-256 sidecar.
    # This avoids a broken/mismatched winget MSI download without disabling integrity checks.
    $version = '21.0.12.1'
    $baseUrl = "https://aka.ms/download-jdk/microsoft-jdk-$version-windows-x64.zip"
    $checksumUrl = "$baseUrl.sha256sum.txt"
    $downloadDir = Join-Path $BuildTemp 'OpenJDK21'
    $extractDir = Join-Path $downloadDir 'extract'
    $zipPath = Join-Path $downloadDir "microsoft-jdk-$version-windows-x64.zip"
    $checksumPath = Join-Path $downloadDir "microsoft-jdk-$version-windows-x64.zip.sha256sum.txt"
    $destination = Join-Path $ToolRoot "jdk-$version"

    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }

    Invoke-WebRequest -UseBasicParsing -Uri $checksumUrl -OutFile $checksumPath
    $checksumText = Get-Content -LiteralPath $checksumPath -Raw
    $checksumMatch = [regex]::Match($checksumText, '(?i)\b[0-9a-f]{64}\b')
    if (-not $checksumMatch.Success) {
        throw 'Microsoft JDK checksum file did not contain a SHA-256 value; refusing to install.'
    }

    Invoke-WebRequest -UseBasicParsing -Uri $baseUrl -OutFile $zipPath
    $actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
    $expectedSha = $checksumMatch.Value.ToLowerInvariant()
    if ($actualSha -ne $expectedSha) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        throw 'Microsoft JDK ZIP checksum mismatch; refusing to install. Check network filtering or retry the official download.'
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $javaExe = Get-ChildItem -LiteralPath $extractDir -Filter 'java.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaExe) { throw 'java.exe was not found in the downloaded JDK archive.' }
    $sourceHome = Split-Path -Parent (Split-Path -Parent $javaExe.FullName)

    if (Test-Path -LiteralPath $destination) {
        throw ("JDK destination exists but is not a recognized Java 21 install: " + $destination + '. Rename that folder and rerun.')
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $sourceHome '*') -Destination $destination -Recurse -Force

    $installed = Find-Jdk21Home
    if (-not $installed) {
        throw 'The verified JDK ZIP was extracted, but Java 21 could not be validated.'
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ("Installed verified Java 21 at: " + $installed) -ForegroundColor Green
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
Install-Jdk21Portable
Install-WingetPackage -Id 'JRSoftware.InnoSetup'

# Check Visual Studio components first and modify only if required items are missing.
$vsInstaller = Join-Path $vsInstallerDir 'vs_installer.exe'
$vsPath = $null
if (Test-Path -LiteralPath $vswhere) { $vsPath = (& $vswhere -latest -products '*' -version '[17.0,18.0)' -property installationPath 2>$null | Select-Object -First 1) }
if (-not $vsPath) {
    Write-Step 'Installing Visual Studio 2022 Build Tools'
    $vsOverride = '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL --add Microsoft.VisualStudio.Component.Windows10SDK.19041'
    Install-WingetPackage -Id 'Microsoft.VisualStudio.2022.BuildTools' -Override $vsOverride
    Refresh-Path
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer did not create vswhere.exe. Check the setup log and repair Build Tools.' }
    $vsPath = (& $vswhere -latest -products '*' -version '[17.0,18.0)' -property installationPath 2>$null | Select-Object -First 1)
}
if (-not $vsPath) { throw 'Could not locate Visual Studio Build Tools after installation.' }
if (-not (Test-Path -LiteralPath $vsInstaller)) { throw 'Visual Studio installer executable was not found. Open Visual Studio Installer and repair Visual Studio 2022 Build Tools.' }
$vsToolchainPath = (& $vswhere @vsQueryArgs 2>$null | Select-Object -First 1)
if ($vsToolchainPath) {
    Write-Host 'Visual Studio C++ tools, ATL and Windows SDK are already installed.' -ForegroundColor DarkGray
} else {
    Write-Step 'Adding missing Visual Studio C++ / ATL / Windows SDK components'
    $vsArgs = @('modify','--installPath',$vsPath,'--add','Microsoft.VisualStudio.Workload.VCTools','--includeRecommended','--add','Microsoft.VisualStudio.Component.VC.ATL','--add','Microsoft.VisualStudio.Component.Windows10SDK.19041','--quiet','--norestart')
    & $vsInstaller @vsArgs
    $vsCode = $LASTEXITCODE
    if (($vsCode -ne 0) -and ($vsCode -ne 3010) -and ($vsCode -ne 1641)) { throw ("Visual Studio installer failed with exit code " + $vsCode) }
    if (($vsCode -eq 3010) -or ($vsCode -eq 1641)) { Write-Warning 'Windows may need a restart before the Windows desktop build works.' }
    Refresh-Path
    $vsToolchainPath = (& $vswhere @vsQueryArgs 2>$null | Select-Object -First 1)
    if (-not $vsToolchainPath) { throw 'Visual Studio is missing a required C++/ATL/Windows SDK component after modify.' }
}

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
$javaHome = Find-Jdk21Home
if (-not $javaHome) { throw 'Java 21 was not found after the verified ZIP installation.' }
Set-UserVariable -Name 'JAVA_HOME' -Value $javaHome
Add-UserPath -Paths @((Join-Path $javaHome 'bin'))

# Pin Android command-line tools 19.0. The newer command-line package changed the legacy license flow
# and caused this project's previous sdkmanager --licenses call to fail.
Write-Step 'Preparing Android SDK'
New-Item -ItemType Directory -Force -Path $AndroidSdk | Out-Null
Set-UserVariable -Name 'ANDROID_HOME' -Value $AndroidSdk
Set-UserVariable -Name 'ANDROID_SDK_ROOT' -Value $AndroidSdk
$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$toolsRevision = '19.0'
$installedToolsRevision = $null
$toolsProperties = Join-Path $AndroidSdk 'cmdline-tools\latest\source.properties'
if (Test-Path -LiteralPath $toolsProperties) {
    $toolsMetadata = Get-Content -LiteralPath $toolsProperties -Raw
    if ($toolsMetadata -match '(?m)^Pkg\.Revision\s*=\s*([^\r\n]+)') {
        $installedToolsRevision = $Matches[1].Trim()
    }
}
# v23+ uses a new Android CLI wrapper for sdkmanager --licenses; Flutter 3.47 still
# expects the legacy interactive license command. Replace it if either version or wrapper is wrong.
$needsToolsInstall = $installedToolsRevision -ne $toolsRevision -or -not (Test-Path -LiteralPath $sdkManager)
if (-not $needsToolsInstall) {
    $sdkManagerText = Get-Content -LiteralPath $sdkManager -Raw
    if ($sdkManagerText -match 'Android CLI will be used instead') { $needsToolsInstall = $true }
}
if ($needsToolsInstall) {
    Write-Host 'Installing pinned Android command-line tools 19.0...'
    $toolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
    $toolsSha = '98b565cb657b012dae6794cefc0f66ae1efb4690c699b78a614b4a6a3505b003'
    $downloadDir = Join-Path $BuildTemp 'PokolenieBootstrap'
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
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $extracted '*') -Destination $target -Recurse -Force
    Remove-Item -LiteralPath $toolsZip -Force
    Remove-Item -LiteralPath $toolsExtract -Recurse -Force
}
if (-not (Test-Path -LiteralPath $sdkManager)) { throw 'Android sdkmanager.bat was not installed correctly.' }
$installedToolsMetadata = Get-Content -LiteralPath $toolsProperties -Raw
if ($installedToolsMetadata -notmatch '(?m)^Pkg\.Revision\s*=\s*19\.0\s*$') {
    throw 'The downloaded Android command-line tools are not revision 19.0; refusing to continue with the incompatible license CLI.'
}
$sdkManagerText = Get-Content -LiteralPath $sdkManager -Raw
if ($sdkManagerText -match 'Android CLI will be used instead') {
    throw 'The downloaded SDK manager uses the newer Android CLI wrapper. The legacy 19.0 license manager is required for this Flutter toolchain.'
}
Add-UserPath -Paths @((Join-Path $AndroidSdk 'platform-tools'), (Join-Path $AndroidSdk 'cmdline-tools\latest\bin'))
# Accept licenses before installing packages; otherwise sdkmanager skips them.
Write-Host 'Accept the Android SDK license terms in the terminal when prompted...'
& $sdkManager "--sdk_root=$AndroidSdk" --licenses
if ($LASTEXITCODE -ne 0) { throw 'Android SDK license acceptance failed. Ensure command-line tools 19.0 is installed.' }
# Check each Android package and only ask sdkmanager for components that are absent.
$missingSdkPackages = @()
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platform-tools\adb.exe'))) { $missingSdkPackages += 'platform-tools' }
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platforms\android-36\android.jar'))) { $missingSdkPackages += 'platforms;android-36' }
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'build-tools\36.0.0\aapt.exe'))) { $missingSdkPackages += 'build-tools;36.0.0' }
if ($missingSdkPackages.Count -gt 0) {
    Write-Host ('Installing missing Android SDK packages: ' + ($missingSdkPackages -join ', '))
    & $sdkManager "--sdk_root=$AndroidSdk" --install @missingSdkPackages
    if ($LASTEXITCODE -ne 0) { throw 'Android sdkmanager failed to install required SDK packages.' }
} else {
    Write-Host 'Android platform-tools, API 36 and build-tools 36.0.0 are already present.' -ForegroundColor DarkGray
}

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
    $flutterZip = Join-Path $BuildTemp ("flutter_windows_" + $FlutterVersion + '-stable.zip')
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

# No manual configuration is required. Without a configured HTTPS endpoint, build offline-first.
$apiBase = [Environment]::GetEnvironmentVariable('POKOLENIE_API_BASE_URL')
if ([string]::IsNullOrWhiteSpace($apiBase)) {
    $apiBase = ''
    Remove-Item Env:POKOLENIE_API_BASE_URL -ErrorAction SilentlyContinue
    Write-Host 'Backend URL is not configured; creating the offline-first build.' -ForegroundColor Yellow
} else {
    if (($apiBase -notmatch '^https://[^/\s]+(?:/.*)?$') -or $apiBase.Contains('@')) { throw 'POKOLENIE_API_BASE_URL must be a public HTTPS URL, without credentials or whitespace.' }
    $env:POKOLENIE_API_BASE_URL = $apiBase.Trim().TrimEnd('/')
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
Write-Host ("Installation log: " + $logPath) -ForegroundColor DarkGray
if ($script:TranscriptStarted) { Stop-Transcript | Out-Null; $script:TranscriptStarted = $false }
Read-Host 'Готово. Нажми Enter, чтобы закрыть окно'
