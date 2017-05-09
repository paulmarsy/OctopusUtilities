function Switch-OctopusProjectStepTemplate {
    param(
        [Parameter(Mandatory)]$ProjectName,
        [Parameter(Mandatory)]$OldTemplateName,
        [Parameter(Mandatory)]$NewTemplateName
    )
    $OldTemplate = Get-OctopusActionTemplate $OldTemplateName
    $NewTemplate = Get-OctopusActionTemplate $NewTemplateName
    
    $process = Get-OctopusProject $ProjectName | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
    Export-OctopusObject "$ProjectName DeploymentProcess" $process.Links.Self
    $process.Steps | % Actions | ? { $_.Properties.'Octopus.Action.Template.Id' -eq $OldTemplate.Id } | % { 
        Write-Host "Updating $($_.Name)..."
         $_.Properties.'Octopus.Action.Template.Id' = $NewTemplate.Id
         $_.Properties.'Octopus.Action.Template.Version' = $NewTemplate.Version
    }
    Write-Host -NoNewLine 'Commiting changes... '
    Invoke-OctopusApi -Uri $process.Links.Self -Method Put -Body $process | Out-Null
    Write-Host -ForegroundColor Green 'done'
}