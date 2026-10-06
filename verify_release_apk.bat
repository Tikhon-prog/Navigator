@echo off
setlocal
cd /d %~dp0
set "APKSIGNER=%ANDROID_SDK_ROOT%\build-tools\36.0.0\apksigner.bat"
if not exist "%APKSIGNER%" set "APKSIGNER=%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\apksigner.bat"
if not exist "%APKSIGNER%" (
  echo ERROR: apksigner.bat not found.
  exit /b 1
)
"%APKSIGNER%" verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
endlocal
