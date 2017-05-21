$script:ProgressPreference = 'SilentlyContinue'

Get-ChildItem -File -Filter *.ps1 -Path (Join-Path $PSScriptRoot 'Internal') -Recurse | % {
	. $_.FullName
}
Get-ChildItem -File -Filter *.ps1 -Path (Join-Path $PSScriptRoot 'Exported') -Recurse | % {
	. $_.FullName
	Export-ModuleMember -Function $_.BaseName
}