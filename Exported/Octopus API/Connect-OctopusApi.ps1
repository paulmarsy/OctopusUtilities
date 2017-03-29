function Connect-OctopusApi {
    param(
        [Parameter(Mandatory)]$Uri,
        [Parameter(Mandatory)]$ApiKey
    )
    
    $success = $false
    try {

        $baseUri = $Uri.Trim('/')
        if ($baseUri.EndsWith('/api', [System.StringComparison]::OrdinalIgnoreCase)) { $baseUri = $baseUri.Remove($baseUri.Length-3, 3).Trim('/') }

        $ExecutionContext.SessionState.Module.PrivateData['OctopusApi'] = @{
            BaseUri = $baseUri
            ApiKey = $ApiKey
        }

        if (Invoke-OctopusApi '/' | ? Application -eq "Octopus Deploy") {
            Write-Host -ForegroundColor Green "Connection successful."
        }
    }
    catch {
        Write-Host -ForegroundColor Red "ERROR: $($_.Exception.Message)"
    }
}