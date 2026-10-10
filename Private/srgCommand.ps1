<#
	Bausteine fuer den robocopy-Aufruf: Normalisierung der Werte, Argumentliste, Quoting fuer
	cmd / Batch / PowerShell. Kein GUI-Code - wird von New-sqmRobocopyCommand und der GUI benutzt.
#>

function ConvertTo-srgBool($Value) {
	if ($Value -is [bool]) { return $Value }
	if ($null -eq $Value) { return $false }
	"$Value".Trim() -in 'Y', 'J', '1', 'true', '$true', 'on', 'x'
}

function ConvertTo-srgList($Value) {
	# Arrays bleiben Arrays; Zeichenketten werden an ; und Zeilenumbruechen getrennt
	$items = foreach ($v in @($Value)) {
		if ($null -eq $v) { continue }
		foreach ($s in ("$v" -split '[;\r\n]')) { $s.Trim().Trim('"') }
	}
	@($items | Where-Object { $_ })
}

function ConvertTo-srgDirectory([string]$Path) {
	<#
		Abschliessenden Backslash entfernen: "C:\Ziel\" wuerde sonst beim Quoten zu C:\Ziel" (der
		Backslash maskiert das Anfuehrungszeichen) - der klassische robocopy-Fehler "Ungueltiger
		Parameter". Laufwerkswurzeln (D:\) bleiben, sie brauchen nie Anfuehrungszeichen.
	#>
	$p = $Path.Trim().Trim('"')
	if ($p -match '^[A-Za-z]:\\*$') { return $p.Substring(0, 2) + '\' }
	$p.TrimEnd('\')
}

function Get-srgActiveParameter([hashtable]$Parameter) {
	<# Liefert die gesetzten Optionen normalisiert: Name -> $true | 'Wert' | string[] #>
	$out = [ordered]@{}
	foreach ($d in Get-srgParameterDefinition) {
		$key = @($Parameter.Keys | Where-Object { $_ -eq $d.Name })[0]
		if ($null -eq $key) { continue }
		$v = $Parameter[$key]
		switch ($d.Type) {
			'Switch' { if (ConvertTo-srgBool $v) { $out[$d.Name] = $true } }
			'Opt' {
				if ($v -is [bool]) { if ($v) { $out[$d.Name] = $true } }
				elseif ($null -ne $v -and "$v".Trim() -ne '') {
					$s = "$v".Trim()
					$out[$d.Name] = if ($s -in '*', '$true', 'true', 'on') { $true } else { $s.ToUpper() }
				}
			}
			'List' { $l = ConvertTo-srgList $v; if ($l.Count) { $out[$d.Name] = $l } }
			'Flags' { if ($null -ne $v -and "$v".Trim() -ne '') { $out[$d.Name] = "$v".Trim().ToUpper() } }
			'Size' { if ($null -ne $v -and "$v".Trim() -ne '') { $out[$d.Name] = "$v".Trim().ToUpper() } }
			default { if ($null -ne $v -and "$v".Trim() -ne '') { $out[$d.Name] = "$v".Trim() } }
		}
	}
	$out
}

function Get-srgArgumentList {
	<#
		Robocopy-Argumente ohne Quoting, in fester Reihenfolge: Quelle, Ziel, Dateien, Optionen.
		Optionen mit Wert als ein Token ('/LOG:C:\x y.log'); das Quoting erledigt Format-srg*Arg.
	#>
	param([hashtable]$Parameter, [string[]]$Extra = @())
	$list = New-Object System.Collections.Generic.List[string]
	$src = [string]$Parameter['Source']
	$dst = [string]$Parameter['Destination']
	if ($src.Trim()) { $list.Add((ConvertTo-srgDirectory $src)) }
	if ($dst.Trim()) { $list.Add((ConvertTo-srgDirectory $dst)) }
	foreach ($f in (ConvertTo-srgList $Parameter['Files'])) { $list.Add($f) }

	$opts = Get-srgActiveParameter $Parameter
	foreach ($name in $opts.Keys) {
		$v = $opts[$name]
		$d = (Get-srgParameterLookup)[$name]
		if ($v -is [bool]) { $list.Add("/$name"); continue }
		if ($d.Type -eq 'List') {
			$list.Add("/$name")
			foreach ($i in $v) { $list.Add($(if ($name -eq 'XD') { ConvertTo-srgDirectory $i } else { $i })) }
			continue
		}
		$list.Add("/${name}:$v")
	}
	foreach ($e in $Extra) { if ($e -and -not ($list -contains $e)) { $list.Add($e) } }
	, $list.ToArray()
}

function Format-srgCmdArg([string]$Token, [switch]$Batch) {
	<# Quoting fuer cmd.exe / CreateProcess: nur wenn noetig, bei /OPT:Wert nur den Wert. #>
	$prefix = ''
	$value = $Token
	if ($Token -match '^(/[A-Za-z0-9+]+:)(.+)$') { $prefix = $Matches[1]; $value = $Matches[2] }
	if ($value -eq '' -or $value -match '[\s&()\[\]{}^=;!'',`|<>"]') {
		# abschliessende Backslashes vor dem schliessenden Anfuehrungszeichen verdoppeln
		$m = [regex]::Match($value, '\\+$')
		if ($m.Success) { $value = $value + $m.Value }
		$value = '"' + $value.Replace('"', '\"') + '"'
	}
	$r = $prefix + $value
	if ($Batch) { $r = $r.Replace('%', '%%') }
	$r
}

function Format-srgPsArg([string]$Token) {
	"'" + $Token.Replace("'", "''") + "'"
}

function Join-srgCmdLine([string[]]$Arguments, [switch]$Batch) {
	(@($Arguments | ForEach-Object { Format-srgCmdArg $_ -Batch:$Batch })) -join ' '
}

function Get-srgExitCodeText([int]$ExitCode) {
	if ($ExitCode -eq 0) { return 'nichts zu tun - Quelle und Ziel sind bereits synchron' }
	if ($ExitCode -lt 0) { return 'robocopy wurde abgebrochen' }
	$parts = foreach ($b in $script:srgExitBits) { if ($ExitCode -band $b.Bit) { $b.Text } }
	$parts -join ', '
}

function Read-srgJobFileLines([string]$Path) {
	<#
		robocopy schreibt .RCJ-Dateien je nach Umgebung in der Konsolen-Codepage (OEM 850, nach
		chcp 65001 UTF-8) oder in der ANSI-Codepage (1252) - ohne Kennung. Mit BOM (/UNICODE) ist es
		eindeutig, sonst gewinnt die Dekodierung, deren Quell-/Zielpfade tatsaechlich existieren.
	#>
	$bytes = [System.IO.File]::ReadAllBytes($Path)
	if (($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or
		($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
		return [System.IO.File]::ReadAllLines($Path)
	}
	$ti = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo
	$candidates = New-Object System.Collections.Generic.List[string]
	try { $candidates.Add((New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)) } catch { }
	foreach ($cp in $ti.OEMCodePage, $ti.ANSICodePage) {
		try { $candidates.Add([System.Text.Encoding]::GetEncoding($cp).GetString($bytes)) } catch { }
	}
	Initialize-srgHelper
	$pick = $candidates[0]
	if (@($candidates | Select-Object -Unique).Count -gt 1) {
		:outer foreach ($text in $candidates) {
			foreach ($m in [regex]::Matches($text, '(?m)^\t/(?:SD|DD):([^\t\r\n]+)')) {
				$d = $m.Groups[1].Value.Trim()
				if ($d -and [Srg.PathProbe]::DirectoryExists($d, 1500) -eq 1) { $pick = $text; break outer }
			}
		}
	}
	$pick -split '\r?\n'
}
