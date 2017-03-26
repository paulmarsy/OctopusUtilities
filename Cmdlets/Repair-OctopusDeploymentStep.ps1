function Repair-OctopusDeploymentStep {
    param(
        [Parameter(Mandatory)]$ProjectName,
        [Parameter(Mandatory)]$ReleaseNumber    
    )
    $project = Invoke-OctopusApi /projects/all | ? Name -eq $ProjectName
    if ($project) { Write-Host "Found project $($project.Name) ($($project.Id))" }
    else { throw "Unable to find project $ProjectName" }

    $release = Invoke-OctopusApi "$($project.Links.Self)/releases/$ReleaseNumber"
    Write-Host "Found release $($release.Version) ($($release.Id))" 

    $deploymentProcess = Invoke-OctopusApi $project.Links.DeploymentProcess
    
    $i = 0
    $choice = $Host.UI.PromptForChoice("Deployment Step", "Select Deployment Step to change", ([System.Management.Automation.Host.ChoiceDescription[]]($deploymentProcess.Steps | % {
        $i++
        New-Object System.Management.Automation.Host.ChoiceDescription "&$i $($_.Name)"
    })), -1)
    $stepId = $deploymentProcess.Steps[$choice].Id

    $releaseStep = Invoke-OctopusApi $release.Links.ProjectDeploymentProcessSnapshot | % Steps | ? Id -eq $stepId
    if (!$releaseStep) { throw "Unable to find deployment step ($stepId) in release $($release.Version)" }

    Write-Host "Current Step:`n$($deploymentProcess.Steps[$choice] | ConvertTo-Json -Depth 99)`n"
    Write-Host "New Step:`n$($releaseStep | ConvertTo-Json -Depth 99)`n"

    if ($Host.UI.PromptForChoice("Confirm Update", "Are you sure?", ([System.Management.Automation.Host.ChoiceDescription[]](
        (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Update the step"),
        (New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Do not update the step")
    )), 1) -ne 0) { return }

    $deploymentProcess.Steps[$choice] = $releaseStep
    $updatedDeploymentProcess = Invoke-OctopusApi $project.Links.DeploymentProcess -Method Put -Body $deploymentProcess
    Write-Host "Deployment process updated" -ForegroundColor Green
}