@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -NoLogo -STA -ExecutionPolicy Bypass -File "%~dp0ChocolateyPackager.ps1"
if errorlevel 1 (
  echo.
  echo Le programme a rencontre une erreur. Consultez le message ci-dessus.
  pause
)