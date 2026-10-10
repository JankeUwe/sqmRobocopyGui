<#
	Metadaten aller robocopy-Optionen (Stand Windows 11 24H2 / Server 2025, "robocopy /?").
	Reihenfolge = Reihenfolge in der GUI und im erzeugten Befehl.

	Typ        Wert im Parameter-Hashtable          Ausgabe
	Switch     $true                                /XO
	Int        '3'                                  /R:3
	Bytes      '1048576'                            /MAX:1048576   (robocopy kennt hier kein K/M/G)
	Size       '10M'                                /IoRate:10M
	Age        '7' oder '20260101'                  /MAXAGE:7      (< 1900 = Tage, sonst JJJJMMTT)
	Hours      '2200-0600'                          /RH:2200-0600
	Flags      'DAT'                                /COPY:DAT      (erlaubte Buchstaben in Letters)
	Opt        $true oder Wert                      /MT bzw. /MT:16  (ValueKind Int | Size | Enum)
	List       @('*.tmp', 'Thumbs.db')              /XF *.tmp Thumbs.db
	Path       'C:\Logs\copy.log'                   /LOG:"C:\Logs\copy.log"

	Exclusive: Optionen mit gleichem Schluessel schliessen sich aus - die GUI waehlt die anderen ab,
	Test-sqmRobocopyParameter meldet die Kombination als Fehler.
#>

$script:srgParameters = @(
	# --- Kopieren --------------------------------------------------------------------------------
	@{ Name = 'S'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Subdirs'; Help = 'Kopiert Unterverzeichnisse, aber keine leeren.' }
	@{ Name = 'E'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Subdirs'; Help = 'Kopiert Unterverzeichnisse einschliesslich leerer. Fuer fast alle Ordnerkopien die richtige Wahl.' }
	@{ Name = 'MIR'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Subdirs'; Danger = $true; Help = 'Spiegelt die Verzeichnisstruktur (= /E + /PURGE). LOESCHT im Ziel alles, was es in der Quelle nicht (mehr) gibt.' }
	@{ Name = 'LEV'; Group = 'Kopieren'; Type = 'Int'; Min = 1; Max = 1000; Help = 'Kopiert nur die obersten n Ebenen der Quellstruktur (1 = nur die Quelle selbst).' }
	@{ Name = 'Z'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Restart'; Help = 'Neustartmodus: abgebrochene Dateien werden an der Abbruchstelle fortgesetzt. Gut fuer instabile Netze, etwas langsamer.' }
	@{ Name = 'B'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Restart'; Admin = $true; Help = 'Sicherungsmodus: kopiert mit dem Sicherungsrecht und ignoriert damit Datei-ACLs. Braucht Administrator- bzw. Sicherungs-Operator-Rechte.' }
	@{ Name = 'ZB'; Group = 'Kopieren'; Type = 'Switch'; Exclusive = 'Restart'; Admin = $true; Help = 'Neustartmodus, bei "Zugriff verweigert" automatisch Sicherungsmodus. Braucht fuer den Sicherungsmodus Administratorrechte.' }
	@{ Name = 'J'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Ungepufferte E/A. Empfohlen fuer sehr grosse Dateien (z.B. SQL-Backups, VHDX), fuer viele kleine Dateien langsamer.' }
	@{ Name = 'MT'; Group = 'Kopieren'; Type = 'Opt'; ValueKind = 'Int'; Min = 1; Max = 128; Default = '8'; Help = 'Multithread-Kopie mit n Threads (1-128, ohne Wert 8). Deutlich schneller bei vielen Dateien. Nicht mit /IPG oder /EFSRAW kombinierbar.' }
	@{ Name = 'EFSRAW'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Kopiert EFS-verschluesselte Dateien im RAW-Modus (ohne Entschluesselung).' }
	@{ Name = 'COMPRESS'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Fordert SMB-Netzwerkkomprimierung an (Windows Server 2022 / Windows 11 und neuer). Lohnt sich bei langsamen Leitungen und gut komprimierbaren Daten.' }
	@{ Name = 'NOOFFLOAD'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Kopiert ohne den Windows-Copy-Offload-Mechanismus (ODX).' }
	@{ Name = 'NOCLONE'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Kein Block-Cloning als Optimierung versuchen (ReFS / Dev Drive).' }
	@{ Name = 'SPARSE'; Group = 'Kopieren'; Type = 'Opt'; ValueKind = 'Enum'; Values = @('Y', 'N'); Default = 'Y'; Help = 'Sparse-Status der Dateien beibehalten (Y) oder nicht (N). Ohne Wert = Y.' }
	@{ Name = 'CREATE'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Erstellt nur die Verzeichnisstruktur und leere Dateien (Laenge 0).' }
	@{ Name = 'FAT'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Erstellt Zieldateien nur mit 8.3-FAT-Dateinamen.' }
	@{ Name = '256'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Schaltet die Unterstuetzung sehr langer Pfade (> 256 Zeichen) ab.' }
	@{ Name = 'SJ'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Kopiert Verzeichnis-Junctions als Junction statt deren Ziel.' }
	@{ Name = 'SL'; Group = 'Kopieren'; Type = 'Switch'; Help = 'Kopiert symbolische Links als Link statt deren Ziel.' }

	# --- Dateiinfos & Attribute -------------------------------------------------------------------
	@{ Name = 'COPY'; Group = 'Dateiinfos & Attribute'; Type = 'Flags'; Letters = 'DATSOUX'; Exclusive = 'CopyInfo'; Default = 'DAT'; Help = 'Was je Datei kopiert wird: D=Daten, A=Attribute, T=Zeitstempel, S=NTFS-ACLs, O=Besitzer, U=Ueberwachung, X=alternative Datenstroeme ueberspringen. Standard DAT. S/O/U brauchen Administratorrechte.' }
	@{ Name = 'SEC'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Exclusive = 'CopyInfo'; Help = 'Kopiert mit NTFS-Berechtigungen (= /COPY:DATS).' }
	@{ Name = 'COPYALL'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Exclusive = 'CopyInfo'; Admin = $true; Help = 'Kopiert alle Dateiinformationen (= /COPY:DATSOU). Braucht fuer Besitzer und Ueberwachung Administratorrechte.' }
	@{ Name = 'NOCOPY'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Exclusive = 'CopyInfo'; Help = 'Kopiert keine Dateiinformationen - sinnvoll nur zusammen mit /PURGE (Ziel aufraeumen ohne zu kopieren).' }
	@{ Name = 'DCOPY'; Group = 'Dateiinfos & Attribute'; Type = 'Flags'; Letters = 'DATEX'; Exclusive = 'DirInfo'; Default = 'DA'; Help = 'Was je Verzeichnis kopiert wird: D=Daten, A=Attribute, T=Zeitstempel, E=erweiterte Attribute, X=alternative Datenstroeme ueberspringen. Standard DA. DAT erhaelt auch die Ordner-Zeitstempel.' }
	@{ Name = 'NODCOPY'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Exclusive = 'DirInfo'; Help = 'Kopiert keine Verzeichnisinformationen (Standard waere /DCOPY:DA).' }
	@{ Name = 'SECFIX'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Help = 'Korrigiert die Berechtigungen aller Dateien, auch der uebersprungenen.' }
	@{ Name = 'TIMFIX'; Group = 'Dateiinfos & Attribute'; Type = 'Switch'; Help = 'Korrigiert die Zeitstempel aller Dateien, auch der uebersprungenen.' }
	@{ Name = 'A+'; Group = 'Dateiinfos & Attribute'; Type = 'Flags'; Letters = 'RASHCNET'; Help = 'Setzt diese Attribute an den kopierten Dateien: R=Schreibgeschuetzt, A=Archiv, S=System, H=Versteckt, C=Komprimiert, N=Nicht indiziert, E=Verschluesselt, T=Temporaer.' }
	@{ Name = 'A-'; Group = 'Dateiinfos & Attribute'; Type = 'Flags'; Letters = 'RASHCNETO'; Help = 'Entfernt diese Attribute an den kopierten Dateien (O = Offline). Typisch: A- R, um den Schreibschutz von CD-Kopien zu entfernen.' }

	# --- Loeschen & Verschieben ----------------------------------------------------------------
	@{ Name = 'PURGE'; Group = 'Loeschen & Verschieben'; Type = 'Switch'; Danger = $true; Help = 'LOESCHT Zieldateien und -verzeichnisse, die es in der Quelle nicht mehr gibt. Mit /E entspricht das /MIR.' }
	@{ Name = 'MOV'; Group = 'Loeschen & Verschieben'; Type = 'Switch'; Exclusive = 'Move'; Danger = $true; Help = 'Verschiebt Dateien: LOESCHT sie nach erfolgreichem Kopieren in der Quelle. Verzeichnisse bleiben stehen.' }
	@{ Name = 'MOVE'; Group = 'Loeschen & Verschieben'; Type = 'Switch'; Exclusive = 'Move'; Danger = $true; Help = 'Verschiebt Dateien UND Verzeichnisse: LOESCHT beides nach dem Kopieren in der Quelle.' }

	# --- Dateiauswahl ---------------------------------------------------------------------------
	@{ Name = 'XF'; Group = 'Dateiauswahl'; Type = 'List'; Picker = 'Files'; Help = 'Schliesst Dateien aus (Namen, Pfade oder Platzhalter wie *.tmp). Mehrere Eintraege mit ; trennen.' }
	@{ Name = 'XD'; Group = 'Dateiauswahl'; Type = 'List'; Picker = 'Folders'; Help = 'Schliesst Verzeichnisse aus (Namen oder vollstaendige Pfade, Platzhalter erlaubt). Mehrere Eintraege mit ; trennen.' }
	@{ Name = 'A'; Group = 'Dateiauswahl'; Type = 'Switch'; Exclusive = 'Archive'; Help = 'Kopiert nur Dateien mit gesetztem Archiv-Attribut.' }
	@{ Name = 'M'; Group = 'Dateiauswahl'; Type = 'Switch'; Exclusive = 'Archive'; Help = 'Kopiert nur Dateien mit Archiv-Attribut und setzt es danach in der Quelle zurueck (inkrementelle Sicherung).' }
	@{ Name = 'IA'; Group = 'Dateiauswahl'; Type = 'Flags'; Letters = 'RASHCNETO'; Help = 'Nur Dateien, bei denen mindestens eines dieser Attribute gesetzt ist.' }
	@{ Name = 'XA'; Group = 'Dateiauswahl'; Type = 'Flags'; Letters = 'RASHCNETO'; Help = 'Schliesst Dateien aus, bei denen eines dieser Attribute gesetzt ist (z.B. SH = System und Versteckt).' }
	@{ Name = 'XC'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst geaenderte Dateien aus (gleicher Zeitstempel, andere Groesse).' }
	@{ Name = 'XN'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst neuere Dateien aus: eine Quelldatei, die neuer als die Zieldatei ist, wird NICHT kopiert.' }
	@{ Name = 'XO'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst aeltere Dateien aus: eine Zieldatei, die neuer ist als die Quelldatei, wird nicht ueberschrieben.' }
	@{ Name = 'XX'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst zusaetzliche Dateien/Verzeichnisse aus (nur im Ziel vorhanden). Schuetzt sie zusammen mit /MIR oder /PURGE vor dem Loeschen.' }
	@{ Name = 'XL'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst "einsame" Dateien/Verzeichnisse aus (nur in der Quelle vorhanden) - aktualisiert also nur, was im Ziel schon existiert.' }
	@{ Name = 'IS'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst identische Dateien ein: kopiert auch Dateien, die im Ziel schon gleich vorhanden sind.' }
	@{ Name = 'IT'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst "optimierte" Dateien ein (gleiche Daten, abweichende Attribute).' }
	@{ Name = 'IM'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst Dateien mit abweichender Aenderungszeit (Change Time) ein.' }
	@{ Name = 'MAX'; Group = 'Dateiauswahl'; Type = 'Bytes'; Help = 'Maximale Dateigroesse in Bytes - groessere Dateien werden ausgeschlossen. robocopy akzeptiert hier KEIN K/M/G.' }
	@{ Name = 'MIN'; Group = 'Dateiauswahl'; Type = 'Bytes'; Help = 'Minimale Dateigroesse in Bytes - kleinere Dateien werden ausgeschlossen.' }
	@{ Name = 'MAXAGE'; Group = 'Dateiauswahl'; Type = 'Age'; Help = 'Maximales Dateialter: schliesst Dateien aus, die aelter sind. Zahl < 1900 = Tage, sonst Datum JJJJMMTT.' }
	@{ Name = 'MINAGE'; Group = 'Dateiauswahl'; Type = 'Age'; Help = 'Minimales Dateialter: schliesst Dateien aus, die neuer sind. Zahl < 1900 = Tage, sonst Datum JJJJMMTT.' }
	@{ Name = 'MAXLAD'; Group = 'Dateiauswahl'; Type = 'Age'; Help = 'Maximales Datum des letzten Zugriffs: schliesst Dateien aus, die seit n nicht benutzt wurden.' }
	@{ Name = 'MINLAD'; Group = 'Dateiauswahl'; Type = 'Age'; Help = 'Minimales Datum des letzten Zugriffs: schliesst Dateien aus, die seit n benutzt wurden.' }
	@{ Name = 'FFT'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'FAT-Zeitstempel annehmen (2 Sekunden Genauigkeit). Noetig fuer NAS / Linux-Freigaben, sonst wird jedes Mal alles neu kopiert.' }
	@{ Name = 'DST'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Gleicht Zeitunterschiede von genau einer Stunde (Sommerzeit) aus.' }
	@{ Name = 'XJ'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst Links und Junctions aus (Dateien und Verzeichnisse). Verhindert Endlosschleifen z.B. bei Benutzerprofilen.' }
	@{ Name = 'XJD'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst symbolische Links und Junctions fuer Verzeichnisse aus.' }
	@{ Name = 'XJF'; Group = 'Dateiauswahl'; Type = 'Switch'; Help = 'Schliesst symbolische Links fuer Dateien aus.' }

	# --- Wiederholung -----------------------------------------------------------------------------
	@{ Name = 'R'; Group = 'Wiederholung'; Type = 'Int'; Min = 0; Max = 1000000; Default = '1000000'; Help = 'Wiederholungen bei Fehlern. Der Standard 1 Million laesst einen Job bei einer gesperrten Datei praktisch ewig haengen - fast immer explizit setzen (z.B. 3).' }
	@{ Name = 'W'; Group = 'Wiederholung'; Type = 'Int'; Min = 0; Max = 86400; Default = '30'; Help = 'Wartezeit in Sekunden zwischen den Wiederholungen. Standard 30.' }
	@{ Name = 'REG'; Group = 'Wiederholung'; Type = 'Switch'; Help = 'Speichert /R und /W als Standard in der Registrierung (HKCU) - wirkt danach auf alle robocopy-Aufrufe dieses Benutzers.' }
	@{ Name = 'TBD'; Group = 'Wiederholung'; Type = 'Switch'; Help = 'Wartet, bis Freigabenamen definiert sind (Wiederholung bei Fehler 67).' }
	@{ Name = 'LFSM'; Group = 'Wiederholung'; Type = 'Opt'; ValueKind = 'Size'; Help = 'Modus "wenig freier Speicherplatz": robocopy pausiert, wenn eine Kopie den freien Platz im Ziel unter die Untergrenze druecken wuerde. Optional Untergrenze n[K|M|G], ohne Wert 10 % des Volumes.' }

	# --- Drosselung & Zeitplan -------------------------------------------------------------------
	@{ Name = 'IPG'; Group = 'Drosselung & Zeitplan'; Type = 'Int'; Min = 1; Max = 60000; Help = 'Pause in Millisekunden zwischen Paketen (64 KB), um Bandbreite auf langsamen Leitungen freizugeben. Nicht mit /MT kombinierbar.' }
	@{ Name = 'IoMaxSize'; Group = 'Drosselung & Zeitplan'; Type = 'Size'; Help = 'Maximale E/A-Groesse je Lese-/Schreibzyklus in n[K|M|G] Bytes.' }
	@{ Name = 'IoRate'; Group = 'Drosselung & Zeitplan'; Type = 'Size'; Help = 'Angestrebte E/A-Rate in n[K|M|G] Bytes pro Sekunde (z.B. 50M) - begrenzt die Last auf Quelle und Ziel.' }
	@{ Name = 'Threshold'; Group = 'Drosselung & Zeitplan'; Type = 'Size'; Help = 'Dateigroesse in n[K|M|G] Bytes, ab der die Drosselung (/IoRate, /IoMaxSize) greift.' }
	@{ Name = 'RH'; Group = 'Drosselung & Zeitplan'; Type = 'Hours'; Help = 'Ausfuehrungszeiten hhmm-hhmm: neue Kopien starten nur in diesem Fenster (z.B. 2200-0600), sonst wartet robocopy.' }
	@{ Name = 'PF'; Group = 'Drosselung & Zeitplan'; Type = 'Switch'; Help = 'Prueft die Ausfuehrungszeiten (/RH) je Datei statt je Durchlauf.' }
	@{ Name = 'MON'; Group = 'Drosselung & Zeitplan'; Type = 'Int'; Min = 1; Max = 1000000; Help = 'Ueberwacht die Quelle und laeuft erneut, sobald mehr als n Aenderungen erkannt werden. robocopy endet dann NICHT von selbst.' }
	@{ Name = 'MOT'; Group = 'Drosselung & Zeitplan'; Type = 'Int'; Min = 1; Max = 100000; Help = 'Ueberwacht die Quelle und laeuft nach m Minuten erneut, wenn sich etwas geaendert hat. robocopy endet dann NICHT von selbst.' }

	# --- Protokoll -------------------------------------------------------------------------------
	@{ Name = 'L'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Nur auflisten: es wird nichts kopiert, geloescht oder mit Zeitstempel versehen. Ideal als Trockenlauf.' }
	@{ Name = 'LOG'; Group = 'Protokoll'; Type = 'Path'; Picker = 'SaveLog'; Exclusive = 'Log'; Help = 'Schreibt die Ausgabe in eine Protokolldatei (ueberschreibt sie). Ohne /TEE erscheint dann nichts mehr in der Konsole.' }
	@{ Name = 'LOG+'; Group = 'Protokoll'; Type = 'Path'; Picker = 'SaveLog'; Exclusive = 'Log'; Help = 'Haengt die Ausgabe an eine vorhandene Protokolldatei an.' }
	@{ Name = 'UNILOG'; Group = 'Protokoll'; Type = 'Path'; Picker = 'SaveLog'; Exclusive = 'Log'; Help = 'Protokolldatei als Unicode (ueberschreibt sie). Noetig, wenn Dateinamen Zeichen ausserhalb der Codepage enthalten.' }
	@{ Name = 'UNILOG+'; Group = 'Protokoll'; Type = 'Path'; Picker = 'SaveLog'; Exclusive = 'Log'; Help = 'Haengt als Unicode an eine vorhandene Protokolldatei an.' }
	@{ Name = 'TEE'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Ausgabe zusaetzlich zur Protokolldatei auch in der Konsole.' }
	@{ Name = 'NP'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Kein Fortschritt in Prozent. Fuer Protokolldateien fast immer sinnvoll, sonst stehen dort tausende Prozentangaben.' }
	@{ Name = 'ETA'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Zeigt die voraussichtliche Ankunftszeit der kopierten Dateien.' }
	@{ Name = 'X'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Meldet alle zusaetzlichen Dateien (nur im Ziel), nicht nur die ausgewaehlten.' }
	@{ Name = 'V'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Ausfuehrliche Ausgabe, auch uebersprungene Dateien.' }
	@{ Name = 'TS'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Gibt die Zeitstempel der Quelldateien aus.' }
	@{ Name = 'FP'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Gibt den vollstaendigen Pfad der Dateien aus.' }
	@{ Name = 'BYTES'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Groessen in Bytes statt k/m/g.' }
	@{ Name = 'NS'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Keine Dateigroessen protokollieren.' }
	@{ Name = 'NC'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Keine Dateiklassen (Neue Datei, Aelter, ...) protokollieren.' }
	@{ Name = 'NFL'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Keine Dateiliste - Dateinamen werden nicht protokolliert.' }
	@{ Name = 'NDL'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Keine Verzeichnisliste - Verzeichnisnamen werden nicht protokolliert.' }
	@{ Name = 'NJH'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Kein Auftragskopf.' }
	@{ Name = 'NJS'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Keine Auftragszusammenfassung (Statistik am Ende).' }
	@{ Name = 'UNICODE'; Group = 'Protokoll'; Type = 'Switch'; Help = 'Gibt den Status als Unicode aus.' }

	# --- Auftragsdatei ---------------------------------------------------------------------------
	@{ Name = 'JOB'; Group = 'Auftragsdatei'; Type = 'Path'; Picker = 'OpenJob'; Help = 'Liest weitere Parameter aus einer robocopy-Auftragsdatei (.RCJ).' }
	@{ Name = 'SAVE'; Group = 'Auftragsdatei'; Type = 'Path'; Picker = 'SaveJob'; Help = 'Speichert die Parameter in eine Auftragsdatei (.RCJ). Hinweis: robocopy speichert dabei z.B. /MT, /IoRate und /LFSM nicht mit.' }
	@{ Name = 'QUIT'; Group = 'Auftragsdatei'; Type = 'Switch'; Help = 'Beendet robocopy nach dem Auswerten der Befehlszeile (nur Parameter anzeigen, z.B. zusammen mit /SAVE).' }
	@{ Name = 'NOSD'; Group = 'Auftragsdatei'; Type = 'Switch'; Help = 'Kein Quellverzeichnis angegeben (kommt aus der Auftragsdatei).' }
	@{ Name = 'NODD'; Group = 'Auftragsdatei'; Type = 'Switch'; Help = 'Kein Zielverzeichnis angegeben (kommt aus der Auftragsdatei).' }
)

function Get-srgParameterDefinition {
	foreach ($p in $script:srgParameters) { [pscustomobject]$p }
}

function Get-srgParameterLookup {
	# Name -> Definition, unabhaengig von Gross-/Kleinschreibung
	if (-not $script:srgLookup) {
		$script:srgLookup = @{}
		foreach ($d in Get-srgParameterDefinition) { $script:srgLookup[$d.Name] = $d }
	}
	$script:srgLookup
}

# robocopy-Exitcode ist eine Bitmaske. Bewusst eine Liste von Hashtables: ein [ordered]-Dictionary mit
# int-Schluesseln wuerde bei $d[1] nach POSITION indizieren, verschachtelte Arrays rollt PowerShell aus.
$script:srgExitBits = @(
	@{ Bit = 1; Text = 'Dateien kopiert' }
	@{ Bit = 2; Text = 'zusaetzliche Dateien/Verzeichnisse im Ziel' }
	@{ Bit = 4; Text = 'abweichende Dateien/Verzeichnisse (Mismatch)' }
	@{ Bit = 8; Text = 'einige Dateien/Verzeichnisse konnten NICHT kopiert werden' }
	@{ Bit = 16; Text = 'schwerer Fehler - robocopy hat nichts kopiert (Parameter, Zugriff, Pfad)' }
)
