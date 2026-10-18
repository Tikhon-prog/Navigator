@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo   Поколение 0.2.0+2 — сборка Android APK
echo ================================================
echo.

where flutter >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter was not found in PATH.
    echo Add your Flutter SDK bin folder to PATH, then run this file again.
    exit /b 1
)

findstr /b /c:"version: 0.2.0+2" pubspec.yaml >nul
if errorlevel 1 (
    echo ERROR: pubspec.yaml is not set to version 0.2.0+2.
    exit /b 1
)

echo [1/5] Resolving packages...
flutter pub get
if errorlevel 1 exit /b 1

echo.
echo [2/5] Running Flutter tests...
flutter test
if errorlevel 1 exit /b 1

echo.
echo [3/5] Analyzing Dart source...
flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 exit /b 1

echo.
echo [4/5] Building release APK...
flutter build apk --release
if errorlevel 1 exit /b 1

set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_PATH%" (
    echo ERROR: Flutter reported success but the APK file was not found.
    exit /b 1
)

echo.
echo [5/5] Preparing named release files...
if not exist "dist" mkdir "dist"
if errorlevel 1 exit /b 1
copy /y "%APK_PATH%" "dist\Pokolenie-0.2.0+2.apk" >nul
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath 'dist\Pokolenie-0.2.0+2.apk').Hash.ToLower(); Set-Content -LiteralPath 'dist\Pokolenie-0.2.0+2.apk.sha256' -Value ($hash + '  Pokolenie-0.2.0+2.apk') -Encoding ascii"
if errorlevel 1 exit /b 1
for %%F in ("dist\Pokolenie-0.2.0+2.apk") do echo APK size: %%~zF bytes
echo APK: %CD%\dist\Pokolenie-0.2.0+2.apk
echo SHA-256: %CD%\dist\Pokolenie-0.2.0+2.apk.sha256
echo Version: 0.2.0 ^(build 2^)
echo.
echo This offline-first build does not embed a school API URL.
echo Keep this APK private until the tests, signing and school data are approved.
endlocal
