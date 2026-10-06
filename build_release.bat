@echo off
setlocal
cd /d %~dp0

echo === Navigator: signed release APK ===
if not exist android\key.properties (
    call setup_release_signing.bat
    if errorlevel 1 exit /b 1
)

flutter clean
if errorlevel 1 exit /b 1
flutter pub get
if errorlevel 1 exit /b 1
flutter analyze
if errorlevel 1 exit /b 1

if not exist build\symbols mkdir build\symbols
flutter build apk --release --obfuscate --split-debug-info=build\symbols
if errorlevel 1 exit /b 1

echo.
echo APK:
dir /b build\app\outputs\flutter-apk\app-release.apk

echo.
echo Verifying APK signature...
set "APKSIGNER=%ANDROID_SDK_ROOT%\build-tools\36.0.0\apksigner.bat"
if not exist "%APKSIGNER%" set "APKSIGNER=%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\apksigner.bat"
if not exist "%APKSIGNER%" (
    echo ERROR: apksigner.bat was not found.
    exit /b 1
)
"%APKSIGNER%" verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
if errorlevel 1 (
    echo Signature verification failed.
    exit /b 1
)

echo.
echo Navigator release APK is signed and verified.
endlocal
