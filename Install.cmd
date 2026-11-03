@echo off
:: sqmRobocopyGui Installer
:: Stages Install.ps1 locally (strips Mark-of-the-Web) and runs it from there,
:: so it works even when a GPO MachinePolicy (e.g. RemoteSigned) blocks scripts
:: launched directly from a remote/UNC share (\\tsclient\..., cross-domain share).
:: Installs ALWAYS for all users; re-launches elevated (UAC) when not running as admin.
::
:: Usage:
::   Install.cmd                              -> system-wide (auto-elevates via UAC)
::   Install.cmd "D:\Modules\sqmRobocopyGui"   -> system-wide, custom path

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "DESTINATION=%~1"

:: ---------------------------------------------------------------
:: Pruefen ob Script bereits als Administrator laeuft
:: ---------------------------------------------------------------
net session >nul 2>&1
set "IS_ADMIN=%errorlevel%"

:: ---------------------------------------------------------------
:: Ohne Admin -> UAC-Elevation (Installation erfolgt immer fuer alle Benutzer)
:: ---------------------------------------------------------------
if "%IS_ADMIN%" neq "0" (
    echo.
    echo  sqmRobocopyGui - Elevation erforderlich
    echo  ============================================================
    echo  Die Installation erfolgt fuer alle Benutzer und benoetigt Administratorrechte.
    echo  Starte UAC-Abfrage ...
    echo.
    if "%DESTINATION%"=="" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
            "Start-Process cmd.exe -ArgumentList '/c ""%~f0""' -Verb RunAs"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
            "Start-Process cmd.exe -ArgumentList '/c ""%~f0"" ""%DESTINATION%""' -Verb RunAs"
    )
    exit /b 0
)

:: ---------------------------------------------------------------
:: Install.ps1 ausfuehren (laeuft jetzt mit den richtigen Rechten)
:: ---------------------------------------------------------------
echo.
echo  sqmRobocopyGui - Installation
echo  ============================================================

:: ---------------------------------------------------------------
:: Bootstrap IMMER lokal stagen und von dort starten (kein Remote-Versuch).
:: Grund: Eine per GPO gesetzte MachinePolicy (z.B. RemoteSigned) ueberstimmt
:: -ExecutionPolicy Bypass (Process-Scope). Ein .ps1 von einem Remote-/UNC-Pfad
:: (\\tsclient\..., Netz-Share) wird dann als unsigniertes Remote-Skript
:: blockiert - der Remote-Versuch scheitert in dieser Umgebung IMMER.
:: "type > datei" erzeugt eine frische LOKALE Datei nur aus dem Hauptstream:
:: der Zone.Identifier-ADS (Mark-of-the-Web) wird NICHT uebernommen, damit
:: laeuft das lokale unsignierte Skript unter RemoteSigned.
:: Install.ps1 liest das Modul per robocopy aus -Source (Datei-Lesen ist nicht
:: policy-beschraenkt) und entblockt die Zieldateien anschliessend selbst.
:: ---------------------------------------------------------------
set "BOOT_DIR=%TEMP%\sqmRobocopyGui_boot"
if not exist "!BOOT_DIR!" md "!BOOT_DIR!"
type "%SCRIPT_DIR%Install.ps1" > "!BOOT_DIR!\Install.ps1"

:: Trailing-Backslash aus SCRIPT_DIR entfernen (sonst Quoting-Bug bei -Source)
set "SRC_DIR=%SCRIPT_DIR%"
if "!SRC_DIR:~-1!"=="\" set "SRC_DIR=!SRC_DIR:~0,-1!"

call :RUN_INSTALL "!BOOT_DIR!\Install.ps1" -Source "!SRC_DIR!"

rmdir /s /q "!BOOT_DIR!" >nul 2>&1

endlocal
pause
goto :EOF

:: ===============================================================
:: Subroutine: Install.ps1 mit den passenden Argumenten starten.
::   %~1 = Pfad zu Install.ps1
::   %~2 %~3 = Zusatzargumente (-Source "<pfad>")
:: ===============================================================
:RUN_INSTALL
set "PS1=%~1"
:: %2 %3 OHNE Tilde, damit die Quotes um den -Source-Pfad erhalten bleiben
set "EXTRA=%2 %3"
if "%DESTINATION%"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %EXTRA%
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Destination "%DESTINATION%" %EXTRA%
)
goto :EOF
