@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo === Поколение: signed release APK ===
for /f "tokens=2 delims=: " %%V in ('findstr /b /c:"version:" pubspec.yaml') do set "APP_VERSION=%%V"
if not defined APP_VERSION (
    echo ERROR: Could not read version from pubspec.yaml.
    exit /b 1
)
echo App version: %APP_VERSION%
if exist android\key.properties if exist android\app\navigator-release.jks goto SIGNING_READY
call setup_release_signing.bat
if errorlevel 1 exit /b 1
if not exist android\key.properties (
    echo ERROR: signing properties were not created.
    exit /b 1
)
if not exist android\app\navigator-release.jks (
    echo ERROR: release keystore was not created.
    exit /b 1
)

:SIGNING_READY
call flutter clean
if errorlevel 1 exit /b 1
call flutter pub get
if errorlevel 1 exit /b 1
call flutter test
if errorlevel 1 exit /b 1
call flutter analyze
if errorlevel 1 exit /b 1

if not exist build\symbols mkdir build\symbols
call flutter build apk --release --target-platform android-arm64,android-x64 --obfuscate --split-debug-info=build\symbols
if errorlevel 1 exit /b 1

echo.
echo APK:
dir /b build\app\outputs\flutter-apk\app-release.apk

echo.
echo Verifying APK signature...
set "ANDROID_SDK_ROOT=%ANDROID_SDK_ROOT%"
if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "APKSIGNER="
for /f "delims=" %%S in ('powershell -NoProfile -Command "Get-ChildItem (Join-Path $env:ANDROID_SDK_ROOT build-tools) -Directory | Where-Object { Test-Path (Join-Path $_.FullName apksigner.bat) } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName apksigner.bat }') do set "APKSIGNER=%%S"
if not defined APKSIGNER (
    echo ERROR: apksigner.bat was not found in Android SDK build-tools.
    exit /b 1
)
"%APKSIGNER%" verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
if errorlevel 1 (
    echo Signature verification failed.
    exit /b 1
)

echo.
echo Preparing named release files...
if not exist "dist" mkdir "dist"
if errorlevel 1 exit /b 1
copy /y "build\app\outputs\flutter-apk\app-release.apk" "dist\Pokolenie-%APP_VERSION%.apk" >nul
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath 'dist\Pokolenie-%APP_VERSION%.apk').Hash.ToLower(); Set-Content -LiteralPath 'dist\Pokolenie-%APP_VERSION%.apk.sha256' -Value ($hash + '  Pokolenie-%APP_VERSION%.apk') -Encoding ascii"
if errorlevel 1 exit /b 1
echo.
echo «Поколение» release APK подписан и проверен.
echo File: %CD%\dist\Pokolenie-%APP_VERSION%.apk
echo SHA-256: %CD%\dist\Pokolenie-%APP_VERSION%.apk.sha256
endlocal
exit /b 0
