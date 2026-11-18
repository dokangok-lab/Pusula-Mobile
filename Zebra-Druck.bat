@echo off
REM Pusula Mobile - Zebra-Druck
REM Schickt eine .zpl-Datei direkt an den freigegebenen Zebra-Etikettdrucker.
REM Freigabename des Druckers hier eintragen (Standard: ZEBRA):
set DRUCKER=ZEBRA

if "%~1"=="" (
  echo Bitte eine .zpl-Datei auf diese Datei ziehen oder .zpl-Dateien damit oeffnen.
  pause
  exit /b
)
copy /b "%~1" "\\%COMPUTERNAME%\%DRUCKER%" >nul
if errorlevel 1 (
  echo Drucken fehlgeschlagen. Ist der Drucker als "%DRUCKER%" freigegeben?
  pause
  exit /b
)
del "%~1" >nul 2>&1
