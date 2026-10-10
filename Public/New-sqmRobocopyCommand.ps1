function New-sqmRobocopyCommand {
	<#
	.SYNOPSIS
		Erzeugt einen robocopy-Aufruf als Kommandozeile, Batch-Datei, PowerShell-Skript oder
		Skript fuer eine geplante Aufgabe.
	.DESCRIPTION
		Nur die in -Parameter gesetzten Optionen landen im Befehl, in fester Reihenfolge (Quelle,
		Ziel, Dateien, Optionen wie in der GUI). Verzeichnisse werden ohne abschliessenden Backslash
		ausgegeben - "C:\Ziel\" in Anfuehrungszeichen ist der haeufigste robocopy-Fehler.
	.PARAMETER Parameter
		Hashtable mit Source, Destination, Files (Array oder ;-getrennt) und den robocopy-Optionen
		ohne Schraegstrich: @{ E = $true; R = 3; XF = '*.tmp;Thumbs.db'; MT = 16; LOG = 'C:\x.log' }.
		Optionen mit optionalem Wert (MT, SPARSE, LFSM) als $true (ohne Wert) oder mit Wert.
	.PARAMETER Format
		CommandLine (Standard), Batch (.cmd mit Exitcode-Auswertung), PowerShell, ScheduledTask
		(Register-ScheduledTask-Skript) oder Arguments (rohe Argumentliste als string[]).
	.EXAMPLE
		New-sqmRobocopyCommand -Parameter @{ Source = 'D:\Daten'; Destination = '\\nas\backup\Daten'; MIR = $true; R = 3; W = 5; MT = 16 }
	.EXAMPLE
		New-sqmRobocopyCommand -Parameter $p -Format ScheduledTask -ScheduleType Daily -ScheduleTime 22:00
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][hashtable]$Parameter,
		[ValidateSet('CommandLine', 'Batch', 'PowerShell', 'ScheduledTask', 'Arguments')][string]$Format = 'CommandLine',
		[string]$TaskName,
		[string]$TaskPath = '\sqmRobocopy\',
		[string]$TaskUser = 'SYSTEM',
		[ValidateSet('None', 'Once', 'Daily', 'Weekly', 'Interval')][string]$ScheduleType = 'Daily',
		[string]$ScheduleTime = '22:00',
		[ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')][string[]]$ScheduleWeekDays = @('Sunday'),
		[ValidateRange(1, 1440)][int]$IntervalMinutes = 60
	)

	$unknown = @($Parameter.Keys | Where-Object { $_ -notin 'Source', 'Destination', 'Files' -and -not (Get-srgParameterLookup).ContainsKey($_) })
	if ($unknown.Count) { throw "Unbekannte robocopy-Option(en): $($unknown -join ', ')" }

	$args_ = Get-srgArgumentList -Parameter $Parameter
	# bewusst ohne Komma-Operator: '& robocopy.exe @(New-sqmRobocopyCommand ... -Format Arguments)' braucht eine flache Liste
	if ($Format -eq 'Arguments') { return $args_ }

	$src = [string]$Parameter['Source']
	$dst = [string]$Parameter['Destination']
	$head = "sqmRobocopyGui $script:srgModuleVersion - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

	switch ($Format) {
		'CommandLine' { return 'robocopy ' + (Join-srgCmdLine $args_) }

		'Batch' {
			$lines = @(
				'@echo off'
				":: robocopy - erzeugt mit $head"
				':: Exitcode 0-7 = Erfolg (Bitmaske: 1 kopiert, 2 Extra, 4 Mismatch), ab 8 = Fehler'
				'chcp 65001 >nul'
				''
				('robocopy ' + (Join-srgCmdLine $args_ -Batch))
				'set "RC=%ERRORLEVEL%"'
				''
				'if %RC% GEQ 8 ('
				'    echo robocopy FEHLER - Exitcode %RC%'
				'    exit /b %RC%'
				')'
				'echo robocopy OK - Exitcode %RC%'
				'exit /b 0'
			)
			return ($lines -join "`r`n")
		}

		'PowerShell' {
			$sb = New-Object System.Text.StringBuilder
			[void]$sb.AppendLine("# robocopy - erzeugt mit $head")
			[void]$sb.AppendLine('# Exitcode 0-7 = Erfolg (Bitmaske: 1 kopiert, 2 Extra, 4 Mismatch), ab 8 = Fehler')
			[void]$sb.AppendLine('$robocopyArgs = @(')
			foreach ($a in $args_) { [void]$sb.AppendLine("    $(Format-srgPsArg $a)") }
			[void]$sb.AppendLine(')')
			[void]$sb.AppendLine('')
			[void]$sb.AppendLine('& robocopy.exe @robocopyArgs')
			[void]$sb.AppendLine('$rc = $LASTEXITCODE')
			[void]$sb.AppendLine('if ($rc -ge 8) { throw "robocopy fehlgeschlagen - Exitcode $rc" }')
			[void]$sb.Append('Write-Host "robocopy OK - Exitcode $rc"')
			return $sb.ToString()
		}

		'ScheduledTask' {
			if (-not $TaskName) {
				$leaf = { param($p) if ($p) { (ConvertTo-srgDirectory $p).TrimEnd('\').Split('\')[-1] } else { '?' } }
				$TaskName = "Robocopy $(& $leaf $src) nach $(& $leaf $dst)"
			}
			if (-not $TaskPath.StartsWith('\')) { $TaskPath = '\' + $TaskPath }
			if (-not $TaskPath.EndsWith('\')) { $TaskPath += '\' }
			if ($ScheduleTime -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') { throw "Ungueltige Uhrzeit '$ScheduleTime' (erwartet HH:mm)." }
			$q = { param($s) "'" + "$s".Replace("'", "''") + "'" }

			$trigger = switch ($ScheduleType) {
				'None' { $null }
				'Once' { "New-ScheduledTaskTrigger -Once -At $(& $q $ScheduleTime)" }
				'Daily' { "New-ScheduledTaskTrigger -Daily -At $(& $q $ScheduleTime)" }
				'Weekly' { "New-ScheduledTaskTrigger -Weekly -DaysOfWeek $($ScheduleWeekDays -join ', ') -At $(& $q $ScheduleTime)" }
				'Interval' { "New-ScheduledTaskTrigger -Once -At $(& $q $ScheduleTime) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)" }
			}
			$principal = if ($TaskUser -eq 'SYSTEM') {
				"New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest"
			} else {
				"New-ScheduledTaskPrincipal -UserId $(& $q $TaskUser) -LogonType Interactive -RunLevel Limited"
			}
			$desc = "robocopy $(ConvertTo-srgDirectory $src) -> $(ConvertTo-srgDirectory $dst) (sqmRobocopyGui $script:srgModuleVersion)"

			$lines = @(
				"# Geplante Aufgabe fuer robocopy - erzeugt mit $head"
				'# Als Administrator ausfuehren. Ergebnis 0x0-0x7 in der Aufgabenplanung = Erfolg, ab 0x8 = Fehler.'
				$(if ($TaskUser -eq 'SYSTEM') { '# Laeuft als SYSTEM: Netzwerkfreigaben werden mit dem Computerkonto (DOMAENE\RECHNER$) angesprochen.' }
					else { "# Laeuft als $TaskUser - nur solange der Benutzer angemeldet ist." })
				''
				"`$taskName  = $(& $q $TaskName)"
				"`$taskPath  = $(& $q $TaskPath)"
				"`$arguments = $(& $q (Join-srgCmdLine $args_))"
				''
				'if (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue) {'
				'    throw "Aufgabe $taskPath$taskName existiert bereits - sie wird nicht ueberschrieben."'
				'}'
				'$action    = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\Robocopy.exe" -Argument $arguments'
				$(if ($trigger) { "`$trigger   = $trigger" })
				"`$principal = $principal"
				'$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 72)'
				$(if ($trigger) {
						"Register-ScheduledTask -TaskName `$taskName -TaskPath `$taskPath -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description $(& $q $desc) | Out-Null"
					} else {
						"Register-ScheduledTask -TaskName `$taskName -TaskPath `$taskPath -Action `$action -Principal `$principal -Settings `$settings -Description $(& $q $desc) | Out-Null"
					})
				'Write-Host "Aufgabe $taskPath$taskName angelegt."'
			)
			return (@($lines | Where-Object { $null -ne $_ }) -join "`r`n")
		}
	}
}
