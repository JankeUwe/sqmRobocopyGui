# sqmRobocopyGui - Changelog

## [0.1.0.0] - 2026-10-10

### Erste Version

- WinForms-GUI `Show-sqmRobocopyGui` im Visual-Studio-Dark-Design der uebrigen Werkzeuge
  (dunkle Titelleiste, Syntaxfaerbung): alle 95 robocopy-Optionen (Stand Windows 11 24H2 /
  Server 2025) in 8 Kategorien mit Navigationsliste wie im VS-Optionen-Dialog, Kurzhilfe in jeder
  Zeile, ausfuehrliche Hilfe und Tooltip, gesetzte Optionen fett, loeschende orange.
- Quelle und Ziel: moderner Explorer-Ordnerdialog (IFileOpenDialog, auch unter PowerShell 5.1),
  Verlauf der letzten 15 Pfade, Drag & Drop aus dem Explorer, Tauschen, im Explorer oeffnen,
  Pfadstatus mit Zeitlimit (tote Freigaben blockieren die Oberflaeche nicht).
- Dateiauswahl per Dialog (Quelle wird auf Wunsch uebernommen), Ordnerauswahl mit
  Mehrfachauswahl fuer `/XD`, Dateiauswahl fuer `/XF`, Speichern-Dialoge fuer Protokoll und
  Auftragsdatei.
- Sich ausschliessende Optionen waehlen sich gegenseitig ab, auch ueber Typen hinweg
  (`/SEC` leert `/COPY`, `/LOG` vs. `/LOG+` / `/UNILOG` / `/UNILOG+`).
- 11 Vorlagen, u.a. Spiegeln, Server-Migration mit Rechten, NAS/Linux, SQL-Backups verteilen,
  langsame WAN-Leitung, nur Ordnerstruktur, Trockenlauf.
- `Test-sqmRobocopyParameter`: Fehler und Hinweise live in der GUI, mit Sprung zur Option;
  optional Pfadpruefung (`-CheckPath`).
- `New-sqmRobocopyCommand`: Kommandozeile, Batch (UTF-8 via `chcp 65001`, `%` maskiert,
  Exitcode-Auswertung), PowerShell, geplante Aufgabe (`Register-ScheduledTask`, SYSTEM oder
  aktueller Benutzer, ueberschreibt nie) und rohe Argumentliste. Verzeichnisse immer ohne
  abschliessenden Backslash.
- Ausfuehren in der GUI: Trockenlauf mit `/L` (F5) und echter Lauf (Strg+F5), Rueckfrage mit
  Klartext bei `/MIR`, `/PURGE`, `/MOV`, `/MOVE`, `/MON`, `/MOT`; farbiges Live-Protokoll,
  Fortschritt der aktuellen Datei, Abbrechen, Exitcode als Text. Bei Protokolldatei wird `/TEE`
  ergaenzt.
- `ConvertFrom-sqmRobocopyCommand`: vorhandene Zeile (cmd, Batch mit `^`, PowerShell) oder
  `.RCJ`-Auftragsdatei in die Felder uebernehmen; RCJ-Kodierung (OEM, ANSI, UTF-8, Unicode)
  wird erkannt.
- `ConvertFrom-sqmRobocopyExitCode`: Exitcode-Bitmaske als Text.
- Einstellungen als JSON speichern/laden.
- `Tests\Test-sqmRobocopyGui.ps1`: robocopy wertet jede Option selbst aus, echte Laeufe aller
  Ausgabeformate in einem Ordner mit Leerzeichen, Umlaut und `%`, RCJ-Rundreise, GUI inkl.
  Trockenlauf, Lauf und Abbruch; bestanden unter PowerShell 5.1 und 7. Geplante Aufgabe live
  im Benutzerkontext angelegt, gestartet und entfernt.
