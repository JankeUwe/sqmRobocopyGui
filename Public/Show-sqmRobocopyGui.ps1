function Show-sqmRobocopyGui {
	<#
	.SYNOPSIS
		Startet die WinForms-Oberflaeche fuer robocopy.
	.DESCRIPTION
		Alle robocopy-Optionen in Kategorien, mit Hilfe zu jeder Option, Vorlagen, Live-Pruefung und
		sofortiger Ausgabe als Kommandozeile, Batch, PowerShell oder geplante Aufgabe. Quelle und Ziel
		per Ordnerdialog, Verlauf oder Drag & Drop aus dem Explorer. Trockenlauf (/L) und echter Lauf
		mit Live-Protokoll, Fortschritt und Exitcode-Auswertung.
	.PARAMETER Source
		Quellordner vorbelegen.
	.PARAMETER Destination
		Zielordner vorbelegen.
	.PARAMETER CommandLine
		Vorhandene robocopy-Zeile in die Felder uebernehmen.
	.PARAMETER PassThru
		Formular nur aufbauen, nicht-modal anzeigen und zurueckgeben (fuer automatisierte Tests).
	.EXAMPLE
		Show-sqmRobocopyGui
	.EXAMPLE
		Show-sqmRobocopyGui -Source D:\Daten -Destination \\nas\backup\Daten
	.EXAMPLE
		Show-sqmRobocopyGui -CommandLine 'robocopy D:\A E:\A /MIR /R:3 /W:5'
	#>
	[CmdletBinding()]
	param(
		[string]$Source,
		[string]$Destination,
		[string]$CommandLine,
		[switch]$PassThru
	)
	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing
	[System.Windows.Forms.Application]::EnableVisualStyles()

	$form = New-srgMainForm
	$ui = $script:srgUi

	$cfg = Read-srgConfig
	foreach ($s in @($cfg.Sources)) { [void]$ui.Source.Items.Add($s) }
	foreach ($d in @($cfg.Destinations)) { [void]$ui.Destination.Items.Add($d) }

	$start = @{ E = $true; R = '3'; W = '5' }
	if ($CommandLine) { $start = ConvertFrom-sqmRobocopyCommand -CommandLine $CommandLine }
	if ($Source) { $start['Source'] = $Source }
	if ($Destination) { $start['Destination'] = $Destination }
	Set-srgValues $start

	if ($PassThru) {
		$form.Show()
		[System.Windows.Forms.Application]::DoEvents()
		return $form
	}
	[void]$form.ShowDialog()
	$form.Dispose()
	$script:srgUi = $null
}
