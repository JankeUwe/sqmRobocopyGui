<#
.SYNOPSIS
    Installs the sqmRobocopyGui module system-wide (all users).

.DESCRIPTION
    Always installs to the system-wide module path
    ($env:ProgramFiles\WindowsPowerShell\Modules) and creates the Start menu entry for all
    users. Requires Administrator rights; Install.cmd elevates automatically via UAC.
    An older per-user copy (CurrentUser) is removed to avoid version conflicts.

    No external dependencies (only robocopy.exe, which ships with Windows).

.PARAMETER Source
    Source directory of the module. Defaults to the script's own directory.

.PARAMETER Destination
    Explicit destination path. Overrides the default module path when specified.

.EXAMPLE
    .\Install.cmd
    Recommended: handles execution policy (cross-domain shares) and elevates via UAC.

.EXAMPLE
    .\Install.ps1
    From an elevated PowerShell.

.NOTES
    Uses robocopy /COPY:DAT to copy the module data. Note: /COPY:DAT does NOT strip
    the Zone.Identifier ADS (Mark-of-the-Web) - the subsequent Unblock-File pass on all
    destination files is what removes it.
#>
param(
    [string]$Source      = $PSScriptRoot,
    [string]$Destination = ''
)

# ---------------------------------------------------------------------------
# 0. Immer AllUsers - Adminrechte erforderlich
# ---------------------------------------------------------------------------
$Scope   = 'AllUsers'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
             [Security.Principal.WindowsBuiltInRole]'Administrator')
if (-not $isAdmin) {
    Write-Warning "sqmRobocopyGui is always installed for all users and requires Administrator rights."
    Write-Warning "Run Install.cmd (it asks for elevation via UAC) or start Install.ps1 from an elevated PowerShell."
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Zielpfad bestimmen
# ---------------------------------------------------------------------------
if (-not $Destination) {
    $Destination = "$env:ProgramFiles\WindowsPowerShell\Modules\sqmRobocopyGui"
}

# ---------------------------------------------------------------------------
# 2. Alte CurrentUser-Installation entfernen (wuerde sonst die AllUsers-Version verdecken)
# ---------------------------------------------------------------------------
$pathUser = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\sqmRobocopyGui'
if (Test-Path $pathUser) {
    Write-Host "CurrentUser installation detected. Removing to avoid conflicts..." -ForegroundColor Yellow
    Write-Host "  $pathUser" -ForegroundColor Gray
    Remove-Item $pathUser -Recurse -Force
    Write-Host "CurrentUser installation removed." -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# 4. Modul kopieren
#    /COPY:DAT  -> Data, Attributes, Timestamps (KEIN Zone.Identifier-Strip!
#                  das erledigt der Unblock-File-Schritt 5)
#    /IS        -> "Include Same": kopiert auch Dateien, die robocopy per Timestamp+Groesse
#                  als bereits identisch einstuft - reine Vorsichtsmassnahme (per Repro
#                  bestaetigt: eine reine Timestamp-Uebereinstimmung bei UNTERSCHIEDLICHER
#                  Groesse fuehrt bei robocopy schon ohne dieses Flag zuverlaessig zum
#                  Kopieren; /IS deckt zusaetzlich den unwahrscheinlicheren Fall ab, dass
#                  Groesse UND Timestamp zufaellig gleich sind).
#    /XD .git   -> exclude git directory
#    /XF        -> exclude meta files
# ---------------------------------------------------------------------------
Write-Host "Installing sqmRobocopyGui to: $Destination" -ForegroundColor Cyan
robocopy $Source $Destination /E /PURGE /NJH /NJS /NDL /COPY:DAT /IS `
    /XD .git tests Tests bin `
    /XF .gitignore README.md LICENSE `
          Install.cmd Install.ps1 `
          "*.TempPoint.*" "*.RestorePoint.*" "*.psproj" "*.psproj.psbuild" "*.psprojs" `
          "desktop.ini" "Tester.ps1" "Test-Module*.ps1" `
          "coverage.xml" "testresults.xml"

# ---------------------------------------------------------------------------
# 5. Zone.Identifier auf dem Ziel entfernen
# ---------------------------------------------------------------------------
Write-Host "Unblocking files..." -ForegroundColor Cyan
Get-ChildItem -Path $Destination -Recurse -File | ForEach-Object {
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 6. Import testen
# ---------------------------------------------------------------------------
Write-Host "Testing module import..." -ForegroundColor Cyan
$importOk = $false
try {
    # Expliziter Pfad zur .psd1 verhindert dass eine alte Version aus PSModulePath geladen wird
    $psd1Path = Join-Path $Destination "sqmRobocopyGui.psd1"
    Import-Module $psd1Path -Force -WarningAction SilentlyContinue -ErrorAction Stop
    $version = (Get-Module sqmRobocopyGui).Version
    Write-Host "sqmRobocopyGui v$version successfully loaded." -ForegroundColor Green
    Write-Host "Scope: $Scope  |  Path: $Destination" -ForegroundColor Gray
    $importOk = $true
} catch {
    Write-Warning "Import failed: $_"
}

# ---------------------------------------------------------------------------
# 6b. Startmenue-Verknuepfung (alle Benutzer)
#     %ProgramData%\Microsoft\Windows\Start Menu\Programs. Die Verknuepfung startet
#     powershell.exe direkt (kein Launcher im Zielordner noetig, der von /PURGE bereinigt
#     wuerde) und importiert das Modul per Pfad zur installierten .psd1. Nur wenn der
#     Import-Test erfolgreich war. Eine alte Verknuepfung des Benutzers wird entfernt, damit
#     kein Doppeleintrag im Startmenue entsteht.
# ---------------------------------------------------------------------------
$shortcutName = 'sqmRobocopyGui.lnk'
if ($importOk) {
    Write-Host "Legt Startmenue-Eintrag an..." -ForegroundColor Cyan
    try {
        $menuDir  = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        $otherLnk = Join-Path ([Environment]::GetFolderPath('Programs')) $shortcutName
        if (Test-Path $otherLnk) {
            Remove-Item $otherLnk -Force -ErrorAction SilentlyContinue
        }

        $psd1Installed = Join-Path $Destination 'sqmRobocopyGui.psd1'
        $psExe         = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcutPath  = Join-Path $menuDir $shortcutName
        $wshShell      = New-Object -ComObject WScript.Shell
        $shortcut      = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath       = $psExe
        $shortcut.Arguments        = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Import-Module '$psd1Installed'; Show-sqmRobocopyGui`""
        $shortcut.WorkingDirectory = [Environment]::GetFolderPath('UserProfile')
        $shortcut.Description      = 'sqmRobocopyGui - robocopy-Befehle per GUI zusammenstellen'
        $iconInstalled             = Join-Path $Destination 'Assets\sqmRobocopyGui.ico'
        $shortcut.IconLocation     = if (Test-Path $iconInstalled) { "$iconInstalled,0" } else { "$env:SystemRoot\System32\imageres.dll,109" }
        $shortcut.Save()
        Write-Host "Startmenue-Eintrag angelegt: $shortcutPath" -ForegroundColor Green
    } catch {
        Write-Warning "Startmenue-Eintrag konnte nicht angelegt werden: $_"
        Write-Warning "Die GUI laesst sich trotzdem starten: Show-sqmRobocopyGui"
    }
}

# ---------------------------------------------------------------------------
# 7. Naechste Schritte
# ---------------------------------------------------------------------------
if ($importOk) {
    Write-Host ""
    Write-Host "Naechste Schritte:" -ForegroundColor Cyan
    Write-Host "  Startmenue > 'sqmRobocopyGui'                              # GUI per Klick" -ForegroundColor Gray
    Write-Host "  Show-sqmRobocopyGui                                        # GUI" -ForegroundColor Gray
    Write-Host "  Show-sqmRobocopyGui -Source D:\Daten -Destination E:\Kopie  # GUI, vorbelegt" -ForegroundColor Gray
    Write-Host "  Get-Help New-sqmRobocopyCommand -Examples                  # Generator per Skript" -ForegroundColor Gray
}
