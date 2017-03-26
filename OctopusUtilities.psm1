Get-ChildItem -File -Filter *.ps1 -Path (Join-Path $PSScriptRoot 'Cmdlets') -Recurse | % {
	. "$($_.FullName)"	
	Export-ModuleMember -Function $_.BaseName
}