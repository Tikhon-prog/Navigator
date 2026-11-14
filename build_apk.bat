@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ================================================
echo   Поколение — Android release
echo ================================================
echo.

where flutter >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter was not found in PATH.
    echo Add your Flutter SDK bin folder to PATH, then run this file again.
    exit /b 1
)

for /f "tokens=2 delims=: " %%V in ('findstr /b /c:"version:" pubspec.yaml') do set "APP_VERSION=%%V"
set "APP_VERSION=%APP_VERSION:"=%"
set "APP_VERSION=%APP_VERSION:'=%"
if not defined APP_VERSION (
    echo ERROR: Could not read version from pubspec.yaml.
    exit /b 1
)
powershell -NoProfile -Command "if ('%APP_VERSION%' -notmatch '^\d+\.\d+\.\d+\+\d+$') { exit 1 }"
if errorlevel 1 (
    echo ERROR: pubspec.yaml version must use major.minor.patch+build format.
    exit /b 1
)
set "APK_NAME=Pokolenie-%APP_VERSION%.apk"

echo Version: %APP_VERSION%
echo.

echo [1/5] Resolving packages...
call flutter pub get
if errorlevel 1 exit /b 1

echo.
echo [2/5] Running Flutter tests...
call flutter test
if errorlevel 1 exit /b 1

echo.
echo [3/5] Analyzing Dart source...
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 exit /b 1

echo.
echo [4/5] Building release APK...
call flutter build apk --release --target-platform android-arm64,android-x64
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
copy /y "%APK_PATH%" "dist\%APK_NAME%" >nul
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$file='dist\%APK_NAME%'; $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant(); Set-Content -LiteralPath ($file+'.sha256') -Value ($hash + '  %APK_NAME%') -Encoding ascii"
if errorlevel 1 exit /b 1
for %%F in ("dist\%APK_NAME%") do echo APK size: %%~zF bytes
echo APK: %CD%\dist\%APK_NAME%
echo SHA-256: %CD%\dist\%APK_NAME%.sha256
echo Version: %APP_VERSION%
echo.
echo This offline-first build does not embed a school API URL.
echo Keep this APK private until tests, signing and school data are approved.
endlocal
exit /b 0
