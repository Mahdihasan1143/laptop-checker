@echo off
title Laptop Checker - Made by Mahdi
cd /d "%~dp0"
if not exist "%~dp0app\laptop-check.ps1" (
  echo.
  echo   The program files were not found next to this file.
  echo   Please EXTRACT the whole ZIP first ^(right-click the ZIP - Extract All^),
  echo   then open the extracted folder and run this file again.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\laptop-check.ps1" %*
