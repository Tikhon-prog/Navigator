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
$PinnedFlutterVersion = '3.47.9'
$FlutterVersion = $PinnedFlutterVersion
$UseExistingFlutter = $false
$RepoName = 'Tikhon-prog/Navigator'
$DevRoot = 'C:\Dev'
$RepoDirectory = Join-Path $DevRoot 'Pokolenie'
$ToolRoot = Join-Path $DevRoot 'Programs\PokolenieToolchain'
$FlutterParent = Join-Path $ToolRoot ("Flutter-" + $PinnedFlutterVersion)
$FlutterSdk = Join-Path $FlutterParent 'flutter'
# Reuse any existing Flutter SDK before considering a download.
# The setup may run elevated under a different Windows account, so search all
# local user profiles (including C:\Users\pc\flutter\flutter) and the inherited PATH.
$flutterCandidates = @()
$pathFlutter = Get-Command 'flutter.bat' -ErrorAction SilentlyContinue
if ($pathFlutter -and $pathFlutter.Source) {
    $flutterCandidates += (Split-Path -Parent (Split-Path -Parent $pathFlutter.Source))
}
if ($env:USERPROFILE) {
    $flutterCandidates += (Join-Path $env:USERPROFILE 'flutter')
    $flutterCandidates += (Join-Path $env:USERPROFILE 'flutter\flutter')
}
foreach ($profileDir in @(Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
    $flutterCandidates += (Join-Path $profileDir.FullName 'flutter')
    $flutterCandidates += (Join-Path $profileDir.FullName 'flutter\flutter')
    $flutterCandidates += (Join-Path $profileDir.FullName 'src\flutter')
}
$flutterCandidates += 'C:\src\flutter'
$flutterCandidates += (Join-Path $ToolRoot ("Flutter-" + $PinnedFlutterVersion + '\flutter'))
$seenFlutter = @{}
foreach ($candidateSdk in $flutterCandidates) {
    if ([string]::IsNullOrWhiteSpace($candidateSdk)) { continue }
    $candidateExe = Join-Path $candidateSdk 'bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $candidateExe -PathType Leaf)) { continue }
    $normalizedSdk = [IO.Path]::GetFullPath($candidateSdk).TrimEnd('\')
    if ($seenFlutter.ContainsKey($normalizedSdk.ToLowerInvariant())) { continue }
    $seenFlutter[$normalizedSdk.ToLowerInvariant()] = $true

    $candidateVersionText = (& $candidateExe --version 2>&1 | Out-String)
    if ($candidateVersionText -match 'Flutter\s+(\d+\.\d+\.\d+)') {
        $FlutterVersion = $Matches[1]
        $FlutterSdk = $normalizedSdk
        $FlutterParent = $null
        $UseExistingFlutter = $true
        if ($FlutterVersion -eq $PinnedFlutterVersion) {
            Write-Host ("Reusing existing Flutter " + $FlutterVersion + " at " + $FlutterSdk) -ForegroundColor Green
        } else {
            Write-Warning ("Found Flutter " + $FlutterVersion + " at " + $FlutterSdk + ". Reusing it instead of downloading another SDK (the pinned version is " + $PinnedFlutterVersion + ").")
        }
        break
    }
}
# Reuse Android Studio's SDK when it already exists; otherwise use the script-managed location.
$AndroidSdk = $null
$configuredAndroidSdk = $env:ANDROID_SDK_ROOT
if ([string]::IsNullOrWhiteSpace($configuredAndroidSdk)) { $configuredAndroidSdk = $env:ANDROID_HOME }
if (-not [string]::IsNullOrWhiteSpace($configuredAndroidSdk) -and (Test-Path -LiteralPath $configuredAndroidSdk)) {
    $AndroidSdk = $configuredAndroidSdk
} elseif ($env:LOCALAPPDATA -and (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
} else {
    $AndroidSdk = Join-Path $DevRoot 'Android\Sdk'
}
$GradleHome = Join-Path $DevRoot 'Gradle'
$PubCache = Join-Path $DevRoot 'PubCache'
$BuildTemp = Join-Path $DevRoot 'Temp'
$LogRoot = Join-Path $DevRoot 'Logs'
$logPath = Join-Path $LogRoot ("setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$pf64 = [Environment]::GetEnvironmentVariable('ProgramFiles')
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
# Visual Studio may place its installer under either Program Files root.
$vsInstallerDir = $null
$vswhere = $null
$vsInstallerRoots = @()
foreach ($root in @($pf86,$pf64,'C:\Program Files (x86)','C:\Program Files')) {
    if (-not [string]::IsNullOrWhiteSpace($root)) {
        $candidateDir = Join-Path $root 'Microsoft Visual Studio\Installer'
        if (Test-Path -LiteralPath $candidateDir) { $vsInstallerRoots += $candidateDir }
    }
}
foreach ($candidateDir in ($vsInstallerRoots | Select-Object -Unique)) {
    if ((Test-Path -LiteralPath (Join-Path $candidateDir 'vswhere.exe')) -or (Test-Path -LiteralPath (Join-Path $candidateDir 'vs_installer.exe'))) {
        $vsInstallerDir = $candidateDir
        $vswhere = Join-Path $candidateDir 'vswhere.exe'
        break
    }
}
if (-not $vsInstallerDir) {
    $vsInstallerDir = Join-Path 'C:\Program Files (x86)' 'Microsoft Visual Studio\Installer'
    $vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
}
$requiredVsComponents = @('Microsoft.VisualStudio.Workload.NativeDesktop','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','Microsoft.VisualStudio.Component.VC.ATL','Microsoft.VisualStudio.Component.Windows11SDK.26100')
$vsQueryArgs = @('-latest','-products','*','-version','[17.0,19.0)','-requires') + $requiredVsComponents + @('-property','installationPath')
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
function Repair-WingetSource {
    Write-Warning 'winget source metadata is unavailable. Resetting and refreshing the official winget source.'
    & winget source reset --force
    if ($LASTEXITCODE -ne 0) {
        throw ("winget source reset failed with exit code " + $LASTEXITCODE + ". Repair App Installer from Windows Settings or Microsoft Store.")
    }
    & winget source update --name winget
    if ($LASTEXITCODE -ne 0) {
        throw ("winget source update failed with exit code " + $LASTEXITCODE + ". Repair App Installer from Windows Settings or Microsoft Store.")
    }
}

function Install-WingetPackage {
    param([string]$Id, [string]$Override)
    $listed = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>&1 | Out-String)
    if ($listed -match '0x8a15000f|source.*(unavailable|failed)|Отсутствуют данные, требуемые источником') {
        Repair-WingetSource
        $listed = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>&1 | Out-String)
    }
    if ($listed -match [regex]::Escape($Id)) {
        Write-Host ("Already installed: " + $Id) -ForegroundColor DarkGray
        return
    }
    Write-Step ("Installing " + $Id)
    $wingetArgs = @('install', '--id', $Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements')
    if ($Override) { $wingetArgs += @('--override', $Override) } else { $wingetArgs += '--silent' }
    & winget @wingetArgs
    $code = $LASTEXITCODE
    if ($code -eq -1978335217 -or $code -eq 0x8a15000f) {
        Repair-WingetSource
        & winget @wingetArgs
        $code = $LASTEXITCODE
    }
    Refresh-Path
    if ($code -ne 0) {
        $check = (& winget list --id $Id --exact --source winget --accept-source-agreements 2>$null | Out-String)
        if ($check -notmatch [regex]::Escape($Id)) { throw ("winget failed to install " + $Id + " (exit " + $code + ").") }
        Write-Warning ("winget returned " + $code + ", but the package is installed. Continuing.")
    }
}
function Install-Python312Portable {
    $pythonHome = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312' } else { Join-Path $ToolRoot 'Python312' }
    $pythonExe = Join-Path $pythonHome 'python.exe'
    if (Test-Path -LiteralPath $pythonExe) {
        $v = (& $pythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:2])))" 2>$null | Out-String).Trim()
        if ($v -eq '3.12') {
            Write-Host ("Using existing Python 3.12: " + $pythonHome) -ForegroundColor DarkGray
            return
        }
    }

    Write-Step 'Downloading official Python 3.12.10 installer (winget is not required)'
    $installer = Join-Path $BuildTemp 'python-3.12.10-amd64.exe'
    $url = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    $signature = Get-AuthenticodeSignature -FilePath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        throw 'Python installer signature is not valid or is not signed by the Python Software Foundation.'
    }
    New-Item -ItemType Directory -Force -Path $pythonHome | Out-Null
    $args = @('/quiet','InstallAllUsers=0','PrependPath=0','Include_launcher=1','Include_test=0',('TargetDir="' + $pythonHome + '"'))
    $proc = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw ("Python installer failed with exit code " + $proc.ExitCode)
    }
    if (-not (Test-Path -LiteralPath $pythonExe)) { throw 'Python installer finished but python.exe was not found.' }
    $v = (& $pythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:2])))" 2>$null | Out-String).Trim()
    if ($v -ne '3.12') { throw ("Expected Python 3.12, installed version reports " + $v) }
    Write-Host ("Installed verified Python 3.12 at: " + $pythonHome) -ForegroundColor Green
}

function Find-Jdk21Home {
    $candidateList = @()
    if ($env:JAVA_HOME) { $candidateList += $env:JAVA_HOME }

    $searchRoots = @()
    if ($pf64) { $searchRoots += (Join-Path $pf64 'Java') }
    $searchRoots += $ToolRoot
    if ($env:LOCALAPPDATA) { $searchRoots += (Join-Path $env:LOCALAPPDATA 'Programs\Java') }

    foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            $candidateList += @(Get-ChildItem -LiteralPath $root -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
    }

    foreach ($candidate in ($candidateList | Where-Object { $_ } | Select-Object -Unique)) {
        $javaExe = Join-Path $candidate 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $javaExe)) { continue }
        # java -version writes to STDERR. With $ErrorActionPreference = 'Stop',
        # Windows PowerShell can turn that normal output into a terminating error.
        # Temporarily allow native STDERR so an older JAVA_HOME (for example JDK 17)
        # is skipped and the search continues to the managed Temurin JDK 21 installation.
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $versionOutput = & $javaExe -version 2>&1
            $versionText = ($versionOutput | ForEach-Object { $_.ToString() }) -join "`n"
        } catch {
            $versionText = ''
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($versionText -match 'version "21(\.|")') { return $candidate }
    }
    return $null
}


function Find-InnoSetupCompiler {
    $candidates = @()

    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates += $command.Source
    }

    if ($pf64) {
        $candidates += (Join-Path $pf64 'Inno Setup 7\ISCC.exe')
        $candidates += (Join-Path $pf64 'Inno Setup 6\ISCC.exe')
    }
    if ($pf86) {
        $candidates += (Join-Path $pf86 'Inno Setup 7\ISCC.exe')
        $candidates += (Join-Path $pf86 'Inno Setup 6\ISCC.exe')
    }

    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($registryRoot in $registryRoots) {
        $entries = @(Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue)
        foreach ($entry in $entries) {
            if ($entry.DisplayName -match '^Inno Setup') {
                if ($entry.InstallLocation) {
                    $candidates += (Join-Path $entry.InstallLocation 'ISCC.exe')
                }

                if ($entry.DisplayIcon) {
                    $iconValue = ([string]$entry.DisplayIcon).Trim()
                    $iconPath = $iconValue
                    if ($iconPath.StartsWith('"')) {
                        $closingQuote = $iconPath.IndexOf('"', 1)
                        if ($closingQuote -gt 1) {
                            $iconPath = $iconPath.Substring(1, $closingQuote - 1)
                        }
                    } else {
                        $iconPath = ($iconPath -split ',')[0].Trim()
                    }

                    if ((Split-Path -Leaf $iconPath) -ieq 'ISCC.exe') {
                        $candidates += $iconPath
                    } elseif ($iconPath) {
                        $candidates += (Join-Path (Split-Path -Parent $iconPath) 'ISCC.exe')
                    }
                }
            }
        }
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Install-InnoSetup {
    $existingCompiler = Find-InnoSetupCompiler
    if ($existingCompiler) {
        Write-Host ("Inno Setup compiler already installed: " + $existingCompiler) -ForegroundColor DarkGray
        return
    }

    Write-Step 'Downloading official Inno Setup 7.1.1 (winget is not required)'
    $installer = Join-Path $BuildTemp 'innosetup-7.1.1-x64.exe'
    $url = 'https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-7.1.1-x64.exe'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer

    $signature = Get-AuthenticodeSignature -FilePath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Pyrsys B\.V\.') {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        throw 'Inno Setup installer signature is not valid or is not signed by Pyrsys B.V.; refusing to install.'
    }

    $proc = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-') -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw ("Inno Setup installer failed with exit code " + $proc.ExitCode)
    }

    $installedCompiler = Find-InnoSetupCompiler
    if (-not $installedCompiler) {
        throw 'Inno Setup installer finished, but ISCC.exe could not be located.'
    }

    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    Write-Host ("Installed Inno Setup at: " + $installedCompiler) -ForegroundColor Green
}

function Install-Jdk21Portable {
    $existing = Find-Jdk21Home
    if ($existing) {
        Write-Host ("Using existing compatible Java 21: " + $existing) -ForegroundColor DarkGray
        return
    }

    Write-Step 'Downloading verified Eclipse Temurin JDK 21.0.13+9 ZIP'
    # Use the official Eclipse Temurin JDK 21.0.13+9 release ZIP and checksum sidecar.
    # Verify SHA-256 before extracting the archive.
    $version = '21.0.13+9'
    $baseUrl = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip'
    $checksumUrl = $baseUrl + '.sha256.txt'
    $downloadDir = Join-Path $BuildTemp 'Temurin21'
    $extractDir = Join-Path $downloadDir 'extract'
    $zipPath = Join-Path $downloadDir 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip'
    $checksumPath = Join-Path $downloadDir 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip.sha256.txt'
    $destination = Join-Path $ToolRoot ("jdk-" + $version)

    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }

    Invoke-WebRequest -UseBasicParsing -Uri $checksumUrl -OutFile $checksumPath
    $checksumText = Get-Content -LiteralPath $checksumPath -Raw
    $checksumMatch = [regex]::Match($checksumText, '(?i)\b[0-9a-f]{64}\b')
    if (-not $checksumMatch.Success) {
        throw 'Eclipse Temurin checksum file did not contain a SHA-256 value; refusing to install.'
    }

    Invoke-WebRequest -UseBasicParsing -Uri $baseUrl -OutFile $zipPath
    $actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
    $expectedSha = $checksumMatch.Value.ToLowerInvariant()
    if ($actualSha -ne $expectedSha) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        throw 'Eclipse Temurin ZIP checksum mismatch; refusing to install. Check network filtering or retry the official download.'
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $javaExe = Get-ChildItem -LiteralPath $extractDir -Filter 'java.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaExe) {
        throw 'java.exe was not found in the downloaded JDK archive.'
    }
    $sourceHome = Split-Path -Parent (Split-Path -Parent $javaExe.FullName)

    if (Test-Path -LiteralPath $destination) {
        throw ("JDK destination exists but is not a recognized Temurin Java 21 install: " + $destination + '. Rename that folder and rerun.')
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $sourceHome '*') -Destination $destination -Recurse -Force

    $installed = Find-Jdk21Home
    if (-not $installed) {
        throw 'The verified JDK ZIP was extracted, but Temurin Java 21 could not be validated.'
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ("Installed verified Temurin Java 21 at: " + $installed) -ForegroundColor Green
}

function Invoke-Checked {
    param([string]$File, [string[]]$Arguments)
    Write-Host ''
    Write-Host ("> " + $File + ' ' + ($Arguments -join ' ')) -ForegroundColor Cyan
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw ("Command failed (exit " + $LASTEXITCODE + "): " + $File) }
}

function Get-RunningVisualStudioInstaller {
    param([string]$InstallerDirectory)
    $expectedPaths = @(
        (Join-Path $InstallerDirectory 'setup.exe'),
        (Join-Path $InstallerDirectory 'vs_installer.exe')
    )
    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='setup.exe' OR Name='vs_installer.exe'" -ErrorAction Stop)
    } catch {
        throw ("Could not check whether Visual Studio Installer is already running: " + $_.Exception.Message)
    }
    return @($processes | Where-Object {
        $_.ExecutablePath -and ($expectedPaths -contains $_.ExecutablePath)
    })
}

function Wait-ForVisualStudioInstallerIdle {
    param(
        [string]$InstallerDirectory,
        [int]$TimeoutSeconds = 900
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastNotice = -15
    while ($true) {
        $running = @(Get-RunningVisualStudioInstaller -InstallerDirectory $InstallerDirectory)
        if ($running.Count -eq 0) { return }
        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $pids = ($running | ForEach-Object { $_.ProcessId }) -join ', '
            throw ("Visual Studio Installer is still running (PID: " + $pids + "). Close the Visual Studio Installer window and rerun the script.")
        }
        if (($timer.Elapsed.TotalSeconds - $lastNotice) -ge 15) {
            $pids = ($running | ForEach-Object { $_.ProcessId }) -join ', '
            Write-Host ("Waiting for the other Visual Studio Installer process to finish (PID: " + $pids + ")...") -ForegroundColor Yellow
            $lastNotice = [int]$timer.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 5
    }
}

Write-Step 'Installing Git, Python 3.12, verified Temurin JDK 21 and Inno Setup'
try { & winget source update --name winget } catch { Write-Warning 'Could not update winget sources; continuing.' }

# Reuse an existing Git installation before asking winget to install it.
# Elevated PowerShell may have a different PATH from the CMD window that launched it.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $gitCandidates = @()
    if ($pf64) { $gitCandidates += (Join-Path $pf64 'Git\cmd\git.exe') }
    if ($pf86) { $gitCandidates += (Join-Path $pf86 'Git\cmd\git.exe') }
    if ($env:LOCALAPPDATA) { $gitCandidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe') }
    foreach ($profileDir in @(Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
        $gitCandidates += (Join-Path $profileDir.FullName 'AppData\Local\Programs\Git\cmd\git.exe')
    }
    $installedGit = $gitCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($installedGit) {
        $env:Path = (Split-Path -Parent $installedGit) + ';' + $env:Path
        Write-Host ("Using existing Git at " + $installedGit) -ForegroundColor DarkGray
    }
}
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host 'Git is already installed; skipping winget Git installation.' -ForegroundColor DarkGray
} else {
    Install-WingetPackage -Id 'Git.Git'
}
Install-Python312Portable
Install-Jdk21Portable
Install-InnoSetup

# Reuse the already installed Visual Studio instance (Community, Professional,
# Enterprise or Build Tools). Do not use winget here: its source metadata can fail
# independently of Visual Studio, even when the VS installer is already present.
$vsInstaller = if ($vsInstallerDir) { Join-Path $vsInstallerDir 'vs_installer.exe' } else { $null }
$vsPath = $null
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    $vsPath = (& $vswhere -latest -products '*' -version '[17.0,19.0)' -property installationPath 2>$null | Select-Object -First 1)
}

# Fallback if vswhere is missing or cannot enumerate the installed VS 2026 instance.
if (-not $vsPath) {
    foreach ($root in @($pf64,$pf86,'C:\Program Files','C:\Program Files (x86)')) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $vsBase = Join-Path $root 'Microsoft Visual Studio'
        if (-not (Test-Path -LiteralPath $vsBase)) { continue }
        foreach ($versionDir in (Get-ChildItem -LiteralPath $vsBase -Directory -ErrorAction SilentlyContinue)) {
            foreach ($edition in @('Community','Professional','Enterprise','BuildTools')) {
                $candidate = Join-Path $versionDir.FullName $edition
                $devenv = Join-Path $candidate 'Common7\IDE\devenv.exe'
                $msbuild = Join-Path $candidate 'MSBuild\Current\Bin\MSBuild.exe'
                if ((Test-Path -LiteralPath $devenv) -or (Test-Path -LiteralPath $msbuild)) {
                    $vsPath = $candidate.TrimEnd('\')
                    break
                }
            }
            if ($vsPath) { break }
        }
        if ($vsPath) { break }
    }
}

# If no VS instance exists, download the official Microsoft bootstrapper directly.
# This avoids winget entirely and installs only the required native C++ toolchain.
if (-not $vsPath) {
    Write-Step 'Installing Visual Studio 2026 Build Tools directly from Microsoft'
    $vsBootstrapper = Join-Path $BuildTemp 'vs_BuildTools_2026.exe'
    $vsBootstrapperUrl = 'https://aka.ms/vs/18/release/vs_BuildTools.exe'
    Invoke-WebRequest -UseBasicParsing -Uri $vsBootstrapperUrl -OutFile $vsBootstrapper
    $vsSignature = Get-AuthenticodeSignature -FilePath $vsBootstrapper
    if ($vsSignature.Status -ne 'Valid' -or $vsSignature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        Remove-Item -LiteralPath $vsBootstrapper -Force -ErrorAction SilentlyContinue
        throw 'Visual Studio bootstrapper signature is not valid or is not signed by Microsoft Corporation.'
    }
    $vsBootstrapArgs = @(
        '--wait','--quiet','--norestart',
        '--add','Microsoft.VisualStudio.Workload.NativeDesktop',
        '--add','Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add','Microsoft.VisualStudio.Component.VC.ATL',
        '--add','Microsoft.VisualStudio.Component.Windows11SDK.26100'
    )
    $vsProc = Start-Process -FilePath $vsBootstrapper -ArgumentList $vsBootstrapArgs -Wait -PassThru
    if (($vsProc.ExitCode -ne 0) -and ($vsProc.ExitCode -ne 3010) -and ($vsProc.ExitCode -ne 1641)) {
        throw ("Visual Studio bootstrapper failed with exit code " + $vsProc.ExitCode)
    }
    if (($vsProc.ExitCode -eq 3010) -or ($vsProc.ExitCode -eq 1641)) {
        Write-Warning 'Windows may need a restart before the Windows desktop build works.'
    }
    Refresh-Path
    if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
        $vsPath = (& $vswhere -latest -products '*' -version '[17.0,19.0)' -property installationPath 2>$null | Select-Object -First 1)
    }
    if (-not $vsPath) {
        throw 'Visual Studio installer completed, but no Visual Studio 2026 instance could be located.'
    }
}

# Find vs_installer.exe beside vswhere, or in the standard installer directory.
if (-not $vsInstaller -or -not (Test-Path -LiteralPath $vsInstaller)) {
    $installerCandidates = @()
    foreach ($root in @($pf86,$pf64,'C:\Program Files (x86)','C:\Program Files')) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $installerCandidates += (Join-Path $root 'Microsoft Visual Studio\Installer\vs_installer.exe')
        }
    }
    $vsInstaller = $installerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $vsInstaller -or -not (Test-Path -LiteralPath $vsInstaller)) {
    throw 'Visual Studio Installer executable was not found. Open Visual Studio Installer and repair the existing Visual Studio installation.'
}

$vsToolchainPath = $null
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    $vsToolchainPath = (& $vswhere @vsQueryArgs 2>$null | Select-Object -First 1)
}
if ($vsToolchainPath) {
    Write-Host 'Visual Studio C++ tools, ATL and Windows SDK are already installed.' -ForegroundColor DarkGray
} else {
    Write-Step 'Adding missing Visual Studio C++ / ATL / Windows SDK components'
    $vsArgs = @('modify','--installPath',$vsPath,'--add','Microsoft.VisualStudio.Workload.NativeDesktop','--includeRecommended','--add','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','--add','Microsoft.VisualStudio.Component.VC.ATL','--add','Microsoft.VisualStudio.Component.Windows11SDK.26100','--quiet','--norestart')
    $modifySucceeded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        # Visual Studio Installer has a single-instance lock. A second invocation may
        # return exit code 0 without applying anything if the GUI/installer is already open.
        Wait-ForVisualStudioInstallerIdle -InstallerDirectory $vsInstallerDir -TimeoutSeconds 900
        Write-Host ("Visual Studio component update, attempt " + $attempt + " of 3...")
        & $vsInstaller @vsArgs
        $vsCode = $LASTEXITCODE
        if (($vsCode -ne 0) -and ($vsCode -ne 3010) -and ($vsCode -ne 1641)) {
            throw ("Visual Studio installer failed with exit code " + $vsCode)
        }
        if (($vsCode -eq 3010) -or ($vsCode -eq 1641)) {
            Write-Warning 'Windows may need a restart before the Windows desktop build works.'
        }
        # Wait for setup.exe to release the installer lock and finish applying packages.
        Wait-ForVisualStudioInstallerIdle -InstallerDirectory $vsInstallerDir -TimeoutSeconds 1800
        Refresh-Path
        if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
            $vsToolchainPath = (& $vswhere @vsQueryArgs 2>$null | Select-Object -First 1)
        }
        if ($vsToolchainPath) {
            $modifySucceeded = $true
            break
        }
        if ($attempt -lt 3) {
            Write-Warning 'The installer returned, but Visual Studio still reports missing components. Retrying after the installer lock is released.'
            Start-Sleep -Seconds 5
        }
    }
    if (-not $modifySucceeded) {
        throw 'Visual Studio still reports missing C++/ATL/Windows SDK components after 3 modify attempts. Open Visual Studio Installer, check the Community installation for pending actions, apply them, close the installer, and rerun.'
    }
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

# GitHub CLI is optional. Prefer normal Git + Git Credential Manager, which can open a browser.
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
$gh = $null
if ($ghCmd) { $gh = $ghCmd.Source }
if (-not $gh -and $pf64) {
    $ghCandidate = Join-Path $pf64 'GitHub CLI\gh.exe'
    if (Test-Path -LiteralPath $ghCandidate) { $gh = $ghCandidate }
}
if ($gh) {
    $ghLoggedIn = $false
    try {
        & $gh auth status --hostname github.com *> $null
        $ghLoggedIn = ($LASTEXITCODE -eq 0)
    } catch { $ghLoggedIn = $false }
    if ($ghLoggedIn) {
        try { Invoke-Checked -File $gh -Arguments @('auth', 'setup-git', '--hostname', 'github.com') }
        catch { Write-Warning 'Could not configure Git through gh; Git Credential Manager can still be used.' }
    } else {
        Write-Host 'gh is not authenticated. The script will use Git Credential Manager during clone instead.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'gh is not installed; that is OK. Git + Git Credential Manager will be used for repository access.' -ForegroundColor DarkGray
}

# Find Temurin JDK 21 and add JAVA_HOME persistently.
$javaHome = Find-Jdk21Home
if (-not $javaHome) { throw 'Temurin Java 21 was not found after the verified ZIP installation.' }
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
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'ndk\28.2.13676358\source.properties'))) { $missingSdkPackages += 'ndk;28.2.13676358' }
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'cmake\3.22.1\bin\cmake.exe'))) { $missingSdkPackages += 'cmake;3.22.1' }
if ($missingSdkPackages.Count -gt 0) {
    Write-Host ('Installing missing Android SDK packages: ' + ($missingSdkPackages -join ', '))
    & $sdkManager "--sdk_root=$AndroidSdk" --install @missingSdkPackages
    if ($LASTEXITCODE -ne 0) { throw 'Android sdkmanager failed to install required SDK packages.' }
} else {
    Write-Host 'Android platform-tools, API 36, build-tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1 are already present.' -ForegroundColor DarkGray
}

# Use the discovered Flutter SDK. This bootstrap does not download or replace Flutter.
Write-Step ("Using existing Flutter " + $FlutterVersion)
$flutterExe = Join-Path $FlutterSdk 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterExe -PathType Leaf)) {
    throw 'Flutter was not found in the detected SDK path. Install Flutter manually or correct the Flutter path; this script will not download a duplicate.'
}
$verifiedFlutterText = (& $flutterExe --version 2>&1 | Out-String)
if ($verifiedFlutterText -notmatch ('Flutter\s+' + [regex]::Escape($FlutterVersion))) {
    throw 'The existing Flutter executable could not be validated; refusing to download or replace it.'
}
Add-UserPath -Paths @((Join-Path $FlutterSdk 'bin'))
Invoke-Checked -File $flutterExe -Arguments @('--version')
Invoke-Checked -File $flutterExe -Arguments @('config', '--enable-windows-desktop')
& $flutterExe doctor --android-licenses
if ($LASTEXITCODE -ne 0) { throw 'Flutter could not validate Android SDK licenses.' }
Write-Host 'Skipping Flutter precache: the build will use existing artifacts and fetch only a missing target artifact if required.' -ForegroundColor DarkGray

# Clone/update repository without discarding local modifications.
# If the script was launched from a freshly cloned private repository in the normal user's
# session, stage that authenticated clone into C:\Dev instead of authenticating again as the
# separate administrator account.
Write-Step 'Downloading or updating repository'
$bootstrapRoot = Split-Path -Parent $PSCommandPath
$bootstrapOrigin = $null
if (Test-Path -LiteralPath (Join-Path $bootstrapRoot '.git')) {
    $bootstrapOrigin = (& git -C $bootstrapRoot remote get-url origin 2>$null | Select-Object -First 1)
}
if (Test-Path -LiteralPath $RepoDirectory) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDirectory '.git'))) {
        throw ("Directory exists but is not a Git repository: " + $RepoDirectory + '. Move/rename it and rerun.')
    }
    $origin = (& git -C $RepoDirectory remote get-url origin 2>$null | Select-Object -First 1)
    if ($origin -notmatch 'github\.com[:/]Tikhon-prog/Navigator(?:\.git)?$') {
        throw ("Existing repository has unexpected origin: " + $origin)
    }
    $changes = (& git -C $RepoDirectory status --porcelain --untracked-files=all | Out-String).Trim()
    if ($changes) {
        throw ("Local edits exist in " + $RepoDirectory + '. Commit/stash or move them first; the script will not delete edits.')
    }
    Invoke-Checked -File (Get-Command git).Source -Arguments @('-C', $RepoDirectory, 'switch', 'main')
    Invoke-Checked -File (Get-Command git).Source -Arguments @('-C', $RepoDirectory, 'pull', '--ff-only', 'origin', 'main')
} elseif ($bootstrapOrigin -match 'github\.com[:/]Tikhon-prog/Navigator(?:\.git)?$') {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RepoDirectory) | Out-Null
    Write-Host 'Using the private repository clone downloaded before elevation; no second GitHub sign-in is needed.' -ForegroundColor DarkGray
    & robocopy $bootstrapRoot $RepoDirectory /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    $copyCode = $LASTEXITCODE
    if ($copyCode -ge 8) {
        throw ("Could not stage the repository into " + $RepoDirectory + " (robocopy exit " + $copyCode + ").")
    }
    $stagedOrigin = (& git -C $RepoDirectory remote get-url origin 2>$null | Select-Object -First 1)
    if ($stagedOrigin -notmatch 'github\.com[:/]Tikhon-prog/Navigator(?:\.git)?$') {
        throw 'The staged repository origin could not be verified.'
    }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RepoDirectory) | Out-Null
    $cloneUrl = "https://github.com/$RepoName.git"
    Invoke-Checked -File (Get-Command git).Source -Arguments @('clone', $cloneUrl, $RepoDirectory)
}

# No manual configuration is required. Without a configured HTTPS endpoint, build offline-first.
$apiBase = [Environment]::GetEnvironmentVariable('POKOLENIE_API_BASE_URL')
if ([string]::IsNullOrWhiteSpace($apiBase)) {
    $apiBase = ''
    Remove-Item Env:POKOLENIE_API_BASE_URL -ErrorAction SilentlyContinue
    Write-Host 'Backend URL is not configured; creating the offline-first build.' -ForegroundColor Yellow
} else {
    if (($apiBase -notmatch '^https://[^/\s]+(?:/.*)?$') -or $apiBase.Contains('@')) {
        throw 'POKOLENIE_API_BASE_URL must be a public HTTPS URL, without credentials or whitespace.'
    }
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
