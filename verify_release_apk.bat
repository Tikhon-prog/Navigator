@echo off
setlocal
cd /d "%~dp0"
if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "APKSIGNER="
for /f "delims=" %%S in ('powershell -NoProfile -Command "Get-ChildItem (Join-Path $env:ANDROID_SDK_ROOT build-tools) -Directory | Where-Object { Test-Path (Join-Path $_.FullName apksigner.bat) } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName apksigner.bat }"') do set "APKSIGNER=%%S"
if not defined APKSIGNER (
  echo ERROR: apksigner.bat was not found in Android SDK build-tools.
  exit /b 1
)
"%APKSIGNER%" verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
if errorlevel 1 exit /b 1
echo APK signature verification succeeded.
endlocal
