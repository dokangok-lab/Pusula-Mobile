@echo off
REM Pusula Mobile - Zebra-Druck
REM Einmal doppelklicken: startet den Waechter, der Etiketten aus der App
REM sofort und ohne Druckfenster auf den Zebra druckt (startet danach automatisch mit Windows).
REM Zebra-Druck.ps1 muss im selben Ordner liegen.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Zebra-Druck.ps1" %*
