function Connect-OctopusApi {
    param(
        [Parameter(ParameterSetName = 'Module',Mandatory)]$Uri,
        [Parameter(ParameterSetName = 'Module',Mandatory)]$ApiKey,
        [Parameter(ParameterSetName = 'CloudStorage',Mandatory)][switch]$CloudStorage
    )
    
    $success = $false
    try {
        if ($CloudStorage) {
            $ExecutionContext.SessionState.Module.PrivateData['OctopusApi'] = Get-CloudStorage OctopusUtilities -Local
        } else {
            $baseUri = $Uri.Trim('/')
            if ($baseUri.EndsWith('/api', [System.StringComparison]::OrdinalIgnoreCase)) { $baseUri = $baseUri.Remove($baseUri.Length-3, 3).Trim('/') }

            $ExecutionContext.SessionState.Module.PrivateData['OctopusApi'] = @{
                BaseUri = $baseUri
                ApiKey = $ApiKey
            }
        }

        if (Invoke-OctopusApi '/' | ? Application -eq "Octopus Deploy") {
            Write-Host -ForegroundColor Green "Connection successful."
        }
        if (Get-Module CloudStorage) {
            Set-CloudStorage OctopusUtilities -Local $ExecutionContext.SessionState.Module.PrivateData['OctopusApi']
        }
    }
    catch {
        Write-Host -ForegroundColor Red "ERROR: $($_.Exception.Message)"
    }
}