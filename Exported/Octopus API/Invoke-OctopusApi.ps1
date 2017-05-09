function Invoke-OctopusApi {
    param(
        [Parameter(Position=0,ValueFromPipeline,Mandatory)]$Uri,
        [ValidateSet('Get', 'Put','Post')]$Method = "Get",
        $Body = $null,
        [switch]$Raw
    )
    process {
        $config = $ExecutionContext.SessionState.Module.PrivateData['OctopusApi']
        if (!$config) {
            throw 'Run Connect-OctopusApi to authenticate'
        }

        if ([string]::IsNullOrWhiteSpace($Uri)) { $Uri = '/' }
        $Uri = $Uri.Trim('/')
        if ($Uri.StartsWith('api', [System.StringComparison]::OrdinalIgnoreCase)) { $Uri = $Uri.Remove(0, 3).Trim('/') }
        $absoluteUri = '{0}/api/{1}' -f $config.BaseUri, $Uri
        
        $webRequest = $null
        try {
            $webRequest = Invoke-WebRequest -Uri $absoluteUri -Method $Method -Body ($Body | ConvertTo-Json -Depth 99) -Headers @{ "X-Octopus-ApiKey" = $config.ApiKey } -UseBasicParsing -ErrorAction Stop
        } catch {
            if ($_.Exception -is [System.Net.WebException] -and $null -ne $_.Exception.Response) {
                $errorResponse = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd()
                Write-Error -Message ('ERROR: {0}' -f $errorResponse) -ErrorId NativeCommandErrorMessage
            }
            throw
        }
        if ($Raw) { $webRequest.Content | Write-Output }
        else { $webRequest.Content | ConvertFrom-Json | Write-Output }
    }
}