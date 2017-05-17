function Copy-OctopusDeploymentStep {
    param(
        [Parameter(Mandatory)]$ProjectName,
        [Parameter()]$DestProjectName,
        [Parameter(Mandatory)]$StepNumber
    )

    $deploymentProcess = Get-OctopusProject $ProjectName | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
    $destDeploymentProcess = Get-OctopusProject $DestProjectName | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
    Export-OctopusObject "$ProjectName DeploymentProcess" $deploymentProcess.Links.Self

    $StepNumber--
    Write-Host "Step: $($deploymentProcess.Steps[$StepNumber].Name)"

    $process.Steps | % Actions | ? { $_.Properties.'Octopus.Action.Template.Id' -eq $OldTemplate.Id } | % { 
        Write-Host "Updating $($_.Name)..."
         $_.Properties.'Octopus.Action.Template.Id' = $NewTemplate.Id
         $_.Properties.'Octopus.Action.Template.Version' = $NewTemplate.Version
    }
    Write-Host -NoNewLine 'Commiting changes... '
    Invoke-OctopusApi -Uri $process.Links.Self -Method Put -Body $process | Out-Null
    Write-Host -ForegroundColor Green 'done'



    $releaseStep = Invoke-OctopusApi $release.Links.ProjectDeploymentProcessSnapshot | % Steps | ? Name -eq $deploymentProcess.Steps[$StepNumber].Name 
    if (!$releaseStep) { throw "Unable to find deployment step in release $($release.Version)" }

    Write-Host "Current Step:`n$($deploymentProcess.Steps[$StepNumber] | ConvertTo-Json -Depth 99)`n"
    Write-Host "New Step:`n$($releaseStep | ConvertTo-Json -Depth 99)`n"

    if ($Host.UI.PromptForChoice("Confirm Update", "Are you sure?", ([System.Management.Automation.Host.ChoiceDescription[]](
        (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Update the step"),
        (New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Do not update the step")
    )), 1) -ne 0) { return }

    $preservedId = $deploymentProcess.Steps[$StepNumber].Id
    $deploymentProcess.Steps[$StepNumber] = $releaseStep
    $deploymentProcess.Steps[$StepNumber].Id = $preservedId

    $updatedDeploymentProcess = Invoke-OctopusApi $project.Links.DeploymentProcess -Method Put -Body $deploymentProcess
    Write-Host "Deployment process updated" -ForegroundColor Green
}