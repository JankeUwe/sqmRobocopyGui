<#
	Visual-Studio-Dark-Farbschema, wie in DbSchemaCompare/SqlRefactorAnalyzer (UI\Theme.cs) und den
	GUIs von sqmSQLTool / sqmPartitionTool / sqmOlaBackupBuilder - damit alle Werkzeuge gleich aussehen.
	Set-srgTheme faerbt ein Formular rekursiv ein; Controls, die nachtraeglich entstehen (Dialoge,
	Kontextmenues), rufen es selbst auf.
#>

$script:srgColors = @{
	Editor    = [System.Drawing.Color]::FromArgb(30, 30, 30)     # #1E1E1E  Editor / Listen
	Bg        = [System.Drawing.Color]::FromArgb(37, 37, 38)     # #252526  Fenster
	Surface   = [System.Drawing.Color]::FromArgb(45, 45, 48)     # #2D2D30  Eingabefelder, Kopfzeilen
	Button    = [System.Drawing.Color]::FromArgb(62, 62, 66)     # #3E3E42
	Border    = [System.Drawing.Color]::FromArgb(63, 63, 70)     # #3F3F46
	Text      = [System.Drawing.Color]::FromArgb(220, 220, 220)  # #DCDCDC
	Subtle    = [System.Drawing.Color]::FromArgb(153, 153, 153)
	Accent    = [System.Drawing.Color]::FromArgb(0, 122, 204)    # #007ACC
	Selection = [System.Drawing.Color]::FromArgb(9, 71, 113)     # #094771
	Critical  = [System.Drawing.Color]::FromArgb(255, 100, 100)
	Warning   = [System.Drawing.Color]::FromArgb(220, 180, 60)
	Info      = [System.Drawing.Color]::FromArgb(108, 180, 220)
	Ok        = [System.Drawing.Color]::FromArgb(78, 201, 176)
	# Syntaxfarben wie im VS-/SSMS-Dark-Theme
	SynKeyword  = [System.Drawing.Color]::FromArgb(86, 156, 214)
	SynString   = [System.Drawing.Color]::FromArgb(214, 157, 133)
	SynComment  = [System.Drawing.Color]::FromArgb(87, 166, 74)
	SynVariable = [System.Drawing.Color]::FromArgb(156, 220, 254)
	SynNumber   = [System.Drawing.Color]::FromArgb(181, 206, 168)
}

function Initialize-srgNative {
	if ('Srg.Native' -as [type]) { return }
	Add-Type -Namespace Srg -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, string lParam);
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetWindowTheme(System.IntPtr hWnd, string pszSubAppName, string pszSubIdList);
'@
}

function Set-srgDarkTitleBar($Form) {
	try {
		Initialize-srgNative
		$on = 1
		# 20 = DWMWA_USE_IMMERSIVE_DARK_MODE (Win10 2004+), 19 auf aelteren Builds
		if ([Srg.Native]::DwmSetWindowAttribute($Form.Handle, 20, [ref]$on, 4) -ne 0) {
			[void][Srg.Native]::DwmSetWindowAttribute($Form.Handle, 19, [ref]$on, 4)
		}
	} catch { }
}

function Set-srgDarkScrollBars($Control) {
	# dunkle Scrollbalken (Explorer-Dark-Theme), wirkungslos aber harmlos auf alten Windows-Versionen
	try {
		Initialize-srgNative
		if ($Control.IsHandleCreated) { [void][Srg.Native]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $null) }
		else { $Control.Add_HandleCreated({ [void][Srg.Native]::SetWindowTheme($this.Handle, 'DarkMode_Explorer', $null) }) }
	} catch { }
}

function Set-srgTheme($Control) {
	$c = $script:srgColors
	switch ($Control) {
		{ $_ -is [System.Windows.Forms.Form] } {
			$_.BackColor = $c.Bg; $_.ForeColor = $c.Text
			if ($_.IsHandleCreated) { Set-srgDarkTitleBar $_ } else { $_.Add_HandleCreated({ Set-srgDarkTitleBar $this }) }
			break
		}
		{ $_ -is [System.Windows.Forms.RichTextBox] } {
			$_.BackColor = $c.Editor; $_.ForeColor = $c.Text; $_.BorderStyle = 'None'; Set-srgDarkScrollBars $_; break
		}
		{ $_ -is [System.Windows.Forms.TextBox] } {
			$_.BackColor = $c.Surface; $_.ForeColor = $c.Text; $_.BorderStyle = 'FixedSingle'; break
		}
		{ $_ -is [System.Windows.Forms.ComboBox] } {
			$_.BackColor = $c.Surface; $_.ForeColor = $c.Text; $_.FlatStyle = 'Flat'; break
		}
		{ $_ -is [System.Windows.Forms.ListBox] } {
			$_.BackColor = $c.Editor; $_.ForeColor = $c.Text; $_.BorderStyle = 'None'; Set-srgDarkScrollBars $_; break
		}
		{ $_ -is [System.Windows.Forms.NumericUpDown] } {
			$_.BackColor = $c.Surface; $_.ForeColor = $c.Text; $_.BorderStyle = 'FixedSingle'; break
		}
		{ $_ -is [System.Windows.Forms.Button] } {
			$_.FlatStyle = 'Flat'; $_.BackColor = $c.Button; $_.ForeColor = $c.Text
			$_.FlatAppearance.BorderColor = $c.Border
			$_.FlatAppearance.MouseOverBackColor = $c.Accent
			$_.Cursor = [System.Windows.Forms.Cursors]::Hand
			break
		}
		{ $_ -is [System.Windows.Forms.CheckBox] -or $_ -is [System.Windows.Forms.RadioButton] } {
			$_.ForeColor = $c.Text; $_.BackColor = [System.Drawing.Color]::Transparent; $_.FlatStyle = 'Flat'
			$_.FlatAppearance.BorderColor = $c.Subtle
			$_.FlatAppearance.CheckedBackColor = $c.Surface
			break
		}
		{ $_ -is [System.Windows.Forms.Label] } {
			$_.ForeColor = if ($_.ForeColor -eq [System.Drawing.Color]::DimGray) { $c.Subtle } else { $c.Text }
			$_.BackColor = [System.Drawing.Color]::Transparent
			break
		}
		{ $_ -is [System.Windows.Forms.DataGridView] } {
			$_.BackgroundColor = $c.Editor; $_.ForeColor = $c.Text; $_.GridColor = $c.Border; $_.BorderStyle = 'None'
			$_.DefaultCellStyle.BackColor = $c.Editor; $_.DefaultCellStyle.ForeColor = $c.Text
			$_.DefaultCellStyle.SelectionBackColor = $c.Selection; $_.DefaultCellStyle.SelectionForeColor = $c.Text
			$_.ColumnHeadersDefaultCellStyle.BackColor = $c.Surface; $_.ColumnHeadersDefaultCellStyle.ForeColor = $c.Text
			$_.ColumnHeadersDefaultCellStyle.SelectionBackColor = $c.Surface
			$_.EnableHeadersVisualStyles = $false
			$_.ColumnHeadersBorderStyle = 'Single'
			$_.CellBorderStyle = 'SingleHorizontal'
			break
		}
		{ $_ -is [System.Windows.Forms.TabControl] } {
			# Kopfzeilen selbst zeichnen und auf volle Breite ziehen - sonst bleibt der Reiterstreifen hell
			$_.DrawMode = 'OwnerDrawFixed'
			$_.SizeMode = 'Fixed'
			$_.Add_DrawItem({ param($s, $e) Invoke-srgDrawTab $s $e })
			$_.Add_Resize({ Update-srgTabWidth $this })
			Update-srgTabWidth $_
			break
		}
		{ $_ -is [System.Windows.Forms.TabPage] } { $_.BackColor = $c.Bg; $_.ForeColor = $c.Text; break }
		{ $_ -is [System.Windows.Forms.SplitContainer] } {
			$_.BackColor = $c.Border; $_.Panel1.BackColor = $c.Bg; $_.Panel2.BackColor = $c.Bg; break
		}
		{ $_ -is [System.Windows.Forms.GroupBox] } { $_.BackColor = $c.Bg; $_.ForeColor = $c.Subtle; break }
		{ $_ -is [System.Windows.Forms.ScrollableControl] } {
			$_.BackColor = $c.Bg; $_.ForeColor = $c.Text
			if ($_.AutoScroll) { Set-srgDarkScrollBars $_ }
			break
		}
	}
	# zusammengesetzte Controls nicht zerlegen (innere Edit-Felder, Scrollbalken)
	if ($Control -is [System.Windows.Forms.NumericUpDown] -or $Control -is [System.Windows.Forms.ComboBox] -or $Control -is [System.Windows.Forms.DataGridView]) { return }
	foreach ($child in @($Control.Controls)) { Set-srgTheme $child }
}

function Update-srgTabWidth($Tabs) {
	if ($Tabs.TabCount -eq 0) { return }
	# .NET 8 (PowerShell 7) loest beim Setzen von ItemSize selbst wieder Resize aus -> Sperre
	if ($script:srgTabResizing) { return }
	$w = [math]::Max(60, [int](($Tabs.ClientSize.Width - 6) / $Tabs.TabCount))
	if ($Tabs.ItemSize.Width -eq $w) { return }
	$script:srgTabResizing = $true
	try { $Tabs.ItemSize = New-Object System.Drawing.Size($w, 26) } finally { $script:srgTabResizing = $false }
}

function Invoke-srgDrawTab($Tabs, $e) {
	if ($e.Index -lt 0) { return }
	$c = $script:srgColors
	$sel = $e.Index -eq $Tabs.SelectedIndex
	$g = $e.Graphics
	# Flaeche hinter den Reitern einmalig dunkel fuellen
	if ($e.Index -eq 0) {
		$strip = New-Object System.Drawing.SolidBrush($c.Bg)
		$g.FillRectangle($strip, 0, 0, $Tabs.Width, $e.Bounds.Bottom + 3)
		$strip.Dispose()
	}
	$back = New-Object System.Drawing.SolidBrush($(if ($sel) { $c.Surface } else { $c.Bg }))
	$g.FillRectangle($back, $e.Bounds)
	$back.Dispose()
	if ($sel) {
		$bar = New-Object System.Drawing.SolidBrush($c.Accent)
		$g.FillRectangle($bar, $e.Bounds.X, $e.Bounds.Top, $e.Bounds.Width, 2)
		$bar.Dispose()
	}
	[System.Windows.Forms.TextRenderer]::DrawText($g, $Tabs.TabPages[$e.Index].Text, $Tabs.Font, $e.Bounds,
		$(if ($sel) { $c.Text } else { $c.Subtle }),
		[System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter)
}

function Set-srgDarkToolTip($Tip) {
	$Tip.OwnerDraw = $true
	$Tip.Add_Draw({
			param($s, $e)
			$c = $script:srgColors
			$b = New-Object System.Drawing.SolidBrush($c.Surface)
			$e.Graphics.FillRectangle($b, $e.Bounds); $b.Dispose()
			$p = New-Object System.Drawing.Pen($c.Border)
			$e.Graphics.DrawRectangle($p, 0, 0, $e.Bounds.Width - 1, $e.Bounds.Height - 1); $p.Dispose()
			[System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.ToolTipText, $e.Font, $e.Bounds, $c.Text,
				[System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::WordBreak)
		})
}

function Set-srgDarkMenu($Menu) {
	$c = $script:srgColors
	$Menu.BackColor = $c.Surface
	$Menu.ForeColor = $c.Text
	$Menu.ShowImageMargin = $false
	foreach ($it in $Menu.Items) { $it.BackColor = $c.Surface; $it.ForeColor = $c.Text }
}

function Set-srgSyntaxColor {
	<# Einfache Syntaxfaerbung (VS-Dark-Farben) fuer Kommandozeile, Batch und PowerShell. #>
	param($Box, [ValidateSet('Cmd', 'PowerShell')][string]$Language = 'Cmd')
	$c = $script:srgColors
	$text = $Box.Text
	if (-not $text) { return }
	$rules = New-Object System.Collections.Generic.List[object]
	if ($Language -eq 'Cmd') {
		$rules.Add(@('(?im)^\s*(robocopy|@echo|echo|set|if|exit|chcp)\b|\b(GEQ|off)\b', $c.SynKeyword))
		$rules.Add(@('(?i)(?<=\s)/[A-Z0-9+]+(?=[:\s]|$)', $c.SynVariable))
		$rules.Add(@('%%?\w+%?', $c.SynNumber))
		$rules.Add(@('"[^"\r\n]*"', $c.SynString))
		$rules.Add(@('(?m)^::[^\n]*', $c.SynComment))
	} else {
		$rules.Add(@('(?i)\b(if|throw|else|foreach)\b|(?i)\b(New-ScheduledTask\w*|Register-ScheduledTask|Get-ScheduledTask|New-TimeSpan|Write-Host|Out-Null)\b', $c.SynKeyword))
		$rules.Add(@('(?<![\w''])-[A-Za-z]+\b', $c.Subtle))
		$rules.Add(@('\$\w+', $c.SynVariable))
		$rules.Add(@("'(?:[^']|'')*'", $c.SynString))
		$rules.Add(@('"[^"\r\n]*"', $c.SynString))
		$rules.Add(@("(?<=')/[A-Za-z0-9+]+", $c.SynVariable))
		$rules.Add(@('(?m)^#[^\n]*', $c.SynComment))
	}
	$selStart = $Box.SelectionStart
	$Box.SuspendLayout()
	$Box.SelectAll(); $Box.SelectionColor = $Box.ForeColor
	foreach ($r in $rules) {
		foreach ($m in [regex]::Matches($text, $r[0])) {
			$Box.Select($m.Index, $m.Length)
			$Box.SelectionColor = $r[1]
		}
	}
	$Box.Select([math]::Min($selStart, $text.Length), 0)
	$Box.ResumeLayout()
}
