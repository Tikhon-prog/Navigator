@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo === Настройка проекта «Поколение» ===
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found in PATH.
  echo Add Flutter\bin to PATH and run this file again.
  pause
  exit /b 1
)
if not exist android\gradle\wrapper\gradle-wrapper.jar (
  echo Android Gradle wrapper is missing. Flutter will restore the Android project files.
  call flutter create --project-name navigator .
  if errorlevel 1 (
    echo flutter create failed.
    pause
    exit /b 1
  )
)
call flutter pub get
if errorlevel 1 exit /b 1
call flutter analyze
if errorlevel 1 exit /b 1
endlocal
exit /b 0
