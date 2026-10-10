function ConvertFrom-sqmRobocopyCommand {
	<#
	.SYNOPSIS
		Zerlegt eine vorhandene robocopy-Befehlszeile oder Auftragsdatei (.RCJ) in den Parameter-Hashtable.
	.DESCRIPTION
		Das Ergebnis passt direkt zu New-sqmRobocopyCommand, Test-sqmRobocopyParameter und der GUI
		(Schaltflaeche "Befehl importieren"). Unbekannte Optionen werden als Warnung gemeldet und
		uebersprungen. Ein vorangestelltes "robocopy" / "robocopy.exe" und Zeilenfortsetzungen
		(^ in cmd, ` in PowerShell) werden ignoriert.
	.EXAMPLE
		ConvertFrom-sqmRobocopyCommand 'robocopy "D:\Daten\" \\nas\backup *.docx /MIR /R:3 /W:5 /XD "~tmp" /LOG:C:\Logs\daten.log'
	.EXAMPLE
		ConvertFrom-sqmRobocopyCommand -JobFile C:\Jobs\Nacht.RCJ
	#>
	[CmdletBinding(DefaultParameterSetName = 'Line')]
	param(
		[Parameter(Mandatory, Position = 0, ParameterSetName = 'Line')][string]$CommandLine,
		[Parameter(Mandatory, ParameterSetName = 'Job')][string]$JobFile
	)
	$lookup = Get-srgParameterLookup
	$result = @{}
	$files = New-Object System.Collections.Generic.List[string]

	$setOption = {
		param([string]$Token)
		$t = $Token.TrimStart('/', '-')
		$name = $t; $value = $null
		$i = $t.IndexOf(':')
		if ($i -gt 0) { $name = $t.Substring(0, $i); $value = $t.Substring($i + 1).Trim('"') }
		$name = $name -replace '\[.*$', ''      # "/SPARSE[:J/N]" in RCJ-Dateien
		if ($name -eq 'IF') { return 'IF' }
		$def = $lookup[$name]
		if (-not $def) { Write-Warning "Unbekannte Option '$Token' uebersprungen."; return $null }
		$name = $def.Name
		switch ($def.Type) {
			'Switch' { $result[$name] = $true }
			'List' { if (-not $result.ContainsKey($name)) { $result[$name] = @() }; return $name }
			'Opt' { $result[$name] = if ($null -ne $value -and $value -ne '') { $value } else { $true } }
			'Hours' {
				# robocopy speichert in .RCJ "100-500" statt "0100-0500"
				if ($value -match '^(\d{1,4})-(\d{1,4})$') { $value = '{0:0000}-{1:0000}' -f [int]$Matches[1], [int]$Matches[2] }
				$result[$name] = $value
			}
			default { $result[$name] = $value }
		}
		$null
	}

	if ($PSCmdlet.ParameterSetName -eq 'Job') {
		# Format: TAB/OPTION<TAB>:: Kommentar, Listeneintraege mit zwei TABs eingerueckt
		$listName = $null
		$path = (Resolve-Path -LiteralPath $JobFile).ProviderPath
		foreach ($raw in (Read-srgJobFileLines $path)) {
			$line = ($raw -split '\t::', 2)[0]
			if ($line.TrimStart().StartsWith('::') -or -not $line.Trim()) { continue }
			if ($line -match '^\t/\S') {
				# Werte mit Leerzeichen (Pfade) stehen ungequotet bis zum Kommentar
				$full = $line.Trim()
				if ($full -match '^/(SD|DD):(.*)$') {
					$result[$(if ($Matches[1] -eq 'SD') { 'Source' } else { 'Destination' })] = ConvertTo-srgDirectory $Matches[2].Trim()
					$listName = $null; continue
				}
				$listName = & $setOption $full
			} elseif ($line -match '^\t\t(.+)$' -and $listName) {
				$item = $Matches[1].Trim()
				if ($listName -eq 'IF') { $files.Add($item) } else { $result[$listName] += $item }
			}
		}
	} else {
		$text = $CommandLine -replace '\s*[\^`]\s*\r?\n\s*', ' ' -replace '\r?\n', ' '
		# Tokenizer im Stil von CommandLineToArgvW (Anfuehrungszeichen mitten im Token erlaubt)
		$tokens = New-Object System.Collections.Generic.List[string]
		$sb = New-Object System.Text.StringBuilder
		$inQ = $false; $any = $false
		# Hochkomma nur am Tokenanfang als PowerShell-Quote werten ('' = Hochkomma) - mitten im Token
		# bleibt es ein normales Zeichen (cmd: C:\O'Brien)
		$inS = $false
		$chars = $text.ToCharArray()
		for ($i = 0; $i -lt $chars.Length; $i++) {
			$ch = $chars[$i]
			if ($inS) {
				if ($ch -eq "'") {
					if ($i + 1 -lt $chars.Length -and $chars[$i + 1] -eq "'") { [void]$sb.Append("'"); $i++ } else { $inS = $false }
				} else { [void]$sb.Append($ch) }
				continue
			}
			if ($ch -eq "'" -and -not $inQ -and -not $any) { $inS = $true; $any = $true; continue }
			if ($ch -eq '"') { $inQ = -not $inQ; $any = $true; continue }
			if (-not $inQ -and [char]::IsWhiteSpace($ch)) {
				if ($any) { $tokens.Add($sb.ToString()); [void]$sb.Clear(); $any = $false }
				continue
			}
			[void]$sb.Append($ch); $any = $true
		}
		if ($any) { $tokens.Add($sb.ToString()) }
		# PowerShell-Aufruf: & robocopy.exe 'a' 'b'
		$tokens = @($tokens | Where-Object { $_ -ne '&' })
		if ($tokens.Count -and $tokens[0] -match '(^|\\)robocopy(\.exe)?$') { $tokens = @($tokens | Select-Object -Skip 1) }

		$positional = 0
		$listName = $null
		foreach ($t in $tokens) {
			if ($t -match '^/') {
				$listName = & $setOption $t
				continue
			}
			if ($listName) {
				if ($listName -eq 'IF') { $files.Add($t) } else { $result[$listName] += $t }
				continue
			}
			switch ($positional) {
				0 { $result['Source'] = ConvertTo-srgDirectory $t }
				1 { $result['Destination'] = ConvertTo-srgDirectory $t }
				default { $files.Add($t) }
			}
			$positional++
		}
	}

	# robocopy schreibt bei /E auch /S in die Auftragsdatei
	if ($result['E'] -and $result['S']) { [void]$result.Remove('S') }
	$files = @($files | Where-Object { $_ -ne '*.*' })
	if ($files.Count) { $result['Files'] = @($files) }
	$result
}
