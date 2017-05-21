function Copy-OctopusProjectStep {
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter()][string]$DestProject
    )

    function Update-DeploymentProcess($DeploymentProcessObject) {
        Write-Host -NoNewLine 'Commiting changes... '
        Invoke-OctopusApi -Uri $DeploymentProcessObject.Links.Self -Method Put -Body $DeploymentProcessObject | Out-Null
        Write-Host -ForegroundColor Green 'done'
    }
    function Find-AvailableName([string[]]$Names, [string]$Name) {
        $availableName = $Name
        $i = 0
        while ($Names -contains $availableName) {
            $i++
            $availableName = '{0} ({1})' -f $Name, $i
        }
        $availableName
    }
    $deploymentProcess = Get-OctopusProject $Project | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
    $stepToCopy = Select-DeploymentStep $deploymentProcess
    $stepToCopy.Id = $null
    $stepToCopy.Actions | % { $_.Id = $null }
    if ($DestProject) {
        $destDeploymentProcess = Get-OctopusProject $DestProject | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
        $stepToCopy.Name = Find-AvailableName ($destDeploymentProcess.Steps | % Name) $stepToCopy.Name
        $stepToCopy.Actions | % { $_.Name = Find-AvailableName ($destDeploymentProcess.Steps | % Actions | % Name) $_.Name }
        $destDeploymentProcess.Steps += $stepToCopy
        Update-DeploymentProcess $destDeploymentProcess
    } else {
        $stepToCopy.Name = Find-AvailableName ($deploymentProcess.Steps | % Name) $stepToCopy.Name
        $stepToCopy.Actions | % { $_.Name = Find-AvailableName ($deploymentProcess.Steps | % Actions | % Name) $_.Name }
        $deploymentProcess.Steps += $stepToCopy
        Update-DeploymentProcess $deploymentProcess
    }
}