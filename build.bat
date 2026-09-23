@echo off
rem Ukraine Air Defense (UAD) - build launcher.
rem   build.bat            -> build\windows\UAD.exe
rem   build.bat apk        -> build\android\UAD.apk
rem   build.bat aab        -> build\android\UAD.aab
rem   build.bat all
rem   build.bat all -Publish   -> builds both, GitHub release + database (update offer in games)
set TARGET=%1
if "%TARGET%"=="" set TARGET=windows
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Target %TARGET% %2
if errorlevel 1 (
  echo.
  echo BUILD FAILED
  pause
  exit /b 1
)
