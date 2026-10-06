@echo off
setlocal
cd /d "%~dp0"
echo === Navigator project setup ===
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found in PATH.
  echo Add Flutter\bin to PATH and run this file again.
  pause
  exit /b 1
)
if not exist android\gradle\wrapper\gradle-wrapper.jar (
  echo Android Gradle wrapper is missing. Flutter will restore the Android project files.
  flutter create --project-name navigator .
  if errorlevel 1 (
    echo flutter create failed.
    pause
    exit /b 1
  )
)
flutter pub get
if errorlevel 1 exit /b 1
flutter analyze
endlocal
