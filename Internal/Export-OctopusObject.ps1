function Export-OctopusObject {
    param(
        [Parameter(Position=0,Mandatory)]$Name,
        [Parameter(Position=1,Mandatory)]$Uri
    )
    Write-Host -NoNewLine "Exporting $Name... "
    Invoke-OctopusApi -Uri $Uri -Raw | Set-Content ('{0}.json' -f $Name) -Encoding UTF8
    Write-Host -ForegroundColor Green 'done'
}