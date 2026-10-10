<#
	===========================================================================
	 Module Manifest
	-------------------------------------------------------------------------
	 Module Name: sqmRobocopyGui
	===========================================================================
#>

@{
	RootModule			   = 'sqmRobocopyGui.psm1'
	ModuleVersion		   = '0.1.0.0'
	GUID				   = '40d407ca-5aef-4bb7-92c5-8ed874f3b7a1'
	Author				   = 'Uwe Janke'
	CompanyName		       = 'dtcSoftware'
	Copyright			   = '(c) 2026 Uwe Janke. MIT License.'
	Description		       = 'Dark WinForms GUI for robocopy with all options: folder and file pickers, drag and drop, presets, live validation, import of existing command lines and .RCJ job files, output as command line, batch, PowerShell or scheduled task, dry run (/L) and live run with progress.'
	PowerShellVersion	   = '5.1'
	DotNetFrameworkVersion = '4.5'
	CLRVersion			   = '4.0'
	ProcessorArchitecture  = 'None'

	FunctionsToExport	   = @(
		'Show-sqmRobocopyGui'
		'New-sqmRobocopyCommand'
		'Test-sqmRobocopyParameter'
		'ConvertFrom-sqmRobocopyCommand'
		'ConvertFrom-sqmRobocopyExitCode'
	)
	CmdletsToExport	       = @()
	VariablesToExport	   = @()
	AliasesToExport	       = @()

	PrivateData		       = @{
		PSData = @{
			Tags	   = @('robocopy', 'Copy', 'Backup', 'Mirror', 'GUI', 'WinForms', 'Windows')
			LicenseUri = 'https://github.com/JankeUwe/sqmRobocopyGui/blob/main/LICENSE'
			ProjectUri = 'https://github.com/JankeUwe/sqmRobocopyGui'
		}
	}
}
