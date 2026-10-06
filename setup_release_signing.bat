@echo off
setlocal EnableExtensions
cd /d %~dp0

echo === Navigator: release signing setup ===
if not exist android\app mkdir android\app

if exist android\key.properties if exist android\app\navigator-release.jks (
    echo Release key already exists. Nothing to do.
    exit /b 0
)

set "KEYTOOL=%JAVA_HOME%\bin\keytool.exe"
if not exist "%KEYTOOL%" set "KEYTOOL=keytool"

where keytool >nul 2>&1
if errorlevel 1 if not exist "%KEYTOOL%" (
    echo ERROR: keytool was not found. Make sure Java 21 is installed and JAVA_HOME is set.
    exit /b 1
)

for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$r=New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Fill($r); [Convert]::ToBase64String($r).TrimEnd('=').Replace('+','A').Replace('/','B')"`) do set "STOREPASS=%%P"
set "KEYPASS=%STOREPASS%"

if "%STOREPASS%"=="" (
    echo ERROR: failed to generate a local signing password.
    exit /b 1
)

"%KEYTOOL%" -genkeypair -v ^
  -keystore android\app\navigator-release.jks ^
  -storepass "%STOREPASS%" ^
  -keypass "%KEYPASS%" ^
  -alias navigator ^
  -keyalg RSA ^
  -keysize 4096 ^
  -validity 10000 ^
  -dname "CN=Navigator Test, OU=Navigator, O=Navigator, L=Local, ST=Local, C=RU"
if errorlevel 1 (
    echo ERROR: key generation failed.
    exit /b 1
)

>android\key.properties echo storeFile=navigator-release.jks
>>android\key.properties echo storePassword=%STOREPASS%
>>android\key.properties echo keyAlias=navigator
>>android\key.properties echo keyPassword=%KEYPASS%

echo.
echo Release signing key created locally.
echo It is ignored by Git and is NOT included in Navigator ZIP archives.
endlocal
