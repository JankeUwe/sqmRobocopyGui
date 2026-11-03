<#
.SYNOPSIS
    Installs the sqmRobocopyGui module into the PowerShell module path.

.DESCRIPTION
    Copies the module to either the system-wide module path (requires Admin)
    or the current user's personal module path (no Admin rights needed).

    The default scope is determined automatically:
      - Running as Administrator  -> AllUsers  ($env:ProgramFiles\WindowsPowerShell\Modules)
      - Running as normal user    -> CurrentUser ($HOME\Documents\WindowsPowerShell\Modules)
    Pass -Scope explicitly to override this behaviour.

    No external dependencies (only robocopy.exe, which ships with Windows).

.PARAMETER Scope
    Installation scope:
      CurrentUser  — installs to $HOME\Documents\WindowsPowerShell\Modules
      AllUsers     — installs to $env:ProgramFiles\WindowsPowerShell\Modules (requires Admin)
    Default: AllUsers when running as Administrator, CurrentUser otherwise.

.PARAMETER Source
    Source directory of the module. Defaults to the script's own directory.

.PARAMETER Destination
    Explicit destination path. Overrides -Scope when specified.

.EXAMPLE
    .\Install.ps1
    Installs for the current user — no Admin rights required.

.EXAMPLE
    .\Install.cmd
    Recommended when running from a cross-domain share (handles execution policy).

.EXAMPLE
    .\Install.ps1 -Scope AllUsers
    Installs system-wide — requires Admin rights.

.NOTES
    Uses robocopy /COPY:DAT to copy the module data. Note: /COPY:DAT does NOT strip
    the Zone.Identifier ADS (Mark-of-the-Web) - the subsequent Unblock-File pass on all
    destination files is what removes it.
#>
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope       = '',          # auto-detected below
    [string]$Source      = $PSScriptRoot,
    [string]$Destination = ''
)

# ---------------------------------------------------------------------------
# 0. Scope auto-detect: Admin -> AllUsers, sonst CurrentUser
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
             [Security.Principal.WindowsBuiltInRole]'Administrator')

if ($Scope -eq '') {
    $Scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Host "Auto-detected Scope: $Scope" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 1. Zielpfad bestimmen
# ---------------------------------------------------------------------------
if (-not $Destination) {
    if ($Scope -eq 'AllUsers') {
        $Destination = "$env:ProgramFiles\WindowsPowerShell\Modules\sqmRobocopyGui"
    } else {
        $docsPath    = [Environment]::GetFolderPath('MyDocuments')
        $Destination = Join-Path $docsPath "WindowsPowerShell\Modules\sqmRobocopyGui"
    }
}

# ---------------------------------------------------------------------------
# 2. Doppel-Installation erkennen und warnen
# ---------------------------------------------------------------------------
$docsPath_     = [Environment]::GetFolderPath('MyDocuments')
$pathUser      = Join-Path $docsPath_ "WindowsPowerShell\Modules\sqmRobocopyGui"
$pathAllUsers  = "$env:ProgramFiles\WindowsPowerShell\Modules\sqmRobocopyGui"
$existsUser    = Test-Path $pathUser
$existsAll     = Test-Path $pathAllUsers

if ($existsUser -and $existsAll -and $Scope -eq 'AllUsers') {
    # Running as Admin installing AllUsers — remove the CurrentUser copy automatically
    Write-Host "Both installations detected. Removing CurrentUser copy..." -ForegroundColor Yellow
    Write-Host "  $pathUser" -ForegroundColor Gray
    Remove-Item $pathUser -Recurse -Force
    Write-Host "CurrentUser installation removed." -ForegroundColor Green
    Write-Host ""
    $existsUser = $false

} elseif ($existsUser -and $existsAll) {
    # CurrentUser install, both exist — warn, cannot auto-remove AllUsers without Admin
    Write-Warning "sqmRobocopyGui is installed in BOTH locations:"
    Write-Warning "  CurrentUser : $pathUser"
    Write-Warning "  AllUsers    : $pathAllUsers"
    Write-Warning "PowerShell loads the CurrentUser version — the AllUsers copy is ignored."
    Write-Warning "To remove the AllUsers copy (requires Admin):"
    Write-Warning "  Remove-Item '$pathAllUsers' -Recurse -Force"
    Write-Host ""

} elseif ($Scope -eq 'CurrentUser' -and $existsAll) {
    Write-Warning "An AllUsers installation already exists at: $pathAllUsers"
    Write-Warning "After this install, PowerShell will load the CurrentUser version and ignore AllUsers."
    Write-Host ""

} elseif ($Scope -eq 'AllUsers' -and $existsUser) {
    # Running as Admin — remove the CurrentUser copy automatically
    Write-Host "CurrentUser installation detected. Removing to avoid conflicts..." -ForegroundColor Yellow
    Write-Host "  $pathUser" -ForegroundColor Gray
    Remove-Item $pathUser -Recurse -Force
    Write-Host "CurrentUser installation removed." -ForegroundColor Green
    Write-Host ""
    $existsUser = $false
}

# ---------------------------------------------------------------------------
# 3. Scope-Hinweis und Admin-Check
# ---------------------------------------------------------------------------
if ($Scope -eq 'AllUsers') {
    if (-not $isAdmin) {
        Write-Warning "Scope 'AllUsers' requires Administrator rights."
        Write-Warning "Run Install.cmd as Administrator, or use:  .\Install.ps1  (installs for current user only)"
        exit 1
    }
} else {
    # CurrentUser — Hinweis auf systemweite Installation
    Write-Host ""
    if ($isAdmin) {
        Write-Host "INFO: You are running as Administrator." -ForegroundColor Cyan
        Write-Host "      Installing for the current user only ($env:USERNAME)." -ForegroundColor Cyan
        Write-Host "      To install system-wide for ALL users, run:" -ForegroundColor Cyan
        Write-Host "        Install.cmd AllUsers" -ForegroundColor White
    } else {
        Write-Host "INFO: Installing for the current user only ($env:USERNAME)." -ForegroundColor Cyan
        Write-Host "      To install system-wide for ALL users, re-run as Administrator:" -ForegroundColor Cyan
        Write-Host "        Right-click Install.cmd > 'Run as administrator'" -ForegroundColor White
        Write-Host "        or: Install.cmd AllUsers  (in an elevated PowerShell)" -ForegroundColor White
    }
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
# 6b. Startmenue-Verknuepfung
#     AllUsers   -> %ProgramData%\Microsoft\Windows\Start Menu\Programs (alle Benutzer)
#     CurrentUser-> %APPDATA%\Microsoft\Windows\Start Menu\Programs (nur dieser Benutzer)
#     Die Verknuepfung startet powershell.exe direkt (kein Launcher im Zielordner noetig,
#     der von /PURGE bereinigt wuerde) und importiert das Modul per Pfad zur installierten
#     .psd1. Nur wenn der Import-Test erfolgreich war. Eine Verknuepfung des jeweils anderen
#     Scopes wird entfernt, damit kein Doppeleintrag im Startmenue entsteht.
# ---------------------------------------------------------------------------
$shortcutName = 'sqmRobocopyGui.lnk'
if ($importOk) {
    Write-Host "Legt Startmenue-Eintrag an..." -ForegroundColor Cyan
    try {
        $menuAll  = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        $menuUser = Join-Path ([Environment]::GetFolderPath('Programs')) ''
        $menuDir  = if ($Scope -eq 'AllUsers') { $menuAll } else { $menuUser }
        $otherLnk = Join-Path $(if ($Scope -eq 'AllUsers') { $menuUser } else { $menuAll }) $shortcutName
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
        $shortcut.IconLocation     = "$env:SystemRoot\System32\imageres.dll,109"
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
