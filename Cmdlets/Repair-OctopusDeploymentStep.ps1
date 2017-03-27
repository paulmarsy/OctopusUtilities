function Repair-OctopusDeploymentStep {
    param(
        [Parameter(Mandatory)]$ProjectName,
        [Parameter(Mandatory)]$ReleaseNumber,
        [Parameter(Mandatory)]$StepNumber
    )
    $project = Invoke-OctopusApi /projects/all | ? Name -eq $ProjectName
    if ($project) { Write-Host "Found project $($project.Name) ($($project.Id))" }
    else { throw "Unable to find project $ProjectName" }

    $release = Invoke-OctopusApi "$($project.Links.Self)/releases/$ReleaseNumber"
    Write-Host "Found release $($release.Version) ($($release.Id))" 

    $deploymentProcess = Invoke-OctopusApi $project.Links.DeploymentProcess 
    $StepNumber--
    Write-Host "Step: $($deploymentProcess.Steps[$StepNumber].Name)"

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