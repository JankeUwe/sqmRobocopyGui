<#
	Selbsttest fuer sqmRobocopyGui. Laeuft unter Windows PowerShell 5.1 und PowerShell 7.

	  .\Test-sqmRobocopyGui.ps1            Generator, Pruefregeln, Import, echte robocopy-Laeufe, GUI
	  .\Test-sqmRobocopyGui.ps1 -NoGui     ohne GUI-Teil (z.B. in einer Sitzung ohne Desktop)

	Die echten Laeufe arbeiten nur in einem Testordner unter %TEMP% und raeumen ihn wieder ab.
#>
param([switch]$NoGui)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\sqmRobocopyGui.psd1') -Force

$script:fail = 0
function Assert-That([bool]$Condition, [string]$Name) {
	if ($Condition) { Write-Host "  OK    $Name" -ForegroundColor Green }
	else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:fail++ }
}
function Test-HasIssue([hashtable]$P, [string]$Param, [string]$Severity = 'Error') {
	[bool](@(Test-sqmRobocopyParameter -Parameter $P) | Where-Object { $_.Severity -eq $Severity -and $_.Parameter -eq $Param })
}
$m = Get-Module sqmRobocopyGui

# Testordner mit Leerzeichen, Umlaut und Prozentzeichen im Namen
$root = Join-Path ([IO.Path]::GetTempPath()) ("srgTest " + [guid]::NewGuid().ToString('N').Substring(0, 6) + " " + [char]0x00E4 + " 100%")
$src = Join-Path $root 'Quelle A'
$dst = Join-Path $root 'Ziel B'
[void](New-Item -ItemType Directory -Path (Join-Path $src 'sub 1'), (Join-Path $src 'skip me'), (Join-Path $src 'leer') -Force)
Set-Content (Join-Path $src 'a.txt') 'a'
Set-Content (Join-Path $src 'b.bak') 'b'
Set-Content (Join-Path $src 'Thumbs.db') 't'
Set-Content (Join-Path $src 'sub 1\c.txt') 'c'
Set-Content (Join-Path $src 'skip me\d.txt') 'd'

try {
	Write-Host 'Parameterdefinition' -ForegroundColor Cyan
	$defs = @(& $m { Get-srgParameterDefinition })
	Assert-That ($defs.Count -ge 90) "alle robocopy-Optionen definiert ($($defs.Count))"
	Assert-That (@($defs.Name | Select-Object -Unique).Count -eq $defs.Count) 'keine doppelten Namen'
	Assert-That (-not ($defs | Where-Object { -not $_.Help })) 'jede Option hat einen Hilfetext'
	Assert-That (-not ($defs | Where-Object { $_.Type -notin 'Switch', 'Int', 'Bytes', 'Size', 'Age', 'Hours', 'Flags', 'Opt', 'List', 'Path' })) 'nur bekannte Typen'
	# jede Option muss robocopy selbst kennen (/QUIT = nur Befehlszeile auswerten)
	$exe = Join-Path $env:SystemRoot 'System32\Robocopy.exe'
	$sample = @{ Int = '2'; Bytes = '1000'; Size = '1M'; Age = '7'; Hours = '2200-0600'; Path = (Join-Path $root 'x.log') }
	$rejected = @()
	foreach ($d in $defs) {
		if ($d.Name -in 'JOB', 'SAVE', 'QUIT', 'REG', 'MON', 'MOT', 'NOSD', 'NODD') { continue }
		$tok = switch ($d.Type) {
			'Switch' { "/$($d.Name)" }
			'Opt' { "/$($d.Name)" }
			'Flags' { "/$($d.Name):$($d.Letters.Substring(0, 1))" }
			'List' { "/$($d.Name)"; 'x' }
			default { "/$($d.Name):$($sample[$d.Type])" }
		}
		$null = & $exe $src $dst @($tok) /QUIT 2>&1
		if ($LASTEXITCODE -ge 8) { $rejected += $d.Name }
	}
	Assert-That ($rejected.Count -eq 0) ("robocopy akzeptiert jede Option {0}" -f $(if ($rejected) { '- abgelehnt: ' + ($rejected -join ', ') } else { '' }))

	Write-Host 'Befehlserzeugung' -ForegroundColor Cyan
	$cmd = New-sqmRobocopyCommand -Parameter @{ Source = 'D:\Daten\'; Destination = '\\nas\backup\Daten 2026\'; E = $true; R = 3 }
	Assert-That ($cmd -eq 'robocopy D:\Daten "\\nas\backup\Daten 2026" /E /R:3') "abschliessender Backslash entfernt, nur bei Bedarf gequotet ($cmd)"
	$cmd = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\'; Destination = 'E:\' }
	Assert-That ($cmd -eq 'robocopy C:\ E:\') 'Laufwerkswurzel bleibt C:\ (ungequotet)'
	$cmd = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B'; R = 1; E = $true; MT = $true; XF = '*.tmp; Thumbs.db'; 'LOG+' = 'C:\L og\x.log' }
	Assert-That ($cmd.IndexOf('/E') -lt $cmd.IndexOf('/MT') -and $cmd.IndexOf('/XF') -lt $cmd.IndexOf('/R:1')) 'feste Reihenfolge der Optionen'
	Assert-That ($cmd -match '/XF \*\.tmp Thumbs\.db') 'Liste mit ; getrennt'
	Assert-That ($cmd -match '/LOG\+:"C:\\L og\\x\.log"') 'Pfadwert: nur der Wert gequotet'
	Assert-That ($cmd -match '/MT( |$)') 'Opt ohne Wert'
	Assert-That ((New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B'; MT = 16 }) -match '/MT:16') 'Opt mit Wert'
	$bat = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\100% A'; Destination = 'C:\B' } -Format Batch
	Assert-That ($bat -match '"C:\\100%% A"') 'Batch verdoppelt %'
	Assert-That ($bat -match 'chcp 65001') 'Batch schaltet auf UTF-8'
	$ps = New-sqmRobocopyCommand -Parameter @{ Source = "C:\O'Brien"; Destination = 'C:\B' } -Format PowerShell
	Assert-That ($ps -match "'C:\\O''Brien'") 'PowerShell verdoppelt Hochkomma'
	$args_ = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B'; XD = @('x', 'y') } -Format Arguments
	Assert-That (($args_ -join '|') -eq 'C:\A|C:\B|/XD|x|y') 'Format Arguments liefert die rohe Liste'
	$task = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B'; E = $true } -Format ScheduledTask -ScheduleType Weekly -ScheduleWeekDays Monday, Friday -ScheduleTime '23:30'
	Assert-That ($task -match "New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Friday -At '23:30'") 'Aufgabe: woechentlicher Trigger'
	Assert-That ($task -match '\$taskName  = ''Robocopy A nach B''') 'Aufgabe: Name automatisch'
	$none = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B' } -Format ScheduledTask -ScheduleType None
	Assert-That ($none -notmatch '\$trigger') 'Aufgabe ohne Zeitplan hat keinen Trigger'
	$tsOk = $true
	foreach ($t in 'CommandLine', 'Batch', 'PowerShell', 'ScheduledTask') {
		$code = New-sqmRobocopyCommand -Parameter @{ Source = 'C:\A'; Destination = 'C:\B'; E = $true } -Format $t
		if ($t -in 'PowerShell', 'ScheduledTask') {
			$err = $null; [void][System.Management.Automation.PSParser]::Tokenize($code, [ref]$err)
			if ($err.Count) { $tsOk = $false }
		}
	}
	Assert-That $tsOk 'PowerShell-Ausgaben sind syntaktisch gueltig'
	$threw = $false; try { New-sqmRobocopyCommand -Parameter @{ Source = 'a'; Destination = 'b'; Foo = 1 } | Out-Null } catch { $threw = $true }
	Assert-That $threw 'unbekannte Option wirft'

	Write-Host 'Pruefregeln' -ForegroundColor Cyan
	$ok = @{ Source = 'C:\A'; Destination = 'D:\B'; E = $true; R = 3; W = 5 }
	Assert-That (@(Test-sqmRobocopyParameter -Parameter $ok).Count -eq 0) 'gueltige Kombination ohne Befund'
	Assert-That (Test-HasIssue @{ Destination = 'D:\B' } 'Source') 'Quelle fehlt'
	Assert-That (Test-HasIssue @{ Source = 'C:\A'; Destination = 'c:\a\' } 'Destination') 'Quelle = Ziel'
	Assert-That (Test-HasIssue @{ Source = 'C:\A\B'; Destination = 'C:\A'; MIR = $true } 'Destination') 'Quelle im Ziel mit /MIR'
	Assert-That (Test-HasIssue @{ Source = 'C:\A'; Destination = 'C:\A\B'; E = $true } 'Destination' 'Warning') 'Ziel in der Quelle (Warnung)'
	Assert-That (Test-HasIssue @{ Source = 'C:\A\*.txt'; Destination = 'D:\B' } 'Source') 'Platzhalter im Verzeichnis'
	Assert-That (Test-HasIssue (@{ S = $true } + $ok) 'S') 'exklusiv: /S und /E'
	Assert-That (Test-HasIssue (@{ LOG = 'a.log'; 'LOG+' = 'b.log'; NP = $true } + $ok) 'LOG') 'exklusiv: /LOG und /LOG+'
	Assert-That (Test-HasIssue (@{ MT = 200 } + $ok) 'MT') '/MT ausserhalb 1-128'
	Assert-That (Test-HasIssue (@{ MT = $true; IPG = 5 } + $ok) 'IPG') '/MT mit /IPG'
	Assert-That (Test-HasIssue (@{ MAX = '1M' } + $ok) 'MAX') '/MAX ohne K/M/G'
	Assert-That (Test-HasIssue (@{ MAXAGE = '20261332' } + $ok) 'MAXAGE') '/MAXAGE ungueltiges Datum'
	Assert-That (-not (Test-HasIssue (@{ MAXAGE = '30' } + $ok) 'MAXAGE')) '/MAXAGE in Tagen gueltig'
	Assert-That (Test-HasIssue (@{ RH = '2500-0600' } + $ok) 'RH') '/RH ungueltig'
	Assert-That (-not (Test-HasIssue (@{ RH = '2200-0600' } + $ok) 'RH')) '/RH ueber Mitternacht gueltig'
	Assert-That (Test-HasIssue (@{ COPY = 'DATQ' } + $ok) 'COPY') '/COPY unbekannter Buchstabe'
	Assert-That (Test-HasIssue (@{ IoRate = '10X' } + $ok) 'IoRate') '/IoRate ungueltige Groesse'
	Assert-That (Test-HasIssue (@{ MIN = '100'; MAX = '10' } + $ok) 'MIN') '/MIN > /MAX'
	Assert-That (Test-HasIssue (@{ Source = 'C:\A'; Destination = 'D:\B'; MIR = $true; R = 3 }) 'MIR' 'Warning') '/MIR warnt'
	Assert-That (-not (Test-HasIssue (@{ Source = 'C:\A'; Destination = 'D:\B'; MIR = $true; L = $true; R = 3 }) 'MIR' 'Warning')) '/MIR mit /L warnt nicht'
	Assert-That (Test-HasIssue (@{ Source = 'C:\A'; Destination = 'E:\'; MIR = $true; R = 3 }) 'Destination' 'Warning') '/MIR auf Laufwerkswurzel warnt'
	Assert-That (Test-HasIssue @{ Source = 'C:\A'; Destination = 'D:\B' } 'R' 'Warning') 'ohne /R warnt'
	Assert-That (Test-HasIssue (@{ LOG = 'C:\x.log' } + $ok) 'NP' 'Warning') 'Protokoll ohne /NP warnt'
	Assert-That (Test-HasIssue (@{ COPYALL = $true } + $ok) 'COPYALL' 'Warning') '/COPYALL braucht Adminrechte'
	Assert-That (Test-HasIssue (@{ Foo = 1 } + $ok) 'Foo') 'unbekannte Option'
	Assert-That ([bool](@(Test-sqmRobocopyParameter -Parameter @{ Source = (Join-Path $root 'gibtsnicht'); Destination = $dst; R = 1 } -CheckPath) | Where-Object Parameter -eq 'Source')) '-CheckPath findet fehlende Quelle'

	Write-Host 'Import' -ForegroundColor Cyan
	$line = 'robocopy "D:\Daten\" \\nas\backup *.docx *.xlsx /MIR /R:3 /W:5 /XD "~tmp" "C:\x y" /XF Thumbs.db /LOG+:"C:\Logs\a b.log" /MT /SPARSE:N /RH:2200-0600'
	$h = ConvertFrom-sqmRobocopyCommand $line
	Assert-That ($h.Source -eq 'D:\Daten' -and $h.Destination -eq '\\nas\backup') 'Quelle/Ziel'
	Assert-That (($h.Files -join ',') -eq '*.docx,*.xlsx') 'Dateien'
	Assert-That ($h.MIR -eq $true -and $h.R -eq '3' -and $h.MT -eq $true -and $h.SPARSE -eq 'N') 'Schalter, Zahl, Opt'
	Assert-That (($h.XD -join '|') -eq '~tmp|C:\x y' -and ($h.XF -join '|') -eq 'Thumbs.db') 'Listen'
	Assert-That ($h['LOG+'] -eq 'C:\Logs\a b.log') 'Pfad mit Leerzeichen'
	$round = ConvertFrom-sqmRobocopyCommand (New-sqmRobocopyCommand -Parameter $h)
	Assert-That ((New-sqmRobocopyCommand -Parameter $round) -eq (New-sqmRobocopyCommand -Parameter $h)) 'Rundreise Befehl -> Import -> Befehl'
	$psLine = New-sqmRobocopyCommand -Parameter $h -Format PowerShell
	$psArgs = ($psLine -split "`n" | Where-Object { $_ -match "^\s+'" }) -join ' '
	$h2 = ConvertFrom-sqmRobocopyCommand "& robocopy.exe $psArgs"
	Assert-That ((New-sqmRobocopyCommand -Parameter $h2) -eq (New-sqmRobocopyCommand -Parameter $h)) 'Import einer PowerShell-Argumentliste'
	$h3 = ConvertFrom-sqmRobocopyCommand "robocopy C:\A C:\B ^`r`n /E ^`r`n /R:1" -WarningAction SilentlyContinue
	Assert-That ($h3.E -and $h3.R -eq '1') 'Batch-Zeilenfortsetzung mit ^'
	$warn = $null
	$h4 = ConvertFrom-sqmRobocopyCommand 'robocopy C:\A C:\B /E /BOGUS' -WarningVariable warn -WarningAction SilentlyContinue
	Assert-That ($h4.E -and $warn.Count -eq 1) 'unbekannte Option als Warnung'

	# Auftragsdatei: robocopy selbst schreiben lassen, dann einlesen
	$job = Join-Path $root 'test'
	$null = & $exe $src $dst '*.txt' '*.bak' /E /XF Thumbs.db /XD 'skip me' /R:2 /W:1 /COPY:DAT /RH:0100-0500 "/LOG+:$(Join-Path $root 'j b.log')" "/SAVE:$job" /QUIT
	$hj = ConvertFrom-sqmRobocopyCommand -JobFile "$job.RCJ"
	Assert-That ($hj.Source -eq $src -and $hj.Destination -eq $dst) "RCJ: Quelle/Ziel mit Leerzeichen"
	if ($hj.Source -ne $src) { Write-Host ("    DIAG got=[{0}] {1} exp=[{2}] {3}" -f $hj.Source, (([int[]]$hj.Source.ToCharArray() | Where-Object { $_ -gt 127 }) -join ','), $src, (([int[]]$src.ToCharArray() | Where-Object { $_ -gt 127 }) -join ',')) }
	Assert-That (($hj.Files -join ',') -eq '*.txt,*.bak') 'RCJ: Dateien (/IF)'
	Assert-That ($hj.E -and -not $hj.ContainsKey('S')) 'RCJ: /E ohne das von robocopy ergaenzte /S'
	Assert-That (($hj.XD -join ',') -eq 'skip me' -and ($hj.XF -join ',') -eq 'Thumbs.db') 'RCJ: Listen'
	Assert-That ($hj.RH -eq '0100-0500') 'RCJ: /RH mit fuehrender Null'
	Assert-That ($hj['LOG+'] -eq (Join-Path $root 'j b.log')) 'RCJ: Protokollpfad mit Leerzeichen'

	Write-Host 'Echte robocopy-Laeufe' -ForegroundColor Cyan
	$p = @{ Source = "$src\"; Destination = "$dst\"; E = $true; XD = 'skip me'; XF = 'Thumbs.db'; R = 1; W = 1; NP = $true }
	# Kommandozeile ueber cmd.exe
	$cl = New-sqmRobocopyCommand -Parameter $p
	$null = cmd.exe /d /c $cl
	$copied = @(Get-ChildItem $dst -Recurse -File | ForEach-Object { $_.FullName.Substring($dst.Length + 1) } | Sort-Object)
	Assert-That ($LASTEXITCODE -eq 1 -and ($copied -join ',') -eq 'a.txt,b.bak,sub 1\c.txt') "Kommandozeile kopiert richtig ($($copied -join ', '))"
	Assert-That (Test-Path (Join-Path $dst 'leer')) '/E legt leere Ordner an'
	Remove-Item $dst -Recurse -Force
	# Batch-Datei
	$batFile = Join-Path $root 'run.cmd'
	[IO.File]::WriteAllText($batFile, (New-sqmRobocopyCommand -Parameter $p -Format Batch), (New-Object Text.UTF8Encoding($false)))
	$out = cmd.exe /d /c "`"$batFile`""
	Assert-That ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $dst 'sub 1\c.txt')) -and ($out -join ' ') -match 'robocopy OK - Exitcode 1') 'Batch kopiert, Exitcode 1 -> 0'
	# PowerShell-Skript mit Protokolldatei (Prozent und Umlaut im Pfad)
	Remove-Item $dst -Recurse -Force
	$log = Join-Path $root 'log 100%.log'
	$psCode = New-sqmRobocopyCommand -Parameter ($p + @{ LOG = $log }) -Format PowerShell
	$null = & ([scriptblock]::Create($psCode)) 6>&1
	Assert-That ((Test-Path (Join-Path $dst 'a.txt')) -and (Test-Path -LiteralPath $log)) 'PowerShell kopiert und schreibt Protokoll'
	# /MIR loescht Extras, /L aendert nichts
	Set-Content (Join-Path $dst 'extra.txt') 'x'
	$null = & $exe @(New-sqmRobocopyCommand -Parameter ($p + @{ MIR = $true; L = $true }) -Format Arguments)
	Assert-That (Test-Path (Join-Path $dst 'extra.txt')) '/L loescht nichts'
	$mir = @{} + $p; $mir.Remove('E'); $mir.MIR = $true
	$null = & $exe @(New-sqmRobocopyCommand -Parameter $mir -Format Arguments)
	Assert-That (-not (Test-Path (Join-Path $dst 'extra.txt'))) '/MIR entfernt Extras im Ziel'
	$fatal = & $exe @(New-sqmRobocopyCommand -Parameter @{ Source = (Join-Path $root 'gibtsnicht'); Destination = $dst; R = 0 } -Format Arguments)
	$info = ConvertFrom-sqmRobocopyExitCode $LASTEXITCODE
	Assert-That (-not $info.Success -and $info.ExitCode -ge 8) "fehlende Quelle -> Exitcode $($info.ExitCode) = Fehler"

	if (-not $NoGui) {
		Write-Host 'GUI' -ForegroundColor Cyan
		Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
		$form = Show-sqmRobocopyGui -Source $src -Destination $dst -PassThru
		try {
			$ui = & $m { $script:srgUi }
			$ui.Confirm = $false
			Assert-That ($ui.Fields.Count -eq $defs.Count) "alle $($defs.Count) Optionen als Feld"
			Assert-That ($ui.Output.Text -like 'robocopy *') 'Befehl wird angezeigt'
			Assert-That ($ui.Fields['E'].Check.Checked -and $ui.Fields['R'].Text.Text -eq '3') 'Startwerte /E /R:3 /W:5'
			$ui.Fields['MIR'].Check.Checked = $true
			Assert-That (-not $ui.Fields['E'].Check.Checked) 'exklusive Option waehlt die andere ab'
			$ui.Fields['MT'].Check.Checked = $true
			$ui.Fields['MT'].Text.Text = '4'
			Assert-That ($ui.Output.Text -match '/MIR /MT:4') 'Opt-Feld mit Wert'
			$ui.Fields['COPY'].Letters['D'].Checked = $true; $ui.Fields['COPY'].Letters['A'].Checked = $true
			Assert-That ($ui.Output.Text -match '/COPY:DA') 'Buchstaben-Feld'
			$ui.Fields['SEC'].Check.Checked = $true
			Assert-That ($ui.Output.Text -notmatch '/COPY:' -and $ui.Output.Text -match '/SEC') 'exklusiv ueber Typen hinweg (/SEC leert /COPY)'
			$ui.Fields['SEC'].Check.Checked = $false
			$ui.Fields['XD'].Text.Text = 'skip me'
			$ui.Fields['XF'].Text.Text = 'Thumbs.db'
			foreach ($k in @($ui.Formats.Keys)) {
				$ui.Formats[$k].Checked = $true
				Assert-That ($ui.Output.Text -and $ui.Output.Text -notmatch 'kann nicht erzeugt') "Format $k"
			}
			Assert-That ($ui.TaskBox.Visible -and $ui.CreateTask.Visible) 'Aufgaben-Optionen bei Geplante Aufgabe sichtbar'
			$ui.Formats['CommandLine'].Checked = $true
			Assert-That (-not $ui.TaskBox.Visible) 'Aufgaben-Optionen sonst ausgeblendet'
			& $m { Set-srgPreset 'SQL-Backups verteilen (*.bak, *.trn)' }
			Assert-That ($ui.Files.Text -eq '*.bak; *.trn' -and $ui.Source.Text -eq $src) 'Vorlage setzt Dateien, behaelt Quelle'
			& $m { Set-srgValues (ConvertFrom-sqmRobocopyCommand $args[0]) } $line
			Assert-That ($ui.Output.Text -eq (New-sqmRobocopyCommand -Parameter $h)) 'Import in die GUI ergibt denselben Befehl'

			# echter Lauf ueber den Runner: Trockenlauf, dann Kopie
			& $m { Set-srgValues $args[0] } $p
			& $m { Start-srgRun -DryRun }
			$t = [DateTime]::Now
			while (($ui.Timer.Enabled -or -not $ui.Runner.Finished) -and ([DateTime]::Now - $t).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 50; [System.Windows.Forms.Application]::DoEvents() }
			Assert-That ($ui.Runner.ExitCode -eq 1 -and -not (Test-Path $dst)) 'GUI-Trockenlauf: Exitcode 1, nichts kopiert'
			Assert-That ($ui.RunLog.Text -match 'Trockenlauf - Exitcode 1' -and $ui.Run.Enabled) 'GUI-Trockenlauf: Ergebnis im Protokoll, Knoepfe wieder aktiv'
			& $m { Start-srgRun }
			$t = [DateTime]::Now
			while (($ui.Timer.Enabled -or -not $ui.Runner.Finished) -and ([DateTime]::Now - $t).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 50; [System.Windows.Forms.Application]::DoEvents() }
			Assert-That ($ui.Runner.ExitCode -eq 1 -and (Test-Path (Join-Path $dst 'sub 1\c.txt')) -and -not (Test-Path (Join-Path $dst 'skip me'))) 'GUI-Lauf kopiert mit /XD'
			Assert-That ($ui.RunLog.Text -match ([regex]::Escape('c.txt'))) 'GUI-Lauf: Dateien im Live-Protokoll'
			Assert-That ($ui.DestinationState.Text -eq 'vorhanden') 'Zielstatus nach dem Lauf aktualisiert'
			# Abbrechen
			$ui.Fields['E'].Check.Checked = $true
			$ui.Fields['MON'].Text.Text = '1'
			& $m { Start-srgRun }
			Start-Sleep -Milliseconds 800
			& $m { Stop-srgRun }
			$t = [DateTime]::Now
			while (($ui.Timer.Enabled -or -not $ui.Runner.Finished) -and ([DateTime]::Now - $t).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 50; [System.Windows.Forms.Application]::DoEvents() }
			Assert-That ($ui.Runner.Cancelled -and $ui.Runner.Finished -and $ui.RunLog.Text -match 'Abgebrochen') 'Abbrechen beendet einen /MON-Lauf'
		} finally {
			$form.Close(); $form.Dispose()
		}
	}
} finally {
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail) { Write-Host "$script:fail Test(s) FEHLGESCHLAGEN" -ForegroundColor Red; exit 1 }
Write-Host 'Alle Tests bestanden.' -ForegroundColor Green
