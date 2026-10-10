function ConvertFrom-sqmRobocopyExitCode {
	<#
	.SYNOPSIS
		Uebersetzt einen robocopy-Exitcode (Bitmaske) in Klartext.
	.DESCRIPTION
		0-7 = Erfolg (1 kopiert, 2 zusaetzliche Dateien im Ziel, 4 Mismatch), ab 8 = Fehler.
		Praktisch nach "& robocopy.exe ..." oder fuer das Ergebnis einer geplanten Aufgabe.
	.EXAMPLE
		robocopy D:\A D:\B /E; ConvertFrom-sqmRobocopyExitCode $LASTEXITCODE
	#>
	[CmdletBinding()]
	param([Parameter(Mandatory, Position = 0, ValueFromPipeline)][int]$ExitCode)
	process {
		[pscustomobject]@{
			ExitCode = $ExitCode
			Success  = $ExitCode -ge 0 -and $ExitCode -lt 8
			Copied   = [bool]($ExitCode -band 1) -and $ExitCode -ge 0
			Text     = Get-srgExitCodeText $ExitCode
		}
	}
}
