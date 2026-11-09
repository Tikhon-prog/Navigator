@rem Gradle wrapper launcher for Navigator.
@echo off
setlocal
set DIRNAME=%~dp0
set APP_HOME=%DIRNAME%

rem Honor the explicitly configured JAVA_HOME (JDK 27 for this project).
rem Use Android Studio's bundled JBR only when JAVA_HOME is not defined.
if not defined JAVA_HOME if exist "%ProgramFiles%\Android\Android Studio\jbr\bin\java.exe" set "JAVA_HOME=%ProgramFiles%\Android\Android Studio\jbr"
if not defined JAVA_HOME if exist "%ProgramFiles(x86)%\Android\Android Studio\jbr\bin\java.exe" set "JAVA_HOME=%ProgramFiles(x86)%\Android\Android Studio\jbr"
if not defined JAVA_HOME if exist "%LOCALAPPDATA%\Programs\Android Studio\jbr\bin\java.exe" set "JAVA_HOME=%LOCALAPPDATA%\Programs\Android Studio\jbr"

if not exist "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" (
  echo.
  echo ERROR: gradle-wrapper.jar is missing.
  echo This archive is intended to replace/update the existing Navigator project.
  echo Please extract it over your current C:\Navigator folder so the existing
  echo Gradle wrapper JAR is preserved.
  exit /b 1
)

set CLASSPATH=%APP_HOME%gradle\wrapper\gradle-wrapper.jar
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo ERROR: A compatible Java runtime was not found.
  echo Install JDK 27 and set JAVA_HOME, or use Android Studio's bundled JDK.
  exit /b 1
)
"%JAVA_HOME%\bin\java.exe" -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*
exit /b %ERRORLEVEL%
