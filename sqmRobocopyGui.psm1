<#
	===========================================================================
	 Module Name: sqmRobocopyGui
	===========================================================================
#>

$script:srgModuleVersion = '0.1.0.0'
# zuletzt benutzte Quellen/Ziele der GUI
$script:srgConfigPath    = Join-Path $env:APPDATA 'sqmRobocopyGui\config.json'
# Zustand der (einen) offenen GUI-Instanz - Event-Handler laufen im Modul-Kontext
$script:srgUi            = $null

# Farbpalette (Private\srgTheme.ps1) braucht die Typen schon beim Laden
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$PublicPath  = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

Get-ChildItem -Path $PrivatePath -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
Get-ChildItem -Path $PublicPath -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

# Export wird ausschliesslich durch FunctionsToExport in sqmRobocopyGui.psd1 gesteuert.
