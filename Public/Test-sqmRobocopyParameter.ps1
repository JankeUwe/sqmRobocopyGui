function Test-sqmRobocopyParameter {
	<#
	.SYNOPSIS
		Prueft robocopy-Parameter offline auf Fehler und riskante Kombinationen.
	.DESCRIPTION
		Liefert je Befund ein Objekt mit Severity (Error | Warning), Parameter und Message. Fehler
		fuehren bei robocopy zu "Ungueltiger Parameter" (Exitcode 16) oder sind widerspruechlich;
		Warnungen markieren Optionen, die Daten loeschen, ewig laufen oder Adminrechte brauchen.
		Mit -CheckPath werden Quelle und Ziel zusaetzlich im Dateisystem geprueft.
	.EXAMPLE
		Test-sqmRobocopyParameter -Parameter @{ Source = 'D:\A'; Destination = 'D:\A\Kopie'; MIR = $true }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][hashtable]$Parameter,
		[switch]$CheckPath
	)
	$issues = New-Object System.Collections.Generic.List[object]
	$add = { param($sev, $par, $msg) $issues.Add([pscustomobject]@{ Severity = $sev; Parameter = $par; Message = $msg }) }
	$lookup = Get-srgParameterLookup

	foreach ($k in $Parameter.Keys) {
		if ($k -notin 'Source', 'Destination', 'Files' -and -not $lookup.ContainsKey($k)) { & $add 'Error' $k "Unbekannte robocopy-Option /$k." }
	}
	$o = Get-srgActiveParameter $Parameter
	$has = { param($n) $o.Contains($n) }

	# --- Quelle / Ziel ----------------------------------------------------------------------------
	$src = ([string]$Parameter['Source']).Trim().Trim('"')
	$dst = ([string]$Parameter['Destination']).Trim().Trim('"')
	if (-not $src -and -not (& $has 'NOSD')) { & $add 'Error' 'Source' 'Quelle fehlt.' }
	if (-not $dst -and -not (& $has 'NODD')) { & $add 'Error' 'Destination' 'Ziel fehlt.' }
	foreach ($pair in @(@('Source', $src), @('Destination', $dst))) {
		if ($pair[1] -and $pair[1] -match '[*?<>|]') { & $add 'Error' $pair[0] "Verzeichnis darf keine Platzhalter enthalten - Dateimuster gehoeren in 'Dateien'." }
		elseif ($pair[1] -and $pair[1] -notmatch '^([A-Za-z]:|\\\\[^\\]+\\[^\\]+)' -and $pair[1] -notmatch '^\.') {
			& $add 'Warning' $pair[0] 'Relativer Pfad - er wird zum aktuellen Verzeichnis von robocopy aufgeloest. Besser absolut (D:\... oder \\Server\Freigabe\...).'
		}
	}
	if ($src -and $dst) {
		$s = (ConvertTo-srgDirectory $src).TrimEnd('\').ToLowerInvariant()
		$d = (ConvertTo-srgDirectory $dst).TrimEnd('\').ToLowerInvariant()
		$recursive = (& $has 'S') -or (& $has 'E') -or (& $has 'MIR') -or (& $has 'MOVE')
		if ($s -eq $d) { & $add 'Error' 'Destination' 'Quelle und Ziel sind identisch.' }
		elseif ($recursive -and $d.StartsWith($s + '\')) {
			& $add 'Warning' 'Destination' 'Das Ziel liegt innerhalb der Quelle - mit Unterverzeichnissen kopiert robocopy dann in sich selbst hinein. Ziel ausserhalb waehlen oder per /XD ausschliessen.'
		} elseif (((& $has 'MIR') -or (& $has 'PURGE')) -and $s.StartsWith($d + '\')) {
			& $add 'Error' 'Destination' 'Die Quelle liegt innerhalb des Ziels - /MIR bzw. /PURGE wuerde im Ziel alles ausser der Quelle loeschen.'
		}
	}
	if ($CheckPath) {
		if ($src -and -not (& $has 'NOSD') -and -not (Test-Path -LiteralPath $src -PathType Container -ErrorAction SilentlyContinue)) {
			& $add 'Error' 'Source' "Quelle '$src' ist nicht erreichbar oder kein Verzeichnis."
		}
		if ($dst -and -not (& $has 'NODD')) {
			$root = [System.IO.Path]::GetPathRoot($dst)
			if ($root -and -not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { & $add 'Error' 'Destination' "Ziellaufwerk/-freigabe '$root' ist nicht erreichbar." }
		}
	}
	foreach ($f in (ConvertTo-srgList $Parameter['Files'])) {
		if ($f -match '[\\/]') { & $add 'Warning' 'Files' "Dateimuster '$f' enthaelt einen Pfad - robocopy erwartet hier nur Namen oder Platzhalter." }
	}

	# --- Exklusive Gruppen -----------------------------------------------------------------------
	foreach ($grp in ($script:srgParameters | Where-Object { $_.Exclusive } | Group-Object { $_.Exclusive })) {
		$set = @($grp.Group | Where-Object { & $has $_.Name } | ForEach-Object { '/' + $_.Name })
		if ($set.Count -gt 1) { & $add 'Error' ($set[0].TrimStart('/')) "Schliessen sich gegenseitig aus: $($set -join ', ')." }
	}

	# --- Werte ------------------------------------------------------------------------------------
	foreach ($name in $o.Keys) {
		$d = $lookup[$name]
		$v = $o[$name]
		if ($v -is [bool]) { continue }
		$kind = if ($d.Type -eq 'Opt') { $d.ValueKind } else { $d.Type }
		switch ($kind) {
			'Int' {
				$n = 0
				if (-not [int]::TryParse($v, [ref]$n)) { & $add 'Error' $name "/$name erwartet eine ganze Zahl."; break }
				if ($null -ne $d.Min -and ($n -lt $d.Min -or $n -gt $d.Max)) { & $add 'Error' $name "/$name muss zwischen $($d.Min) und $($d.Max) liegen." }
			}
			'Bytes' { if ($v -notmatch '^\d+$') { & $add 'Error' $name "/$name erwartet eine Zahl in Bytes (robocopy kennt hier kein K/M/G - z.B. 1048576 fuer 1 MB)." } }
			'Size' { if ($v -notmatch '^\d+[KMG]?$') { & $add 'Error' $name "/$name erwartet n oder n mit K, M oder G (z.B. 50M)." } }
			'Enum' { if ($v -notin $d.Values) { & $add 'Error' $name "/$name erlaubt nur $($d.Values -join ' oder ')." } }
			'Flags' {
				$bad = @($v.ToCharArray() | Where-Object { $d.Letters.IndexOf([string]$_) -lt 0 } | Select-Object -Unique)
				if ($bad.Count) { & $add 'Error' $name "/$name erlaubt nur die Buchstaben $($d.Letters) (ungueltig: $($bad -join ''))." }
			}
			'Age' {
				if ($v -notmatch '^\d+$') { & $add 'Error' $name "/$name erwartet Tage (< 1900) oder ein Datum JJJJMMTT."; break }
				if ([long]$v -ge 1900) {
					$dt = [datetime]::MinValue
					if (-not [datetime]::TryParseExact($v, 'yyyyMMdd', [cultureinfo]::InvariantCulture, 'None', [ref]$dt)) {
						& $add 'Error' $name "/${name}:$v ist kein gueltiges Datum JJJJMMTT (Werte ab 1900 gelten als Datum)."
					}
				}
			}
			'Hours' {
				if ($v -notmatch '^(\d{4})-(\d{4})$' -or [int]$Matches[1].Substring(2) -gt 59 -or [int]$Matches[2].Substring(2) -gt 59 -or [int]$Matches[1] -gt 2400 -or [int]$Matches[2] -gt 2400) {
					& $add 'Error' $name '/RH erwartet hhmm-hhmm (z.B. 2200-0600).'
				} elseif ($Matches[1] -eq $Matches[2]) { & $add 'Error' $name '/RH: Start und Ende sind gleich.' }
			}
			'Path' { if ($v -match '[*?<>|]') { & $add 'Error' $name "/$name enthaelt unzulaessige Zeichen." } }
		}
	}
	if ((& $has 'MIN') -and (& $has 'MAX') -and $o['MIN'] -match '^\d+$' -and $o['MAX'] -match '^\d+$' -and [long]$o['MIN'] -gt [long]$o['MAX']) {
		& $add 'Error' 'MIN' '/MIN ist groesser als /MAX - es wuerde keine Datei kopiert.'
	}

	# --- Kombinationen ---------------------------------------------------------------------------
	if (& $has 'MT') {
		if (& $has 'IPG') { & $add 'Error' 'IPG' '/IPG ist nicht mit /MT kombinierbar (robocopy ignoriert dann eine der Optionen).' }
		if (& $has 'EFSRAW') { & $add 'Error' 'EFSRAW' '/EFSRAW ist nicht mit /MT kombinierbar.' }
	}
	if ((& $has 'NOCOPY') -and -not (& $has 'PURGE') -and -not (& $has 'MIR')) {
		& $add 'Warning' 'NOCOPY' '/NOCOPY ohne /PURGE bzw. /MIR kopiert nichts.'
	}
	if ((& $has 'PURGE') -and (& $has 'MIR')) { & $add 'Warning' 'PURGE' '/PURGE ist in /MIR bereits enthalten.' }
	if ((& $has 'PURGE') -and -not ((& $has 'E') -or (& $has 'S') -or (& $has 'MIR'))) {
		& $add 'Warning' 'PURGE' '/PURGE ohne /E loescht nur im obersten Zielverzeichnis.'
	}
	if ((& $has 'XN') -and (& $has 'XO')) { & $add 'Warning' 'XO' '/XN und /XO zusammen: es werden nur Dateien kopiert, die im Ziel fehlen.' }
	if ((& $has 'XX') -and -not ((& $has 'MIR') -or (& $has 'PURGE'))) { & $add 'Warning' 'XX' '/XX wirkt nur zusammen mit /MIR oder /PURGE.' }
	if ((& $has 'TEE') -and -not ((& $has 'LOG') -or (& $has 'LOG+') -or (& $has 'UNILOG') -or (& $has 'UNILOG+'))) {
		& $add 'Warning' 'TEE' '/TEE ohne Protokolldatei hat keine Wirkung.'
	}
	if ((& $has 'PF') -and -not (& $has 'RH')) { & $add 'Warning' 'PF' '/PF wirkt nur zusammen mit /RH.' }
	if (((& $has 'Threshold')) -and -not ((& $has 'IoRate') -or (& $has 'IoMaxSize'))) { & $add 'Warning' 'Threshold' '/Threshold wirkt nur zusammen mit /IoRate oder /IoMaxSize.' }
	if (((& $has 'LOG') -or (& $has 'LOG+') -or (& $has 'UNILOG') -or (& $has 'UNILOG+')) -and -not (& $has 'NP')) {
		& $add 'Warning' 'NP' 'Protokolldatei ohne /NP: jede Prozentanzeige landet in der Datei. /NP setzen.'
	}
	if ((& $has 'SAVE') -and (& $has 'MT')) { & $add 'Warning' 'SAVE' 'robocopy speichert /MT nicht in der Auftragsdatei.' }
	if ((& $has 'JOB') -and -not (& $has 'NOSD') -and -not $src) { & $add 'Warning' 'NOSD' 'Kommt die Quelle aus der Auftragsdatei, /NOSD setzen.' }

	# --- Riskantes -------------------------------------------------------------------------------
	if (-not (& $has 'L')) {
		if (& $has 'MIR') { & $add 'Warning' 'MIR' '/MIR loescht im Ziel alles, was in der Quelle fehlt. Erst einen Trockenlauf (/L) machen.' }
		if (& $has 'PURGE') { & $add 'Warning' 'PURGE' '/PURGE loescht im Ziel alles, was in der Quelle fehlt.' }
		if (& $has 'MOV') { & $add 'Warning' 'MOV' '/MOV loescht die Dateien nach dem Kopieren in der Quelle.' }
		if (& $has 'MOVE') { & $add 'Warning' 'MOVE' '/MOVE loescht Dateien und Verzeichnisse nach dem Kopieren in der Quelle.' }
		if (((& $has 'MIR') -or (& $has 'PURGE')) -and $dst -match '^([A-Za-z]:|\\\\[^\\]+\\[^\\]+)\\?$') {
			& $add 'Warning' 'Destination' 'Das Ziel ist eine Laufwerks- bzw. Freigabewurzel - /MIR oder /PURGE raeumt dort ALLES ab, was nicht in der Quelle liegt.'
		}
	}
	if (-not (& $has 'R')) { & $add 'Warning' 'R' 'Ohne /R wiederholt robocopy eine gesperrte Datei 1 Million Mal (je 30 s) - typischerweise /R:3 /W:5 setzen.' }
	if ((& $has 'MON') -or (& $has 'MOT')) { & $add 'Warning' ($(if (& $has 'MON') { 'MON' } else { 'MOT' })) 'Mit /MON bzw. /MOT laeuft robocopy dauerhaft weiter und endet nicht von selbst.' }
	if (& $has 'REG') { & $add 'Warning' 'REG' '/REG aendert die robocopy-Standardwerte in der Registrierung fuer alle kuenftigen Aufrufe.' }
	$admin = @($o.Keys | Where-Object { $lookup[$_].Admin })
	if ((& $has 'COPY') -and $o['COPY'] -match '[OU]') { $admin += 'COPY' }
	if ($admin.Count) { & $add 'Warning' $admin[0] "$((@($admin) | ForEach-Object { '/' + $_ }) -join ', ') braucht Administrator- bzw. Sicherungsrechte." }

	$issues.ToArray()
}
