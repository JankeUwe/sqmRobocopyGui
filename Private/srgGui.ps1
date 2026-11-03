<#
	WinForms-Aufbau und Logik der GUI. Alle Handler greifen ueber $script:srgUi auf die
	Controls zu (Modul-Scope), nicht ueber Variablen der aufrufenden Funktion - so laufen
	sie auch nach Show-sqmRobocopyGui -PassThru noch korrekt.
#>

# ===========================================================================================
# Konfiguration (zuletzt benutzte Quellen / Ziele)
# ===========================================================================================
function Read-srgConfig {
	$cfg = [pscustomobject]@{ Sources = @(); Destinations = @() }
	try {
		if (Test-Path $script:srgConfigPath) {
			$j = Get-Content $script:srgConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
			$cfg.Sources = @($j.Sources | Where-Object { $_ })
			$cfg.Destinations = @($j.Destinations | Where-Object { $_ })
		}
	} catch { }
	$cfg
}

function Save-srgConfig {
	param([string]$Source, [string]$Destination)
	try {
		$cfg = Read-srgConfig
		$merge = { param($new, $old) @(@($new) + @($old | Where-Object { $_ -and $_ -ne $new }) | Where-Object { $_ } | Select-Object -First 15) }
		$dir = Split-Path $script:srgConfigPath
		if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
		[pscustomobject]@{ Sources = (& $merge $Source $cfg.Sources); Destinations = (& $merge $Destination $cfg.Destinations) } |
			ConvertTo-Json | Set-Content -Path $script:srgConfigPath -Encoding UTF8
	} catch { }
}

# ===========================================================================================
# Vorlagen
# ===========================================================================================
function Get-srgPreset {
	[ordered]@{
		'Ordner kopieren (mit Unterordnern)'          = @{ E = $true; DCOPY = 'DAT'; MT = $true; R = '3'; W = '5' }
		'Spiegeln /MIR (Ziel = Abbild der Quelle)'    = @{ MIR = $true; DCOPY = 'DAT'; MT = $true; R = '3'; W = '5'; XJ = $true }
		'Nur Neues ergaenzen (nichts ueberschreiben)' = @{ E = $true; XO = $true; XC = $true; XN = $true; R = '3'; W = '5' }
		'Verschieben (Dateien und Ordner)'            = @{ MOVE = $true; E = $true; R = '3'; W = '5' }
		'Server-Migration mit Rechten (Admin)'        = @{ MIR = $true; COPYALL = $true; DCOPY = 'DAT'; ZB = $true; MT = '32'; XJ = $true; R = '1'; W = '1'; NP = $true }
		'NAS / Linux-Freigabe'                        = @{ E = $true; FFT = $true; DST = $true; Z = $true; XJ = $true; R = '3'; W = '10' }
		'Grosse Dateien (VHDX, ISO, Backups)'         = @{ E = $true; J = $true; R = '3'; W = '10' }
		'SQL-Backups verteilen (*.bak, *.trn)'        = @{ Files = @('*.bak', '*.trn'); S = $true; J = $true; XO = $true; R = '3'; W = '10' }
		'Langsame WAN-Leitung'                        = @{ E = $true; Z = $true; COMPRESS = $true; MT = '4'; R = '10'; W = '30' }
		'Nur Ordnerstruktur (ohne Dateien)'           = @{ E = $true; XF = @('*'); R = '1'; W = '1' }
		'Trockenlauf: nur auflisten'                  = @{ E = $true; L = $true; R = '1'; W = '1' }
	}
}

# ===========================================================================================
# Formular-Bausteine
# ===========================================================================================
function New-srgLabel([string]$Text) {
	$l = New-Object System.Windows.Forms.Label
	$l.Text = $Text
	$l.AutoSize = $true
	$l.Anchor = 'Left'
	$l.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
	$l
}

function New-srgButton([string]$Text, [int]$Width = 110) {
	$b = New-Object System.Windows.Forms.Button
	$b.Text = $Text
	$b.Width = $Width
	$b.Height = 27
	$b
}

function Set-srgCueBanner {
	param($TextBox, [string]$Text)
	if (-not $Text -or -not $TextBox -or -not $TextBox.IsHandleCreated) { return }
	Initialize-srgNative
	$h = $TextBox.Handle
	# ComboBox: Cue-Banner gehoert an das innere Edit-Feld (CB_SETCUEBANNER = 0x1703)
	$msg = if ($TextBox -is [System.Windows.Forms.ComboBox]) { 0x1703 } else { 0x1501 }
	[void][Srg.Native]::SendMessage($h, $msg, [System.IntPtr]1, $Text)
}

function Get-srgShortHelp([string]$Text) {
	# erster Satz als Kurzhilfe in der Zeile
	$i = $Text.IndexOf('. ')
	if ($i -gt 0) { return $Text.Substring(0, $i + 1) }
	$Text
}

function New-srgField {
	<# Baut eine Tabellenzeile fuer eine robocopy-Option: Name | Eingabe + Kurzhilfe #>
	param($Def, $Table, $Tip)
	$ui = $script:srgUi
	$f = @{ Def = $Def; Check = $null; Text = $null; Letters = $null; Button = $null }
	$row = $Table.RowCount
	$Table.RowCount++
	[void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
	$tipText = $Def.Help
	if ($null -ne $Def.Default) { $tipText += "`r`nStandard: $($Def.Default)" }

	$help = New-Object System.Windows.Forms.Label
	$help.Text = Get-srgShortHelp $Def.Help
	$help.AutoSize = $false
	$help.AutoEllipsis = $true
	$help.Dock = 'Fill'
	$help.TextAlign = 'MiddleLeft'
	$help.ForeColor = [System.Drawing.Color]::DimGray
	$help.Margin = New-Object System.Windows.Forms.Padding(8, 0, 3, 0)
	$help.Height = 26
	$help.Tag = $Def.Name

	$isCheck = $Def.Type -in 'Switch', 'Opt'
	if ($isCheck) {
		$cb = New-Object System.Windows.Forms.CheckBox
		$cb.Text = '/' + $Def.Name
		$cb.AutoSize = $true
		$cb.Anchor = 'Left'
		$cb.Margin = New-Object System.Windows.Forms.Padding(3, 4, 3, 2)
		$cb.Tag = $Def.Name
		$cb.Add_CheckedChanged({ Invoke-srgFieldChanged $this.Tag })
		$cb.Add_Enter({ Show-srgHelp $this.Tag })
		$f.Check = $cb
		$f.Label = $cb
		$Table.Controls.Add($cb, 0, $row)
	} else {
		$lbl = New-Object System.Windows.Forms.Label
		$lbl.Text = '/' + $Def.Name
		$lbl.AutoSize = $true
		$lbl.Anchor = 'Left'
		$lbl.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
		$lbl.Tag = $Def.Name
		$lbl.Add_Click({ Show-srgHelp $this.Tag; Select-srgField $this.Tag })
		$f.Label = $lbl
		$Table.Controls.Add($lbl, 0, $row)
	}
	$Tip.SetToolTip($f.Label, $tipText)

	$ctl = $null
	switch ($Def.Type) {
		'Switch' { }
		'Flags' {
			$fl = New-Object System.Windows.Forms.FlowLayoutPanel
			$fl.AutoSize = $true; $fl.WrapContents = $false; $fl.Anchor = 'Left'
			$fl.Margin = New-Object System.Windows.Forms.Padding(0)
			$f.Letters = [ordered]@{}
			foreach ($ch in $Def.Letters.ToCharArray()) {
				$lc = New-Object System.Windows.Forms.CheckBox
				$lc.Text = [string]$ch; $lc.AutoSize = $true; $lc.Tag = $Def.Name
				$lc.Margin = New-Object System.Windows.Forms.Padding(2, 4, 4, 2)
				$lc.Add_CheckedChanged({ Invoke-srgFieldChanged $this.Tag })
				$lc.Add_Enter({ Show-srgHelp $this.Tag })
				$Tip.SetToolTip($lc, (Get-srgLetterHelp $Def.Name ([string]$ch)))
				$f.Letters[[string]$ch] = $lc
				$fl.Controls.Add($lc)
			}
			$ctl = $fl
		}
		'Opt' {
			if ($Def.ValueKind -eq 'Enum') {
				$c = New-Object System.Windows.Forms.ComboBox
				$c.DropDownStyle = 'DropDownList'; $c.Width = 120
				[void]$c.Items.Add("(Standard $($Def.Default))")
				foreach ($v in $Def.Values) { [void]$c.Items.Add($v) }
				$c.SelectedIndex = 0
				$c.Add_SelectedIndexChanged({ Invoke-srgFieldChanged $this.Tag })
			} else {
				$c = New-Object System.Windows.Forms.TextBox
				$c.Width = 120
				$c.Add_TextChanged({ Invoke-srgFieldChanged $this.Tag })
			}
			$c.Anchor = 'Left'
			$c.Enabled = $false
			$f.Text = $c
			$ctl = $c
		}
		default {
			$t = New-Object System.Windows.Forms.TextBox
			$t.Add_TextChanged({ Invoke-srgFieldChanged $this.Tag })
			if ($Def.Type -in 'List', 'Path') {
				$pnl = New-Object System.Windows.Forms.TableLayoutPanel
				$pnl.ColumnCount = 2; $pnl.RowCount = 1; $pnl.Width = 330; $pnl.Height = 30; $pnl.Anchor = 'Left'
				$pnl.Margin = New-Object System.Windows.Forms.Padding(0)
				[void]$pnl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
				[void]$pnl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 34)))
				$t.Dock = 'Fill'
				$b = New-srgButton '...' 30
				$b.Height = 24; $b.Tag = $Def.Name
				$b.Margin = New-Object System.Windows.Forms.Padding(2, 2, 0, 2)
				$b.Add_Click({ Show-srgFieldPicker $this.Tag })
				$Tip.SetToolTip($b, $(switch ($Def.Picker) { 'Files' { 'Dateien auswaehlen und anhaengen' } 'Folders' { 'Verzeichnisse auswaehlen und anhaengen (Mehrfachauswahl)' } default { 'Datei auswaehlen' } }))
				$pnl.Controls.Add($t, 0, 0); $pnl.Controls.Add($b, 1, 0)
				$f.Button = $b
				$ctl = $pnl
			} else {
				$t.Width = 140; $t.Anchor = 'Left'
				$ctl = $t
			}
			$f.Text = $t
		}
	}
	if ($f.Text) {
		$f.Text.Tag = $Def.Name
		$f.Text.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 3)
		$f.Text.Add_Enter({ Show-srgHelp $this.Tag })
		$Tip.SetToolTip($f.Text, $tipText)
	}
	if ($ctl) {
		# Eingabe und Kurzhilfe in einer eigenen Zeile, damit die Hilfe direkt hinter dem Feld beginnt
		$rowPanel = New-Object System.Windows.Forms.TableLayoutPanel
		$rowPanel.ColumnCount = 2; $rowPanel.RowCount = 1
		$rowPanel.Dock = 'Fill'; $rowPanel.AutoSize = $true
		$rowPanel.Margin = New-Object System.Windows.Forms.Padding(0)
		[void]$rowPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
		[void]$rowPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
		$rowPanel.Controls.Add($ctl, 0, 0)
		$rowPanel.Controls.Add($help, 1, 0)
		$Table.Controls.Add($rowPanel, 1, $row)
	} else {
		$Table.Controls.Add($help, 1, $row)
	}
	$Tip.SetToolTip($help, $tipText)
	$help.Add_Click({ Show-srgHelp $this.Tag; Select-srgField $this.Tag })
	$f.Help = $help
	$ui.Fields[$Def.Name] = $f
}

function Get-srgLetterHelp([string]$Name, [string]$Letter) {
	$m = if ($Name -eq 'COPY') {
		@{ D = 'Daten'; A = 'Attribute'; T = 'Zeitstempel'; S = 'Sicherheit (NTFS-ACLs)'; O = 'Besitzer'; U = 'Ueberwachung (Auditing)'; X = 'alternative Datenstroeme ueberspringen' }
	} elseif ($Name -eq 'DCOPY') {
		@{ D = 'Daten'; A = 'Attribute'; T = 'Zeitstempel'; E = 'erweiterte Attribute (EAs)'; X = 'alternative Datenstroeme ueberspringen' }
	} else {
		@{ R = 'Schreibgeschuetzt'; A = 'Archiv'; S = 'System'; H = 'Versteckt'; C = 'Komprimiert'; N = 'Nicht indiziert'; E = 'Verschluesselt'; T = 'Temporaer'; O = 'Offline' }
	}
	"$Letter = $($m[$Letter])"
}

# ===========================================================================================
# Formularaufbau
# ===========================================================================================
function New-srgMainForm {
	Initialize-srgHelper
	# Confirm = $false nur fuer automatisierte Tests (keine Rueckfrage vor dem Lauf)
	$ui = @{ Loading = $true; Fields = [ordered]@{}; Runner = $null; Confirm = $true }
	$script:srgUi = $ui
	$tip = New-Object System.Windows.Forms.ToolTip
	$tip.AutoPopDelay = 20000
	$tip.InitialDelay = 400
	$ui.Tip = $tip
	$ui.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

	$form = New-Object System.Windows.Forms.Form
	$form.Text = "sqmRobocopyGui $script:srgModuleVersion - robocopy zusammenklicken und ausfuehren" + $(if ($ui.IsAdmin) { '  [Administrator]' } else { '' })
	$form.Size = New-Object System.Drawing.Size(1440, 940)
	$form.MinimumSize = New-Object System.Drawing.Size(1150, 720)
	$form.StartPosition = 'CenterScreen'
	$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
	$form.KeyPreview = $true
	$ui.Form = $form

	$root = New-Object System.Windows.Forms.TableLayoutPanel
	$root.Dock = 'Fill'
	$root.ColumnCount = 1
	$root.RowCount = 3
	$root.Padding = New-Object System.Windows.Forms.Padding(6)
	[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 128)))
	[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 42)))
	[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

	# --- Quelle / Ziel / Dateien ------------------------------------------------------------
	$gPath = New-Object System.Windows.Forms.GroupBox
	$gPath.Text = 'Quelle und Ziel  (Ordner auch per Drag && Drop aus dem Explorer)'
	$gPath.Dock = 'Fill'
	$tPath = New-Object System.Windows.Forms.TableLayoutPanel
	$tPath.Dock = 'Fill'; $tPath.ColumnCount = 6; $tPath.RowCount = 3
	foreach ($cs in @(@('Absolute', 70), @('Percent', 100), @('Absolute', 96), @('Absolute', 84), @('Absolute', 96), @('Absolute', 230))) {
		[void]$tPath.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle($cs[0], $cs[1])))
	}
	foreach ($i in 0..2) { [void]$tPath.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 32))) }

	foreach ($k in 'Source', 'Destination') {
		$r = if ($k -eq 'Source') { 0 } else { 1 }
		$lbl = New-srgLabel $(if ($k -eq 'Source') { 'Quelle:' } else { 'Ziel:' })
		$cmb = New-Object System.Windows.Forms.ComboBox
		$cmb.Dock = 'Fill'; $cmb.Tag = $k; $cmb.AllowDrop = $true
		$cmb.Margin = New-Object System.Windows.Forms.Padding(3, 4, 3, 3)
		$cmb.Font = New-Object System.Drawing.Font('Consolas', 10)
		$cmb.Add_TextChanged({ Update-srgOutput; Start-srgPathCheck })
		$cmb.Add_Leave({ Update-srgPathState $this.Tag })
		$cmb.Add_SelectedIndexChanged({ Update-srgPathState $this.Tag })
		$cmb.Add_DragEnter({ param($s, $e) Invoke-srgDragEnter $e })
		$cmb.Add_DragDrop({ param($s, $e) Invoke-srgDrop $s.Tag $e })
		$bPick = New-srgButton 'Ordner...' 90; $bPick.Tag = $k
		$bPick.Add_Click({ Show-srgDirPicker $this.Tag })
		$bOpen = New-srgButton 'Oeffnen' 78; $bOpen.Tag = $k
		$bOpen.Add_Click({ Open-srgExplorer $this.Tag })
		$tip.SetToolTip($bOpen, 'Im Explorer oeffnen')
		$state = New-srgLabel ''
		$state.AutoEllipsis = $true
		foreach ($c in $bPick, $bOpen) { $c.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 2) }
		$tPath.Controls.Add($lbl, 0, $r); $tPath.Controls.Add($cmb, 1, $r)
		$tPath.Controls.Add($bPick, 2, $r); $tPath.Controls.Add($bOpen, 3, $r)
		$tPath.Controls.Add($state, 5, $r)
		$ui[$k] = $cmb
		$ui["${k}State"] = $state
	}
	$ui.Swap = New-srgButton 'Tauschen' 90
	$ui.Swap.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 2)
	$tip.SetToolTip($ui.Swap, 'Quelle und Ziel vertauschen')
	$ui.Swap.Add_Click({
			$s = $script:srgUi.Source.Text
			$script:srgUi.Source.Text = $script:srgUi.Destination.Text
			$script:srgUi.Destination.Text = $s
			Update-srgPathState 'Source'; Update-srgPathState 'Destination'
		})
	$tPath.Controls.Add($ui.Swap, 4, 0)

	$ui.Files = New-Object System.Windows.Forms.TextBox
	$ui.Files.Dock = 'Fill'
	$ui.Files.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 3)
	$ui.Files.Add_TextChanged({ Update-srgOutput })
	$ui.Files.AllowDrop = $true
	$ui.Files.Add_DragEnter({ param($s, $e) Invoke-srgDragEnter $e })
	$ui.Files.Add_DragDrop({ param($s, $e) Invoke-srgDrop 'Files' $e })
	$tip.SetToolTip($ui.Files, 'Zu kopierende Dateien: Namen oder Platzhalter, mehrere mit ; trennen. Leer = alle (*.*).')
	$ui.FilesPick = New-srgButton 'Dateien...' 90
	$ui.FilesPick.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 2)
	$ui.FilesPick.Add_Click({ Show-srgFilesPicker })
	$ui.FilesClear = New-srgButton 'Alle (*.*)' 78
	$ui.FilesClear.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 2)
	$ui.FilesClear.Add_Click({ $script:srgUi.Files.Text = '' })
	$tPath.Controls.Add((New-srgLabel 'Dateien:'), 0, 2); $tPath.Controls.Add($ui.Files, 1, 2)
	$tPath.Controls.Add($ui.FilesPick, 2, 2); $tPath.Controls.Add($ui.FilesClear, 3, 2)
	$gPath.Controls.Add($tPath)
	$root.Controls.Add($gPath, 0, 0)

	# --- Werkzeugleiste -----------------------------------------------------------------------
	$fBar = New-Object System.Windows.Forms.FlowLayoutPanel
	$fBar.Dock = 'Fill'
	$fBar.WrapContents = $false
	$ui.Preset = New-Object System.Windows.Forms.ComboBox; $ui.Preset.DropDownStyle = 'DropDownList'; $ui.Preset.Width = 290
	$ui.Preset.MaxDropDownItems = 15
	[void]$ui.Preset.Items.Add('-- Vorlage waehlen --')
	foreach ($k in (Get-srgPreset).Keys) { [void]$ui.Preset.Items.Add($k) }
	$ui.Preset.SelectedIndex = 0
	$ui.Preset.Margin = New-Object System.Windows.Forms.Padding(3, 8, 3, 3)
	$ui.Import = New-srgButton 'Befehl importieren...' 140
	$tip.SetToolTip($ui.Import, 'Vorhandene robocopy-Zeile (cmd, Batch oder PowerShell) einfuegen und in die Felder uebernehmen.')
	$ui.ImportJob = New-srgButton 'RCJ oeffnen...' 100
	$tip.SetToolTip($ui.ImportJob, 'robocopy-Auftragsdatei (.RCJ, erzeugt mit /SAVE) einlesen.')
	$ui.Reset = New-srgButton 'Zuruecksetzen' 100
	$tip.SetToolTip($ui.Reset, 'Alle Optionen leeren (Quelle, Ziel und Dateien bleiben).')
	$ui.Load = New-srgButton 'Laden...' 80
	$ui.Save = New-srgButton 'Speichern...' 90
	foreach ($b in $ui.Import, $ui.ImportJob, $ui.Reset, $ui.Load, $ui.Save) { $b.Margin = New-Object System.Windows.Forms.Padding(3, 6, 3, 3) }
	$ui.SetCount = New-srgLabel ''
	$ui.SetCount.Margin = New-Object System.Windows.Forms.Padding(12, 11, 3, 3)
	$ui.SetCount.ForeColor = [System.Drawing.Color]::DimGray
	$ui.Message = New-srgLabel ''
	$ui.Message.Margin = New-Object System.Windows.Forms.Padding(12, 11, 3, 3)
	$lblPreset = New-srgLabel 'Vorlage:'
	$lblPreset.Margin = New-Object System.Windows.Forms.Padding(3, 11, 3, 3)
	$fBar.Controls.AddRange(@($lblPreset, $ui.Preset, $ui.Import, $ui.ImportJob, $ui.Reset, $ui.Load, $ui.Save, $ui.SetCount, $ui.Message))
	$root.Controls.Add($fBar, 0, 1)

	# --- Hauptbereich -------------------------------------------------------------------------
	$split = New-Object System.Windows.Forms.SplitContainer
	$split.Dock = 'Fill'
	$split.Orientation = 'Vertical'
	$ui.Split = $split

	# links: Kategorienliste (wie der Optionen-Dialog von Visual Studio), Optionen, Hilfe
	$left = New-Object System.Windows.Forms.TableLayoutPanel
	$left.Dock = 'Fill'; $left.ColumnCount = 2; $left.RowCount = 2
	[void]$left.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 210)))
	[void]$left.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
	[void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
	[void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 70)))

	$nav = New-Object System.Windows.Forms.ListBox
	$nav.Dock = 'Fill'
	$nav.DrawMode = 'OwnerDrawFixed'
	$nav.ItemHeight = 32
	$nav.IntegralHeight = $false
	$nav.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
	$nav.Add_DrawItem({ param($s, $e) Invoke-srgDrawNav $s $e })
	$nav.Add_SelectedIndexChanged({ Show-srgGroup $script:srgUi.Nav.SelectedItem })
	$ui.Nav = $nav

	$content = New-Object System.Windows.Forms.Panel
	$content.Dock = 'Fill'
	$ui.Pages = [ordered]@{}
	$ui.GroupCount = @{}

	foreach ($grp in (Get-srgParameterDefinition | Group-Object Group)) {
		$tbl = New-Object System.Windows.Forms.TableLayoutPanel
		$tbl.Dock = 'Fill'
		$tbl.AutoScroll = $true
		$tbl.Visible = $false
		$tbl.ColumnCount = 2
		$tbl.RowCount = 0
		$tbl.Padding = New-Object System.Windows.Forms.Padding(4, 6, 20, 4)
		[void]$tbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 118)))
		[void]$tbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
		foreach ($d in $grp.Group) { New-srgField -Def $d -Table $tbl -Tip $tip }
		# Fuellzeile, damit die Zeilen oben bleiben
		$tbl.RowCount++
		[void]$tbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
		$content.Controls.Add($tbl)
		$ui.Pages[$grp.Name] = $tbl
		$ui.GroupCount[$grp.Name] = 0
		[void]$nav.Items.Add($grp.Name)
	}
	$left.Controls.Add($nav, 0, 0)
	$left.Controls.Add($content, 1, 0)

	$ui.Help = New-Object System.Windows.Forms.Label
	$ui.Help.Dock = 'Fill'
	$ui.Help.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
	$ui.Help.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
	$ui.Help.Text = 'Option anklicken fuer Hilfe. Nur gesetzte Optionen landen im Befehl - alles andere bleibt robocopy-Standard.'
	$left.Controls.Add($ui.Help, 0, 1)
	$left.SetColumnSpan($ui.Help, 2)
	$split.Panel1.Controls.Add($left)

	# rechts: Format, Aufgaben-Optionen, Ausgabe, Aktionen, Fortschritt, Pruefung
	$right = New-Object System.Windows.Forms.TableLayoutPanel
	$right.Dock = 'Fill'; $right.ColumnCount = 1; $right.RowCount = 6
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34)))
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 66)))
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 40)))
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))
	[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 34)))

	$fFmt = New-Object System.Windows.Forms.FlowLayoutPanel
	$fFmt.Dock = 'Fill'; $fFmt.WrapContents = $false
	$ui.Formats = [ordered]@{}
	foreach ($f in @(@('CommandLine', 'Kommandozeile'), @('Batch', 'Batch (.cmd)'), @('PowerShell', 'PowerShell'), @('ScheduledTask', 'Geplante Aufgabe'))) {
		$rb = New-Object System.Windows.Forms.RadioButton
		$rb.Text = $f[1]; $rb.Tag = $f[0]; $rb.AutoSize = $true
		$rb.Margin = New-Object System.Windows.Forms.Padding(3, 6, 12, 3)
		$rb.Add_CheckedChanged({ if ($this.Checked) { Update-srgTaskPanel; Update-srgOutput } })
		$ui.Formats[$f[0]] = $rb
		$fFmt.Controls.Add($rb)
	}
	$ui.Formats['CommandLine'].Checked = $true
	$right.Controls.Add($fFmt, 0, 0)

	# Geplante Aufgabe
	$gTask = New-Object System.Windows.Forms.GroupBox
	$gTask.Text = 'Geplante Aufgabe (Windows-Aufgabenplanung)'
	$gTask.Dock = 'Fill'
	$gTask.Height = 112
	$tTask = New-Object System.Windows.Forms.TableLayoutPanel
	$tTask.Dock = 'Fill'; $tTask.ColumnCount = 1; $tTask.RowCount = 2
	$f1 = New-Object System.Windows.Forms.FlowLayoutPanel; $f1.AutoSize = $true; $f1.WrapContents = $false
	$f2 = New-Object System.Windows.Forms.FlowLayoutPanel; $f2.AutoSize = $true; $f2.WrapContents = $false
	$ui.TaskName = New-Object System.Windows.Forms.TextBox; $ui.TaskName.Width = 250
	$ui.TaskPath = New-Object System.Windows.Forms.TextBox; $ui.TaskPath.Width = 110; $ui.TaskPath.Text = '\sqmRobocopy\'
	$ui.TaskUser = New-Object System.Windows.Forms.ComboBox; $ui.TaskUser.DropDownStyle = 'DropDownList'; $ui.TaskUser.Width = 200
	[void]$ui.TaskUser.Items.AddRange(@('SYSTEM', [System.Security.Principal.WindowsIdentity]::GetCurrent().Name))
	$ui.TaskUser.SelectedIndex = 0
	$tip.SetToolTip($ui.TaskUser, "SYSTEM: laeuft auch ohne Anmeldung, Freigaben mit dem Computerkonto.`r`nAktueller Benutzer: nur solange er angemeldet ist.")
	$ui.Schedule = New-Object System.Windows.Forms.ComboBox; $ui.Schedule.DropDownStyle = 'DropDownList'; $ui.Schedule.Width = 110
	[void]$ui.Schedule.Items.AddRange(@('kein Zeitplan', 'einmalig', 'taeglich', 'woechentlich', 'Intervall'))
	$ui.Schedule.SelectedIndex = 2
	$ui.Time = New-Object System.Windows.Forms.ComboBox; $ui.Time.Width = 70; $ui.Time.MaxDropDownItems = 16
	for ($m = 0; $m -lt 1440; $m += 30) { [void]$ui.Time.Items.Add(('{0:00}:{1:00}' -f [math]::Floor($m / 60), ($m % 60))) }
	$ui.Time.Text = '22:00'
	$ui.Interval = New-Object System.Windows.Forms.NumericUpDown
	$ui.Interval.Minimum = 1; $ui.Interval.Maximum = 1440; $ui.Interval.Value = 60; $ui.Interval.Width = 60
	$ui.Days = [ordered]@{}
	foreach ($d in @(@('Monday', 'Mo'), @('Tuesday', 'Di'), @('Wednesday', 'Mi'), @('Thursday', 'Do'), @('Friday', 'Fr'), @('Saturday', 'Sa'), @('Sunday', 'So'))) {
		$cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $d[1]; $cb.Tag = $d[0]; $cb.AutoSize = $true
		$cb.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 3)
		if ($d[0] -eq 'Sunday') { $cb.Checked = $true }
		$cb.Add_CheckedChanged({ Update-srgOutput })
		$ui.Days[$d[0]] = $cb
	}
	foreach ($c in $ui.TaskName, $ui.TaskPath, $ui.TaskUser, $ui.Schedule, $ui.Time, $ui.Interval) { $c.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 3) }
	$f1.Controls.AddRange(@((New-srgLabel 'Name:'), $ui.TaskName, (New-srgLabel 'Ordner:'), $ui.TaskPath, (New-srgLabel 'Konto:'), $ui.TaskUser))
	$ui.LblEvery = New-srgLabel 'alle'
	$ui.LblMin = New-srgLabel 'Min. ab'
	$ui.LblAt = New-srgLabel 'um'
	$f2.Controls.AddRange(@((New-srgLabel 'Zeitplan:'), $ui.Schedule, $ui.LblEvery, $ui.Interval, $ui.LblMin, $ui.LblAt, $ui.Time) + @($ui.Days.Values))
	foreach ($l in @($f1.Controls) + @($f2.Controls) | Where-Object { $_ -is [System.Windows.Forms.Label] }) { $l.Margin = New-Object System.Windows.Forms.Padding(3, 6, 3, 3) }
	$tTask.Controls.Add($f1, 0, 0)
	$tTask.Controls.Add($f2, 0, 1)
	$gTask.Controls.Add($tTask)
	$ui.TaskBox = $gTask
	foreach ($c in $ui.TaskName, $ui.TaskPath) { $c.Add_TextChanged({ Update-srgOutput }) }
	$ui.TaskUser.Add_SelectedIndexChanged({ Update-srgOutput })
	$ui.Schedule.Add_SelectedIndexChanged({ Update-srgTaskPanel; Update-srgOutput })
	$ui.Time.Add_TextChanged({ Update-srgOutput })
	$ui.Interval.Add_ValueChanged({ Update-srgOutput })
	$right.Controls.Add($gTask, 0, 1)

	# Ausgabe: zwei Umschaltflaechen statt TabControl (dessen Reiterstreifen bleibt sonst hell)
	$outBox = New-Object System.Windows.Forms.TableLayoutPanel
	$outBox.Dock = 'Fill'; $outBox.ColumnCount = 1; $outBox.RowCount = 2; $outBox.Margin = New-Object System.Windows.Forms.Padding(0)
	[void]$outBox.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))
	[void]$outBox.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
	$fTabs = New-Object System.Windows.Forms.FlowLayoutPanel
	$fTabs.Dock = 'Fill'; $fTabs.WrapContents = $false; $fTabs.Margin = New-Object System.Windows.Forms.Padding(0)
	$ui.OutButtons = @()
	$i = 0
	foreach ($t in 'Befehl', 'Ausfuehrung / Protokoll') {
		$tb = New-srgButton $t 200
		$tb.Tag = $i++
		$tb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 2, 0)
		$tb.Add_Click({ Show-srgOutTab $this.Tag })
		$ui.OutButtons += $tb
		$fTabs.Controls.Add($tb)
	}
	$outHost = New-Object System.Windows.Forms.Panel
	$outHost.Dock = 'Fill'; $outHost.Margin = New-Object System.Windows.Forms.Padding(0)
	foreach ($n in 'Output', 'RunLog') {
		$rtb = New-Object System.Windows.Forms.RichTextBox
		$rtb.Dock = 'Fill'; $rtb.ReadOnly = $true; $rtb.DetectUrls = $false
		$rtb.WordWrap = $n -eq 'Output'
		$rtb.ScrollBars = if ($n -eq 'Output') { 'Vertical' } else { 'Both' }
		$rtb.Font = New-Object System.Drawing.Font('Consolas', 10)
		$ui[$n] = $rtb
		$outHost.Controls.Add($rtb)
	}
	$outBox.Controls.Add($fTabs, 0, 0)
	$outBox.Controls.Add($outHost, 0, 1)
	$right.Controls.Add($outBox, 0, 2)

	$fAct = New-Object System.Windows.Forms.FlowLayoutPanel
	$fAct.Dock = 'Fill'; $fAct.WrapContents = $false
	$ui.Copy = New-srgButton 'Kopieren' 80
	$ui.SaveFile = New-srgButton 'Als Datei...' 90
	$ui.DryRun = New-srgButton 'Trockenlauf (/L)' 115
	$tip.SetToolTip($ui.DryRun, 'Fuehrt robocopy mit /L aus: listet auf, was passieren wuerde - kopiert, loescht und aendert nichts.')
	$ui.Run = New-srgButton 'Ausfuehren' 95
	$ui.Stop = New-srgButton 'Abbrechen' 85
	$ui.Stop.Enabled = $false
	$ui.CreateTask = New-srgButton 'Aufgabe anlegen...' 125
	$ui.Valid = New-srgLabel ''
	$ui.Valid.Margin = New-Object System.Windows.Forms.Padding(10, 11, 3, 3)
	$ui.Valid.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
	foreach ($b in $ui.Copy, $ui.SaveFile, $ui.DryRun, $ui.Run, $ui.Stop, $ui.CreateTask) { $b.Margin = New-Object System.Windows.Forms.Padding(3, 6, 3, 3) }
	$fAct.Controls.AddRange(@($ui.Copy, $ui.SaveFile, $ui.DryRun, $ui.Run, $ui.Stop, $ui.CreateTask, $ui.Valid))
	$right.Controls.Add($fAct, 0, 3)

	# Fortschritt: eigener Balken, weil die WinForms-ProgressBar sich nicht dunkel faerben laesst
	$tProg = New-Object System.Windows.Forms.TableLayoutPanel
	$tProg.Dock = 'Fill'; $tProg.ColumnCount = 2; $tProg.RowCount = 1; $tProg.Margin = New-Object System.Windows.Forms.Padding(0)
	[void]$tProg.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 160)))
	[void]$tProg.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
	[void]$tProg.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
	$ui.Bar = New-Object System.Windows.Forms.Panel
	$ui.Bar.Dock = 'Fill'; $ui.Bar.Margin = New-Object System.Windows.Forms.Padding(3, 7, 6, 7)
	$ui.Bar.Tag = 0.0
	$ui.Bar.Add_Paint({ param($s, $e) Invoke-srgDrawBar $s $e })
	$ui.ProgText = New-srgLabel 'bereit'
	$ui.ProgText.AutoSize = $false; $ui.ProgText.Dock = 'Fill'; $ui.ProgText.AutoEllipsis = $true
	$ui.ProgText.TextAlign = 'MiddleLeft'; $ui.ProgText.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
	$ui.ProgText.ForeColor = [System.Drawing.Color]::DimGray
	$tProg.Controls.Add($ui.Bar, 0, 0); $tProg.Controls.Add($ui.ProgText, 1, 0)
	$right.Controls.Add($tProg, 0, 4)

	$gv = New-Object System.Windows.Forms.DataGridView
	$gv.Dock = 'Fill'
	$gv.ReadOnly = $true
	$gv.RowHeadersVisible = $false
	$gv.AllowUserToAddRows = $false; $gv.AllowUserToDeleteRows = $false; $gv.AllowUserToResizeRows = $false
	$gv.SelectionMode = 'FullRowSelect'; $gv.MultiSelect = $false
	$gv.ColumnHeadersHeightSizeMode = 'DisableResizing'; $gv.ColumnHeadersHeight = 26
	foreach ($col in @(@('Typ', 70), @('Option', 100), @('Meldung', 0))) {
		$i = $gv.Columns.Add($col[0], $col[0])
		if ($col[1]) { $gv.Columns[$i].Width = $col[1] } else { $gv.Columns[$i].AutoSizeMode = 'Fill' }
	}
	$gv.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { Select-srgField ([string]$s.Rows[$e.RowIndex].Cells[1].Value).TrimStart('/') } })
	$ui.Issues = $gv
	$right.Controls.Add($gv, 0, 5)
	$split.Panel2.Controls.Add($right)

	$root.Controls.Add($split, 0, 2)
	$form.Controls.Add($root)

	# --- Ereignisse ---------------------------------------------------------------------------
	$ui.Preset.Add_SelectedIndexChanged({ if ($script:srgUi.Preset.SelectedIndex -gt 0) { Set-srgPreset $script:srgUi.Preset.SelectedItem } })
	$ui.Import.Add_Click({ Show-srgImportDialog })
	$ui.ImportJob.Add_Click({ Import-srgJobFile })
	$ui.Reset.Add_Click({ Set-srgValues @{} -KeepPaths })
	$ui.Load.Add_Click({ Import-srgSettings })
	$ui.Save.Add_Click({ Export-srgSettings })
	$ui.Copy.Add_Click({
			if ($script:srgUi.Output.Text) { [System.Windows.Forms.Clipboard]::SetText($script:srgUi.Output.Text); Set-srgStatus 'Befehl in die Zwischenablage kopiert.' }
		})
	$ui.SaveFile.Add_Click({ Save-srgCommandFile })
	$ui.DryRun.Add_Click({ Start-srgRun -DryRun })
	$ui.Run.Add_Click({ Start-srgRun })
	$ui.Stop.Add_Click({ Stop-srgRun })
	$ui.CreateTask.Add_Click({ Invoke-srgCreateTask })
	$form.Add_FormClosing({
			param($s, $e)
			$r = $script:srgUi.Runner
			if ($r -and -not $r.Finished) {
				$a = [System.Windows.Forms.MessageBox]::Show($s, 'robocopy laeuft noch. Abbrechen und schliessen?', 'sqmRobocopyGui', 'YesNo', 'Warning')
				if ($a -ne 'Yes') { $e.Cancel = $true; return }
				$r.Stop()
			}
			if ($script:srgUi.Timer) { $script:srgUi.Timer.Stop() }
			if ($script:srgUi.PathTimer) { $script:srgUi.PathTimer.Stop() }
		})
	$form.Add_KeyDown({
			param($s, $e)
			if ($e.KeyCode -eq 'F5') { Start-srgRun -DryRun:(-not $e.Control); $e.Handled = $true }
		})
	$form.Add_Shown({
			$script:srgUi.Split.SplitterDistance = [int]($script:srgUi.Split.Width * 0.55)
			$script:srgUi.Form.ActiveControl = $script:srgUi.Nav
			foreach ($f in $script:srgUi.Fields.Values) {
				if ($f.Text -is [System.Windows.Forms.TextBox]) { Set-srgCueBanner $f.Text (Get-srgCue $f.Def) }
			}
			Set-srgCueBanner $script:srgUi.Source 'Quellordner: D:\Daten oder \\Server\Freigabe\Ordner'
			Set-srgCueBanner $script:srgUi.Destination 'Zielordner - wird bei Bedarf angelegt'
			Set-srgCueBanner $script:srgUi.Files '*.*  (leer = alle Dateien; mehrere mit ; trennen, z.B. *.bak; *.trn)'
			Set-srgCueBanner $script:srgUi.TaskName 'automatisch: Robocopy <Quelle> nach <Ziel>'
		})

	# Pfadstatus nach dem Tippen entprellt pruefen (eine tote Freigabe blockiert sonst bei jedem Zeichen)
	$ui.PathTimer = New-Object System.Windows.Forms.Timer
	$ui.PathTimer.Interval = 700
	$ui.PathTimer.Add_Tick({ $script:srgUi.PathTimer.Stop(); Update-srgPathState 'Source'; Update-srgPathState 'Destination' })

	$ui.Timer = New-Object System.Windows.Forms.Timer
	$ui.Timer.Interval = 150
	$ui.Timer.Add_Tick({ Update-srgRun })

	$ui.Bold = New-Object System.Drawing.Font($form.Font, [System.Drawing.FontStyle]::Bold)
	Set-srgTheme $form
	Set-srgDarkToolTip $tip
	$ui.Help.BackColor = $script:srgColors.Surface
	$ui.Help.ForeColor = $script:srgColors.Text
	$ui.Nav.BackColor = $script:srgColors.Bg
	$ui.Bar.BackColor = $script:srgColors.Surface
	$nav.SelectedIndex = 0
	Show-srgOutTab 0
	$ui.Loading = $false
	Update-srgTaskPanel
	$form
}

function Get-srgCue($Def) {
	$kind = if ($Def.Type -eq 'Opt') { $Def.ValueKind } else { $Def.Type }
	switch ($kind) {
		'Int' { if ($null -ne $Def.Default) { return "Standard $($Def.Default)" } else { return 'Zahl' } }
		'Bytes' { return 'Bytes, z.B. 1048576' }
		'Size' { return 'z.B. 50M' }
		'Age' { return 'Tage oder JJJJMMTT' }
		'Hours' { return 'hhmm-hhmm' }
		'List' { if ($Def.Name -eq 'XD') { return 'z.B. $RECYCLE.BIN; System Volume Information' } return 'z.B. *.tmp; ~$*; Thumbs.db' }
		'Path' { return 'Dateipfad' }
	}
	''
}

# ===========================================================================================
# Werte lesen / setzen
# ===========================================================================================
function Get-srgFieldValue($Field) {
	$d = $Field.Def
	switch ($d.Type) {
		'Switch' { if ($Field.Check.Checked) { return $true } else { return $null } }
		'Opt' {
			if (-not $Field.Check.Checked) { return $null }
			if ($Field.Text -is [System.Windows.Forms.ComboBox]) {
				if ($Field.Text.SelectedIndex -le 0) { return $true } else { return [string]$Field.Text.SelectedItem }
			}
			$t = $Field.Text.Text.Trim()
			if ($t) { return $t } else { return $true }
		}
		'Flags' {
			$s = (@($Field.Letters.Values | Where-Object Checked | ForEach-Object { $_.Text }) -join '')
			if ($s) { return $s } else { return $null }
		}
		'List' {
			$l = ConvertTo-srgList $Field.Text.Text
			if ($l.Count) { return , $l } else { return $null }
		}
		default {
			$t = $Field.Text.Text.Trim()
			if ($t) { return $t } else { return $null }
		}
	}
}

function Set-srgFieldValue($Field, $Value) {
	$d = $Field.Def
	switch ($d.Type) {
		'Switch' { $Field.Check.Checked = ConvertTo-srgBool $Value }
		'Opt' {
			$on = ($Value -is [bool] -and $Value) -or ($Value -isnot [bool] -and $null -ne $Value -and "$Value".Trim() -ne '')
			$Field.Check.Checked = $on
			$v = if ($on -and $Value -isnot [bool] -and "$Value" -notin '*', 'True', '$true') { "$Value".Trim().ToUpper() } else { '' }
			if ($Field.Text -is [System.Windows.Forms.ComboBox]) {
				$Field.Text.SelectedIndex = [math]::Max(0, $Field.Text.Items.IndexOf($v))
			} else { $Field.Text.Text = $v }
			$Field.Text.Enabled = $on
		}
		'Flags' {
			$s = if ($null -ne $Value) { "$Value".ToUpper() } else { '' }
			foreach ($k in $Field.Letters.Keys) { $Field.Letters[$k].Checked = $s.Contains($k) }
		}
		'List' { $Field.Text.Text = (ConvertTo-srgList $Value) -join '; ' }
		default { $Field.Text.Text = if ($null -ne $Value) { "$Value" } else { '' } }
	}
}

function Get-srgValues {
	$ui = $script:srgUi
	$h = @{}
	if ($ui.Source.Text.Trim()) { $h['Source'] = $ui.Source.Text.Trim() }
	if ($ui.Destination.Text.Trim()) { $h['Destination'] = $ui.Destination.Text.Trim() }
	$files = ConvertTo-srgList $ui.Files.Text
	if ($files.Count) { $h['Files'] = $files }
	foreach ($f in $ui.Fields.Values) {
		$v = Get-srgFieldValue $f
		if ($null -ne $v) { $h[$f.Def.Name] = $v }
	}
	$h
}

function Set-srgValues {
	param([hashtable]$Values, [switch]$KeepPaths)
	$ui = $script:srgUi
	$ui.Loading = $true
	try {
		if (-not $KeepPaths) {
			$ui.Source.Text = [string]$Values['Source']
			$ui.Destination.Text = [string]$Values['Destination']
			$ui.Files.Text = (ConvertTo-srgList $Values['Files']) -join '; '
			foreach ($c in $ui.Source, $ui.Destination) { $c.SelectionStart = $c.Text.Length; $c.SelectionLength = 0 }
		}
		foreach ($f in $ui.Fields.Values) {
			$key = @($Values.Keys | Where-Object { $_ -eq $f.Def.Name })[0]
			Set-srgFieldValue $f $(if ($null -ne $key) { $Values[$key] } else { $null })
		}
	} finally { $ui.Loading = $false }
	Update-srgOutput
	if (-not $KeepPaths) { Update-srgPathState 'Source'; Update-srgPathState 'Destination' }
}

function Invoke-srgFieldChanged([string]$Name) {
	$ui = $script:srgUi
	if (-not $ui -or $ui.Loading) { return }
	$f = $ui.Fields[$Name]
	if ($f.Def.Type -eq 'Opt') { $f.Text.Enabled = $f.Check.Checked }
	# Exklusive Optionen: die anderen der Gruppe abwaehlen
	if ($f.Def.Exclusive -and $null -ne (Get-srgFieldValue $f)) {
		$ui.Loading = $true
		try {
			foreach ($o in $ui.Fields.Values) {
				if ($o.Def.Exclusive -eq $f.Def.Exclusive -and $o.Def.Name -ne $Name) { Set-srgFieldValue $o $null }
			}
		} finally { $ui.Loading = $false }
	}
	Update-srgOutput
}

function Set-srgPreset([string]$Name) {
	$p = (Get-srgPreset)[$Name]
	if (-not $p) { return }
	$v = @{} + $p
	# Quelle / Ziel bleiben, Dateien nur wenn die Vorlage keine eigenen setzt
	$v['Source'] = $script:srgUi.Source.Text
	$v['Destination'] = $script:srgUi.Destination.Text
	if (-not $v.ContainsKey('Files')) { $v['Files'] = $script:srgUi.Files.Text }
	# Protokolldatei behalten
	$cur = Get-srgValues
	foreach ($k in 'LOG', 'LOG+', 'UNILOG', 'UNILOG+', 'TEE', 'NP') { if ($cur.ContainsKey($k) -and -not $v.ContainsKey($k)) { $v[$k] = $cur[$k] } }
	Set-srgValues $v
	Set-srgStatus "Vorlage '$Name' geladen."
	$script:srgUi.Loading = $true
	$script:srgUi.Preset.SelectedIndex = 0
	$script:srgUi.Loading = $false
}

function Get-srgFormat {
	foreach ($k in $script:srgUi.Formats.Keys) { if ($script:srgUi.Formats[$k].Checked) { return $k } }
	'CommandLine'
}

function Get-srgTaskArgs {
	$ui = $script:srgUi
	$a = @{
		TaskPath         = if ($ui.TaskPath.Text.Trim()) { $ui.TaskPath.Text.Trim() } else { '\sqmRobocopy\' }
		TaskUser         = [string]$ui.TaskUser.SelectedItem
		ScheduleType     = @('None', 'Once', 'Daily', 'Weekly', 'Interval')[[math]::Max(0, $ui.Schedule.SelectedIndex)]
		ScheduleTime     = $ui.Time.Text.Trim()
		IntervalMinutes  = [int]$ui.Interval.Value
	}
	if ($ui.TaskName.Text.Trim()) { $a.TaskName = $ui.TaskName.Text.Trim() }
	$days = @($ui.Days.Values | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
	$a.ScheduleWeekDays = if ($days.Count) { $days } else { @('Sunday') }
	$a
}

# ===========================================================================================
# Aktualisierung
# ===========================================================================================
function Update-srgTaskPanel {
	$ui = $script:srgUi
	if (-not $ui -or $ui.Loading) { return }
	$task = (Get-srgFormat) -eq 'ScheduledTask'
	$ui.TaskBox.Visible = $task
	$ui.CreateTask.Visible = $task
	$s = $ui.Schedule.SelectedIndex
	$ui.Time.Enabled = $s -gt 0
	foreach ($c in $ui.LblEvery, $ui.Interval, $ui.LblMin) { $c.Visible = $s -eq 4 }
	$ui.LblAt.Visible = $s -ne 4
	foreach ($cb in $ui.Days.Values) { $cb.Visible = $s -eq 3 }
}

function Update-srgOutput {
	$ui = $script:srgUi
	if (-not $ui -or $ui.Loading) { return }
	$values = Get-srgValues

	# gesetzte Optionen hervorheben, Anzahl pro Kategorie
	$count = @{}
	$n = 0
	foreach ($f in $ui.Fields.Values) {
		$set = $values.ContainsKey($f.Def.Name)
		$f.Label.Font = if ($set) { $ui.Bold } else { $ui.Form.Font }
		$f.Label.ForeColor = if ($set -and $f.Def.Danger) { $script:srgColors.Warning } elseif ($set) { $script:srgColors.SynKeyword } else { $script:srgColors.Text }
		if ($set) { $count[$f.Def.Group] = 1 + [int]$count[$f.Def.Group]; $n++ }
	}
	foreach ($g in @($ui.Pages.Keys)) { $ui.GroupCount[$g] = [int]$count[$g] }
	$ui.Nav.Invalidate()
	$ui.SetCount.Text = '{0} Option(en) gesetzt' -f $n

	# Pruefung
	$issues = @(Test-sqmRobocopyParameter -Parameter $values)
	$ui.Issues.Rows.Clear()
	foreach ($i in ($issues | Sort-Object @{ e = { $_.Severity -ne 'Error' } })) {
		$par = if ($i.Parameter -in 'Source', 'Destination', 'Files') { @{ Source = 'Quelle'; Destination = 'Ziel'; Files = 'Dateien' }[$i.Parameter] } else { '/' + $i.Parameter }
		$r = $ui.Issues.Rows.Add($(if ($i.Severity -eq 'Error') { 'Fehler' } else { 'Hinweis' }), $par, $i.Message)
		$ui.Issues.Rows[$r].DefaultCellStyle.ForeColor = if ($i.Severity -eq 'Error') { $script:srgColors.Critical } else { $script:srgColors.Warning }
	}
	$ui.Issues.ClearSelection()
	$errs = @($issues | Where-Object Severity -eq 'Error').Count
	$warns = $issues.Count - $errs
	if ($errs) {
		$ui.Valid.Text = "$errs Fehler, $warns Hinweis(e)"
		$ui.Valid.ForeColor = $script:srgColors.Critical
	} else {
		$ui.Valid.Text = if ($warns) { "gueltig, $warns Hinweis(e)" } else { 'gueltig' }
		$ui.Valid.ForeColor = $script:srgColors.Ok
	}

	# Befehl
	try {
		$fmt = Get-srgFormat
		$ta = if ($fmt -eq 'ScheduledTask') { Get-srgTaskArgs } else { @{} }
		$ui.Output.ForeColor = $script:srgColors.Text
		$ui.Output.Text = New-sqmRobocopyCommand -Parameter $values -Format $fmt @ta
		Set-srgSyntaxColor $ui.Output -Language $(if ($fmt -in 'PowerShell', 'ScheduledTask') { 'PowerShell' } else { 'Cmd' })
	} catch {
		$ui.Output.ForeColor = $script:srgColors.Critical
		$ui.Output.Text = ":: Befehl kann nicht erzeugt werden:`r`n:: $($_.Exception.Message)"
	}
}

function Update-srgPathState([string]$Key) {
	$ui = $script:srgUi
	if (-not $ui) { return }
	$lbl = $ui["${Key}State"]
	$p = $ui[$Key].Text.Trim().Trim('"')
	if (-not $p) { $lbl.Text = ''; return }
	if ($p -match '[*?<>|]') { $lbl.Text = 'ungueltiger Pfad'; $lbl.ForeColor = $script:srgColors.Critical; return }
	$ui.Form.Cursor = 'WaitCursor'
	try { $state = [Srg.PathProbe]::DirectoryExists($p, 1500) } finally { $ui.Form.Cursor = 'Default' }
	switch ($state) {
		1 { $lbl.Text = 'vorhanden'; $lbl.ForeColor = $script:srgColors.Ok }
		0 {
			if ($Key -eq 'Source') { $lbl.Text = 'nicht gefunden'; $lbl.ForeColor = $script:srgColors.Critical }
			else { $lbl.Text = 'neu - wird angelegt'; $lbl.ForeColor = $script:srgColors.Info }
		}
		default { $lbl.Text = 'keine Antwort (Netzwerk?)'; $lbl.ForeColor = $script:srgColors.Warning }
	}
	$ui.Tip.SetToolTip($lbl, $lbl.Text)
}

function Start-srgPathCheck {
	$ui = $script:srgUi
	if (-not $ui -or $ui.Loading -or -not $ui.PathTimer) { return }
	$ui.PathTimer.Stop(); $ui.PathTimer.Start()
}

function Show-srgOutTab([int]$Index) {
	$ui = $script:srgUi
	$ui.OutIndex = $Index
	$ui.Output.Visible = $Index -eq 0
	$ui.RunLog.Visible = $Index -eq 1
	for ($i = 0; $i -lt $ui.OutButtons.Count; $i++) {
		$b = $ui.OutButtons[$i]
		$b.BackColor = if ($i -eq $Index) { $script:srgColors.Accent } else { $script:srgColors.Surface }
		$b.FlatAppearance.BorderColor = if ($i -eq $Index) { $script:srgColors.Accent } else { $script:srgColors.Border }
	}
}

function Show-srgGroup([string]$Group) {
	foreach ($g in @($script:srgUi.Pages.Keys)) { $script:srgUi.Pages[$g].Visible = ($g -eq $Group) }
}

function Invoke-srgDrawNav($List, $e) {
	if ($e.Index -lt 0) { return }
	$c = $script:srgColors
	$name = [string]$List.Items[$e.Index]
	$sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
	$g = $e.Graphics
	$back = New-Object System.Drawing.SolidBrush($(if ($sel) { $c.Selection } else { $c.Bg }))
	$g.FillRectangle($back, $e.Bounds); $back.Dispose()
	if ($sel) {
		$bar = New-Object System.Drawing.SolidBrush($c.Accent)
		$g.FillRectangle($bar, $e.Bounds.X, $e.Bounds.Y, 3, $e.Bounds.Height); $bar.Dispose()
	}
	$r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 12), $e.Bounds.Y, ($e.Bounds.Width - 50), $e.Bounds.Height)
	$flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
	[System.Windows.Forms.TextRenderer]::DrawText($g, $name, $List.Font, $r, $c.Text, $flags)
	$n = [int]$script:srgUi.GroupCount[$name]
	if ($n) {
		$badge = New-Object System.Drawing.Rectangle(($e.Bounds.Right - 36), ($e.Bounds.Y + 7), 26, ($e.Bounds.Height - 14))
		$bb = New-Object System.Drawing.SolidBrush($c.Accent)
		$g.FillRectangle($bb, $badge); $bb.Dispose()
		[System.Windows.Forms.TextRenderer]::DrawText($g, [string]$n, $List.Font, $badge, [System.Drawing.Color]::White,
			[System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter)
	}
}

function Invoke-srgDrawBar($Panel, $e) {
	$pct = [double]$Panel.Tag
	if ($pct -le 0) { return }
	$w = [int]($Panel.ClientSize.Width * [math]::Min(1.0, $pct / 100.0))
	$b = New-Object System.Drawing.SolidBrush($script:srgColors.Accent)
	$e.Graphics.FillRectangle($b, 0, 0, $w, $Panel.ClientSize.Height); $b.Dispose()
}

function Show-srgHelp([string]$Name) {
	$f = $script:srgUi.Fields[$Name]
	if (-not $f) { return }
	$d = $f.Def
	$std = if ($null -ne $d.Default) { "  (Standard: $($d.Default))" } else { '' }
	$script:srgUi.Help.Text = "/$($d.Name)$std`r`n$($d.Help)"
}

function Select-srgField([string]$Name) {
	$ui = $script:srgUi
	if ($Name -in 'Quelle', 'Source') { [void]$ui.Source.Focus(); return }
	if ($Name -in 'Ziel', 'Destination') { [void]$ui.Destination.Focus(); return }
	if ($Name -in 'Dateien', 'Files') { [void]$ui.Files.Focus(); return }
	$f = $ui.Fields[$Name]
	if (-not $f) { return }
	$ui.Nav.SelectedItem = $f.Def.Group
	if ($f.Text -and $f.Text.Enabled) { [void]$f.Text.Focus() }
	elseif ($f.Check) { [void]$f.Check.Focus() }
	elseif ($f.Letters) { [void]@($f.Letters.Values)[0].Focus() }
	Show-srgHelp $Name
}

function Set-srgStatus([string]$Text, [switch]$IsError) {
	$script:srgUi.Message.Text = $Text
	$script:srgUi.Message.ForeColor = if ($IsError) { $script:srgColors.Critical } else { $script:srgColors.Ok }
}

# ===========================================================================================
# Auswahl von Ordnern / Dateien, Drag & Drop
# ===========================================================================================
function Get-srgPickStart([string]$Path) {
	$p = $Path.Trim().Trim('"')
	while ($p -and -not ([Srg.PathProbe]::DirectoryExists($p, 800) -eq 1)) {
		$parent = Split-Path $p -Parent
		if (-not $parent -or $parent -eq $p) { $p = ''; break }
		$p = $parent
	}
	$p
}

function Select-srgFolder([string]$Title, [string]$Start, [switch]$Multi) {
	$ui = $script:srgUi
	try {
		# Komma: sonst entpackt PowerShell ein einelementiges Array zum String, und $r[0] waere nur der erste Buchstabe
		$picked = [Srg.FolderPicker]::Pick($ui.Form.Handle, $Title, $Start, [bool]$Multi)
		if ($null -eq $picked) { return $null }
		return ,$picked
	} catch {
		# Rueckfall: klassischer Dialog
		$fbd = New-Object System.Windows.Forms.FolderBrowserDialog
		$fbd.Description = $Title
		if ($Start) { $fbd.SelectedPath = $Start }
		try { if ($fbd.ShowDialog($ui.Form) -eq 'OK') { return ,@($fbd.SelectedPath) } } finally { $fbd.Dispose() }
		return $null
	}
}

function Show-srgDirPicker([string]$Key) {
	$ui = $script:srgUi
	$title = if ($Key -eq 'Source') { 'Quellordner auswaehlen' } else { 'Zielordner auswaehlen' }
	$start = Get-srgPickStart $ui[$Key].Text
	# Ziel nicht am Quellordner starten lassen: ohne eigenen Pfad "Dieser PC"
	if (-not $start -and $Key -eq 'Destination') { $start = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}' }
	$r = Select-srgFolder -Title $title -Start $start
	if ($r) { $ui[$Key].Text = $r[0]; Update-srgPathState $Key }
}

function Open-srgExplorer([string]$Key) {
	$p = Get-srgPickStart $script:srgUi[$Key].Text
	if ($p) { Start-Process explorer.exe -ArgumentList "`"$p`"" }
	else { Set-srgStatus 'Ordner existiert (noch) nicht.' -IsError }
}

function Show-srgFilesPicker {
	$ui = $script:srgUi
	$ofd = New-Object System.Windows.Forms.OpenFileDialog
	$ofd.Title = 'Dateien fuer die Kopie auswaehlen (nur die Namen werden uebernommen)'
	$ofd.Multiselect = $true
	$ofd.Filter = 'Alle Dateien (*.*)|*.*'
	$start = Get-srgPickStart $ui.Source.Text
	if ($start) { $ofd.InitialDirectory = $start }
	if ($ofd.ShowDialog($ui.Form) -eq 'OK') {
		Add-srgFileNames ($ofd.FileNames)
	}
	$ofd.Dispose()
}

function Add-srgFileNames([string[]]$Paths) {
	$ui = $script:srgUi
	$names = @($Paths | ForEach-Object { Split-Path $_ -Leaf })
	$dirs = @($Paths | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique)
	$src = Get-srgPickStart $ui.Source.Text
	if ($dirs.Count -eq 1 -and (-not $ui.Source.Text.Trim() -or $src -ne $dirs[0])) {
		if (-not $ui.Source.Text.Trim()) {
			$ui.Source.Text = $dirs[0]; Update-srgPathState 'Source'
		} elseif ($src.TrimEnd('\') -ne $dirs[0].TrimEnd('\')) {
			$q = "Die Dateien liegen in`r`n$($dirs[0])`r`n`r`nQuelle auf diesen Ordner setzen?"
			if ([System.Windows.Forms.MessageBox]::Show($ui.Form, $q, 'Dateien', 'YesNo', 'Question') -eq 'Yes') {
				$ui.Source.Text = $dirs[0]; Update-srgPathState 'Source'
			}
		}
	}
	$cur = ConvertTo-srgList $ui.Files.Text
	$ui.Files.Text = (@($cur) + $names | Select-Object -Unique) -join '; '
}

function Invoke-srgDragEnter($e) {
	$e.Effect = if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { 'Copy' } else { 'None' }
}

function Invoke-srgDrop([string]$Key, $e) {
	$ui = $script:srgUi
	$paths = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
	if (-not $paths.Count) { return }
	if ($Key -eq 'Files') { Add-srgFileNames @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }); return }
	$p = $paths[0]
	if (Test-Path -LiteralPath $p -PathType Leaf) {
		# Datei auf Quelle/Ziel gezogen: deren Ordner nehmen, bei der Quelle die Dateinamen uebernehmen
		$ui[$Key].Text = Split-Path $p -Parent
		if ($Key -eq 'Source') { $ui.Files.Text = (@($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Split-Path $_ -Leaf })) -join '; ' }
	} else {
		$ui[$Key].Text = $p
	}
	Update-srgPathState $Key
}

function Show-srgFieldPicker([string]$Name) {
	$ui = $script:srgUi
	$f = $ui.Fields[$Name]
	$d = $f.Def
	switch ($d.Picker) {
		'Files' {
			$ofd = New-Object System.Windows.Forms.OpenFileDialog
			$ofd.Title = "Dateien fuer /$Name auswaehlen (nur die Namen werden uebernommen)"
			$ofd.Multiselect = $true
			$start = Get-srgPickStart $ui.Source.Text
			if ($start) { $ofd.InitialDirectory = $start }
			if ($ofd.ShowDialog($ui.Form) -eq 'OK') {
				$cur = ConvertTo-srgList $f.Text.Text
				$f.Text.Text = (@($cur) + @($ofd.FileNames | ForEach-Object { Split-Path $_ -Leaf }) | Select-Object -Unique) -join '; '
			}
			$ofd.Dispose()
		}
		'Folders' {
			$start = Get-srgPickStart $ui.Source.Text
			$r = Select-srgFolder -Title "Verzeichnisse fuer /$Name auswaehlen (Mehrfachauswahl mit Strg)" -Start $start -Multi
			if ($r) {
				$src = (ConvertTo-srgDirectory $ui.Source.Text).TrimEnd('\')
				# Unterordner der Quelle als Name, sonst als vollstaendiger Pfad
				$items = foreach ($p in $r) {
					if ($src -and (Split-Path $p -Parent).TrimEnd('\') -eq $src) { Split-Path $p -Leaf } else { $p }
				}
				$cur = ConvertTo-srgList $f.Text.Text
				$f.Text.Text = (@($cur) + @($items) | Select-Object -Unique) -join '; '
			}
		}
		{ $_ -in 'SaveLog', 'SaveJob' } {
			$sfd = New-Object System.Windows.Forms.SaveFileDialog
			$sfd.OverwritePrompt = $false
			if ($d.Picker -eq 'SaveLog') {
				$sfd.Filter = 'Protokoll (*.log;*.txt)|*.log;*.txt|Alle Dateien (*.*)|*.*'
				$leaf = (ConvertTo-srgDirectory $ui.Source.Text).TrimEnd('\').Split('\')[-1]
				$sfd.FileName = if ($f.Text.Text) { Split-Path $f.Text.Text -Leaf } else { "robocopy_$($leaf -replace '[:\\]', '').log" }
			} else {
				$sfd.Filter = 'robocopy-Auftrag (*.rcj)|*.rcj'
				$sfd.FileName = 'robocopy.rcj'
			}
			if ($sfd.ShowDialog($ui.Form) -eq 'OK') {
				$p = $sfd.FileName
				# /SAVE haengt .RCJ selbst an
				if ($d.Picker -eq 'SaveJob') { $p = $p -replace '\.rcj$', '' }
				$f.Text.Text = $p
			}
			$sfd.Dispose()
		}
		'OpenJob' {
			$ofd = New-Object System.Windows.Forms.OpenFileDialog
			$ofd.Filter = 'robocopy-Auftrag (*.rcj)|*.rcj|Alle Dateien (*.*)|*.*'
			if ($ofd.ShowDialog($ui.Form) -eq 'OK') { $f.Text.Text = $ofd.FileName }
			$ofd.Dispose()
		}
	}
}

# ===========================================================================================
# Import / Speichern / Laden
# ===========================================================================================
function Show-srgImportDialog {
	$ui = $script:srgUi
	$dlg = New-Object System.Windows.Forms.Form
	$dlg.Text = 'robocopy-Befehl importieren'
	$dlg.Size = New-Object System.Drawing.Size(860, 360)
	$dlg.StartPosition = 'CenterParent'
	$dlg.Font = $ui.Form.Font
	$dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
	$t = New-Object System.Windows.Forms.TableLayoutPanel
	$t.Dock = 'Fill'; $t.ColumnCount = 1; $t.RowCount = 3; $t.Padding = New-Object System.Windows.Forms.Padding(8)
	[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
	[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
	[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 40)))
	$t.Controls.Add((New-srgLabel 'robocopy-Zeile einfuegen (cmd, Batch mit ^-Fortsetzung oder PowerShell). Alle Felder werden ersetzt.'), 0, 0)
	$box = New-Object System.Windows.Forms.TextBox
	$box.Multiline = $true; $box.Dock = 'Fill'; $box.ScrollBars = 'Vertical'
	$box.Font = New-Object System.Drawing.Font('Consolas', 10)
	try {
		$clip = [System.Windows.Forms.Clipboard]::GetText()
		if ($clip -match '(?i)robocopy') { $box.Text = $clip.Trim() }
	} catch { }
	$t.Controls.Add($box, 0, 1)
	$fb = New-Object System.Windows.Forms.FlowLayoutPanel; $fb.Dock = 'Fill'; $fb.FlowDirection = 'RightToLeft'
	$ok = New-srgButton 'Uebernehmen' 100; $ok.DialogResult = 'OK'
	$cancel = New-srgButton 'Abbrechen' 90; $cancel.DialogResult = 'Cancel'
	$fb.Controls.AddRange(@($cancel, $ok))
	$t.Controls.Add($fb, 0, 2)
	$dlg.Controls.Add($t)
	$dlg.CancelButton = $cancel
	Set-srgTheme $dlg
	if ($dlg.ShowDialog($ui.Form) -eq 'OK' -and $box.Text.Trim()) {
		try {
			$warn = @()
			$h = ConvertFrom-sqmRobocopyCommand -CommandLine $box.Text -WarningVariable warn -WarningAction SilentlyContinue
			Set-srgValues $h
			if ($warn.Count) { Set-srgStatus ("Importiert, aber: " + (@($warn | ForEach-Object { "$_" }) -join ' ')) -IsError }
			else { Set-srgStatus 'Befehl importiert.' }
		} catch { Set-srgStatus "Import fehlgeschlagen: $($_.Exception.Message)" -IsError }
	}
	$dlg.Dispose()
}

function Import-srgJobFile {
	$ui = $script:srgUi
	$ofd = New-Object System.Windows.Forms.OpenFileDialog
	$ofd.Filter = 'robocopy-Auftrag (*.rcj)|*.rcj|Alle Dateien (*.*)|*.*'
	if ($ofd.ShowDialog($ui.Form) -eq 'OK') {
		try {
			$warn = @()
			$h = ConvertFrom-sqmRobocopyCommand -JobFile $ofd.FileName -WarningVariable warn -WarningAction SilentlyContinue
			Set-srgValues $h
			if ($warn.Count) { Set-srgStatus ("Auftrag geladen, aber: " + (@($warn | ForEach-Object { "$_" }) -join ' ')) -IsError }
			else { Set-srgStatus "Auftrag geladen: $($ofd.FileName)" }
		} catch { Set-srgStatus "Laden fehlgeschlagen: $($_.Exception.Message)" -IsError }
	}
	$ofd.Dispose()
}

function Export-srgSettings {
	$ui = $script:srgUi
	$sfd = New-Object System.Windows.Forms.SaveFileDialog
	$sfd.Filter = 'sqmRobocopyGui-Einstellungen (*.json)|*.json'
	$sfd.FileName = 'robocopy.json'
	if ($sfd.ShowDialog($ui.Form) -ne 'OK') { return }
	[pscustomobject]@{
		Tool       = 'sqmRobocopyGui'
		Version    = $script:srgModuleVersion
		Parameters = Get-srgValues
		Format     = Get-srgFormat
		Task       = Get-srgTaskArgs
	} | ConvertTo-Json -Depth 4 | Set-Content -Path $sfd.FileName -Encoding UTF8
	Set-srgStatus "Gespeichert: $($sfd.FileName)"
}

function Import-srgSettings {
	$ui = $script:srgUi
	$ofd = New-Object System.Windows.Forms.OpenFileDialog
	$ofd.Filter = 'sqmRobocopyGui-Einstellungen (*.json)|*.json'
	if ($ofd.ShowDialog($ui.Form) -ne 'OK') { return }
	try {
		$j = Get-Content $ofd.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
		$h = @{}
		foreach ($p in $j.Parameters.PSObject.Properties) {
			$v = $p.Value
			$h[$p.Name] = if ($v -is [array]) { @($v | ForEach-Object { [string]$_ }) } elseif ($v -is [bool]) { $v } else { [string]$v }
		}
		if ($j.Format -and $ui.Formats.Contains([string]$j.Format)) { $ui.Formats[[string]$j.Format].Checked = $true }
		if ($j.Task) {
			$ui.TaskName.Text = [string]$j.Task.TaskName
			if ($j.Task.TaskPath) { $ui.TaskPath.Text = $j.Task.TaskPath }
			if ($j.Task.TaskUser -and $ui.TaskUser.Items.Contains([string]$j.Task.TaskUser)) { $ui.TaskUser.SelectedItem = [string]$j.Task.TaskUser }
			$ui.Schedule.SelectedIndex = [math]::Max(0, [array]::IndexOf(@('None', 'Once', 'Daily', 'Weekly', 'Interval'), [string]$j.Task.ScheduleType))
			if ($j.Task.ScheduleTime) { $ui.Time.Text = [string]$j.Task.ScheduleTime }
			if ($j.Task.IntervalMinutes) { $ui.Interval.Value = [int]$j.Task.IntervalMinutes }
			if ($j.Task.ScheduleWeekDays) { foreach ($k in $ui.Days.Keys) { $ui.Days[$k].Checked = $k -in @($j.Task.ScheduleWeekDays) } }
		}
		Set-srgValues $h
		Set-srgStatus "Geladen: $($ofd.FileName)"
	} catch { Set-srgStatus "Laden fehlgeschlagen: $($_.Exception.Message)" -IsError }
}

function Save-srgCommandFile {
	$ui = $script:srgUi
	$sfd = New-Object System.Windows.Forms.SaveFileDialog
	$fmt = Get-srgFormat
	$sfd.Filter = switch ($fmt) { { $_ -in 'PowerShell', 'ScheduledTask' } { 'PowerShell (*.ps1)|*.ps1' } 'Batch' { 'Batch (*.cmd)|*.cmd|Batch (*.bat)|*.bat' } default { 'Text (*.txt)|*.txt|Batch (*.cmd)|*.cmd' } }
	$sfd.FileName = switch ($fmt) { 'PowerShell' { 'robocopy.ps1' } 'ScheduledTask' { 'robocopy-Aufgabe.ps1' } 'Batch' { 'robocopy.cmd' } default { 'robocopy.txt' } }
	if ($sfd.ShowDialog($ui.Form) -ne 'OK') { return }
	# .ps1 mit BOM (PowerShell 5.1 erkennt Umlaute sonst nicht), Batch ohne BOM (chcp 65001 im Skript)
	$bom = -not ($sfd.FileName -match '\.(cmd|bat|txt)$')
	[System.IO.File]::WriteAllText($sfd.FileName, $ui.Output.Text, (New-Object System.Text.UTF8Encoding($bom)))
	Set-srgStatus "Gespeichert: $($sfd.FileName)"
}

# ===========================================================================================
# Ausfuehren
# ===========================================================================================
function Start-srgRun {
	param([switch]$DryRun)
	$ui = $script:srgUi
	if ($ui.Runner -and -not $ui.Runner.Finished) { return }
	$values = Get-srgValues
	$errs = @(Test-sqmRobocopyParameter -Parameter $values -CheckPath | Where-Object Severity -eq 'Error')
	if ($errs.Count) {
		$txt = ($errs | ForEach-Object { "- $($_.Message)" }) -join "`r`n"
		[void][System.Windows.Forms.MessageBox]::Show($ui.Form, "Bitte zuerst beheben:`r`n`r`n$txt", 'robocopy', 'OK', 'Warning')
		return
	}
	$o = Get-srgActiveParameter $values
	$listOnly = $DryRun -or $o.Contains('L')
	if (-not $listOnly -and $ui.Confirm) {
		$danger = @()
		if ($o.Contains('MIR') -or $o.Contains('PURGE')) { $danger += "- LOESCHT im Ziel alles, was in der Quelle fehlt:`r`n   $($values.Destination)" }
		if ($o.Contains('MOV') -or $o.Contains('MOVE')) { $danger += "- LOESCHT die kopierten Dateien$(if ($o.Contains('MOVE')) { ' und Ordner' }) in der Quelle:`r`n   $($values.Source)" }
		if ($o.Contains('MON') -or $o.Contains('MOT')) { $danger += '- laeuft mit /MON bzw. /MOT dauerhaft, bis Sie abbrechen' }
		$q = if ($danger.Count) { "Achtung, dieser Lauf`r`n`r`n$($danger -join "`r`n")`r`n`r`nTipp: vorher 'Trockenlauf (/L)'.`r`n`r`nJetzt wirklich ausfuehren?" }
		else { "robocopy jetzt ausfuehren?`r`n`r`n$($values.Source)`r`n  ->  $($values.Destination)" }
		$icon = if ($danger.Count) { 'Warning' } else { 'Question' }
		$def = if ($danger.Count) { 'Button2' } else { 'Button1' }
		if ([System.Windows.Forms.MessageBox]::Show($ui.Form, $q, 'robocopy ausfuehren', 'YesNo', $icon, $def) -ne 'Yes') { return }
	}
	$extra = @()
	if ($DryRun) { $extra += '/L' }
	$hasLog = $o.Contains('LOG') -or $o.Contains('LOG+') -or $o.Contains('UNILOG') -or $o.Contains('UNILOG+')
	if ($hasLog -and -not $o.Contains('TEE')) { $extra += '/TEE' }
	$argList = Get-srgArgumentList -Parameter $values -Extra $extra
	$argLine = Join-srgCmdLine $argList

	$log = $ui.RunLog
	$log.Clear()
	Add-srgLogLine "> robocopy $argLine" $script:srgColors.SynKeyword
	if ($DryRun) { Add-srgLogLine '  Trockenlauf mit /L: es wird nichts kopiert, geloescht oder geaendert.' $script:srgColors.Info }
	if ($hasLog -and -not $o.Contains('TEE')) { Add-srgLogLine '  /TEE ergaenzt, damit die Ausgabe trotz Protokolldatei auch hier erscheint.' $script:srgColors.Subtle }
	Show-srgOutTab 1

	$runner = New-Object Srg.Runner
	try {
		$runner.Start((Join-Path $env:SystemRoot 'System32\Robocopy.exe'), $argLine, [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
	} catch {
		Add-srgLogLine "robocopy konnte nicht gestartet werden: $($_.Exception.Message)" $script:srgColors.Critical
		return
	}
	$ui.Runner = $runner
	$ui.RunIsDry = [bool]$DryRun
	$ui.Run.Enabled = $false; $ui.DryRun.Enabled = $false; $ui.Stop.Enabled = $true
	$ui.Bar.Tag = 0.0; $ui.Bar.Invalidate()
	$ui.ProgText.ForeColor = $script:srgColors.Text
	$ui.ProgText.Text = 'robocopy laeuft ...'
	Save-srgConfig -Source $values.Source -Destination $values.Destination
	$ui.Timer.Start()
}

function Stop-srgRun {
	$r = $script:srgUi.Runner
	if ($r -and -not $r.Finished) { $r.Stop() }
}

function Add-srgLogLine([string]$Text, $Color) {
	$box = $script:srgUi.RunLog
	$box.SelectionStart = $box.TextLength
	$box.SelectionLength = 0
	$box.SelectionColor = $Color
	$box.AppendText($Text + "`n")
}

function Get-srgLogColor([string]$Line) {
	$c = $script:srgColors
	if ($Line -match '(?i)\b(FEHLER|ERROR)\b|Zugriff verweigert|Access is denied') { return $c.Critical }
	if ($Line -match '\*EXTRA|\*EXTRA') { return $c.Warning }
	if ($Line -match '(?i)Neue Datei|Neues Verz|New File|New Dir|\bNeuer\b|\bNewer\b') { return $c.Ok }
	if ($Line -match '(?i)\b(Aelter|Älter|Older|Geaendert|Geändert|Changed|Modified|Changed)\b') { return $c.Info }
	if ($Line -match '^\s*-{20,}|ROBOCOPY\s+::') { return $c.Subtle }
	if ($Line -match '(?i)^\s*(Verzeich\.|Dateien|Bytes|Zeiten|Dirs|Files|Times|Geschwindigkeit|Speed|Beendet|Ended|Gestartet|Started)\s*:') { return $c.SynVariable }
	$c.Text
}

function Update-srgRun {
	$ui = $script:srgUi
	$r = $ui.Runner
	if (-not $r) { $ui.Timer.Stop(); return }
	$lines = $r.Drain(3000)
	if ($lines.Count) {
		$box = $ui.RunLog
		# sehr lange Laeufe: alte Zeilen abschneiden, damit die RichTextBox bedienbar bleibt
		if ($box.TextLength -gt 3000000) {
			$box.Select(0, 1500000); $box.ReadOnly = $false; $box.SelectedText = ''; $box.ReadOnly = $true
		}
		$box.SuspendLayout()
		foreach ($l in $lines) { Add-srgLogLine $l (Get-srgLogColor $l) }
		$box.ResumeLayout()
		$box.SelectionStart = $box.TextLength
		$box.ScrollToCaret()
	}
	$elapsed = (Get-Date) - $r.Started
	$pct = 0.0
	if ($r.Progress -match '([\d.]+)%') { $pct = [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) }
	$ui.Bar.Tag = $pct; $ui.Bar.Invalidate()
	$cur = ($r.Current -replace '\s+', ' ').Trim()
	if (-not $r.Finished) {
		$ui.ProgText.Text = '{0:hh\:mm\:ss}  {1}  {2}' -f $elapsed, $r.Progress, $cur
		return
	}
	if ($r.Pending -gt 0) { return }    # erst alles ausgeben
	$ui.Timer.Stop()
	$ui.Run.Enabled = $true; $ui.DryRun.Enabled = $true; $ui.Stop.Enabled = $false
	$dur = $r.Ended - $r.Started
	if ($r.Cancelled) {
		$txt = 'Abgebrochen nach {0:hh\:mm\:ss}.' -f $dur
		$col = $script:srgColors.Warning
	} else {
		$info = ConvertFrom-sqmRobocopyExitCode $r.ExitCode
		$txt = 'Exitcode {0} nach {1:hh\:mm\:ss}: {2}' -f $r.ExitCode, $dur, $info.Text
		if ($ui.RunIsDry) { $txt = "Trockenlauf - " + ($txt -replace 'Dateien kopiert', 'Dateien wuerden kopiert') }
		$col = if ($info.Success) { $script:srgColors.Ok } else { $script:srgColors.Critical }
	}
	Add-srgLogLine '' $script:srgColors.Text
	Add-srgLogLine $txt $col
	$ui.RunLog.SelectionStart = $ui.RunLog.TextLength; $ui.RunLog.ScrollToCaret()
	$ui.Bar.Tag = if ($r.Cancelled) { 0.0 } else { 100.0 }; $ui.Bar.Invalidate()
	$ui.ProgText.Text = $txt
	$ui.ProgText.ForeColor = $col
	Update-srgPathState 'Destination'
}

function Invoke-srgCreateTask {
	$ui = $script:srgUi
	$values = Get-srgValues
	$errs = @(Test-sqmRobocopyParameter -Parameter $values | Where-Object Severity -eq 'Error')
	if ($errs.Count) {
		[void][System.Windows.Forms.MessageBox]::Show($ui.Form, "Die Parameter enthalten $($errs.Count) Fehler - bitte zuerst beheben.", 'Aufgabe anlegen', 'OK', 'Warning')
		return
	}
	if (-not $ui.IsAdmin -and [string]$ui.TaskUser.SelectedItem -eq 'SYSTEM') {
		[void][System.Windows.Forms.MessageBox]::Show($ui.Form, "Eine Aufgabe als SYSTEM kann nur ein Administrator anlegen. Konto auf den aktuellen Benutzer stellen oder die GUI als Administrator starten.`r`n`r`nOder: Skript ueber 'Als Datei...' speichern und in einer Administrator-PowerShell ausfuehren.", 'Aufgabe anlegen', 'OK', 'Information')
		return
	}
	$taskScript = $ui.Output.Text
	$name = if ($taskScript -match "(?m)^\`$taskName\s*=\s*'((?:[^']|'')*)'") { $Matches[1].Replace("''", "'") } else { '?' }
	$path = if ($taskScript -match "(?m)^\`$taskPath\s*=\s*'((?:[^']|'')*)'") { $Matches[1].Replace("''", "'") } else { '' }
	$q = "Geplante Aufgabe '$path$name' anlegen?`r`n`r`nEine vorhandene Aufgabe gleichen Namens wird NICHT ueberschrieben."
	if ([System.Windows.Forms.MessageBox]::Show($ui.Form, $q, 'Aufgabe anlegen', 'YesNo', 'Question') -ne 'Yes') { return }
	$ui.Form.Cursor = 'WaitCursor'
	try {
		$out = & ([scriptblock]::Create($taskScript)) 6>&1 2>&1 | Out-String
		$ui.RunLog.Clear()
		Add-srgLogLine "Aufgabe $path$name angelegt." $script:srgColors.Ok
		if ($out.Trim()) { Add-srgLogLine $out.Trim() $script:srgColors.Subtle }
		Add-srgLogLine 'Hinweis: In der Aufgabenplanung bedeutet "Letztes Ergebnis" 0x0 bis 0x7 Erfolg, ab 0x8 Fehler.' $script:srgColors.Info
		Set-srgStatus "Aufgabe $path$name angelegt."
	} catch {
		$ui.RunLog.Clear()
		Add-srgLogLine "Aufgabe konnte nicht angelegt werden: $($_.Exception.Message)" $script:srgColors.Critical
		Set-srgStatus 'Aufgabe nicht angelegt.' -IsError
	} finally { $ui.Form.Cursor = 'Default' }
	Show-srgOutTab 1
}
