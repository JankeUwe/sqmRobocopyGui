# sqmRobocopyGui - Changelog

## [0.1.5.1] - 2026-11-03

### Fehler

- `Install.cmd` brach mit "Label nicht gefunden" ab. Beim Umbau auf die reine AllUsers-Installation
  ging die Zeile verloren, die die Installation startet und danach aufraeumt, und die Subroutine
  wurde an der falschen Stelle gekuerzt. Der Ablauf ist wiederhergestellt.

## [0.1.5.0] - 2026-11-03

### Aenderungen

- Die Installation erfolgt immer fuer alle Benutzer (`%ProgramFiles%\WindowsPowerShell\Modules`,
  Startmenue-Eintrag in `%ProgramData%`). `Install.cmd` fordert die Administratorrechte per UAC
  an, `Install.ps1` bricht ohne Adminrechte mit Hinweis ab. Der Parameter `-Scope` und die
  CurrentUser-Installation entfallen. Eine alte Installation und Verknuepfung des Benutzers
  werden bei der Installation entfernt, damit sie die systemweite Version nicht verdecken.

## [0.1.4.0] - 2026-11-03

### Erweiterungen

- Eigenes Symbol fuer den Startmenue-Eintrag (`Assets\sqmRobocopyGui.ico`: zwei Ordner mit
  Pfeil im dunklen Design). Die Installation setzt es an die Verknuepfung; fehlt die Datei, bleibt
  ein Standardsymbol.

## [0.1.3.0] - 2026-11-03

### Fehler

- Die Ordnerauswahl kuerzte den gewaehlten Pfad auf den ersten Buchstaben (`F:\Daten\Backup`
  wurde zu `F`). Ursache: PowerShell entpackte das einelementige Ergebnis-Array zu einem String,
  `$r[0]` lieferte dann nur das erste Zeichen. Das Ergebnis wird jetzt als Array zurueckgegeben.

### Erweiterungen

- Die Zielauswahl startet nicht mehr im Quellordner. Ist im Zielfeld ein (teilweise
  vorhandener) Pfad eingetragen, startet sie dort, sonst bei "Dieser PC".

## [0.1.2.0] - 2026-11-03

### Erweiterungen

- `Install.cmd` / `Install.ps1` legen einen Startmenue-Eintrag "sqmRobocopyGui" an: bei
  AllUsers fuer alle Benutzer (`%ProgramData%`), bei CurrentUser nur fuer den Anwender. Der
  Eintrag startet die GUI direkt aus dem installierten Modul, ein Kommandozeilenaufruf ist
  nicht mehr noetig. Die Verknuepfung des jeweils anderen Scopes wird entfernt, damit es
  keinen Doppeleintrag gibt.

## [0.1.1.0] - 2026-10-14

### Fehler

- Nach der Auswahl von Quelle oder Ziel erschien ein zweiter, alter Ordnerdialog. Ursache:
  `IFileOpenDialog::GetResults()` liefert unter aktuellen Windows-11-Builds S_OK mit leerem
  Ergebnis, der Zugriff darauf warf eine Ausnahme, und die GUI fiel auf den
  FolderBrowserDialog zurueck. Die Einzelauswahl liest jetzt `GetResult()`, die
  Mehrfachauswahl (`/XD`) faellt bei leerem Ergebnis ebenfalls darauf zurueck. Nach dem
  Schliessen des Dialogs wirft die Auswahl keine Ausnahme mehr, der alte Dialog ist nur noch
  Rueckfall, wenn der Explorer-Dialog gar nicht geoeffnet werden kann.

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
