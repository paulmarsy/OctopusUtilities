function Invoke-OctopusApi {
    param(
        [Parameter(Position=0, ValueFromRemainingArguments,ValueFromPipeline,Mandatory)]$Uri,
        [ValidateSet("Get", "Put")]$Method = "Get",
        $Body = $null
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

        Invoke-WebRequest -Uri $absoluteUri -Method $Method -Body ($Body | ConvertTo-Json -Depth 99) -Headers @{ "X-Octopus-ApiKey" = $config.ApiKey } -UseBasicParsing -ErrorAction Stop |
            % Content |
            ConvertFrom-Json |
            Write-Output
    }
}