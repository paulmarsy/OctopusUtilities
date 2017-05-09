function Switch-OctopusProjectStepTemplate {
    param(
        [Parameter(Mandatory)]$ProjectName,
        [Parameter(Mandatory)]$OldTemplate,
        [Parameter(Mandatory)]$NewTemplate
    )
    $process = Get-OctopusProject $ProjectName | % { Invoke-OctopusApi $_.Links.DeploymentProcess }
    $process.Steps | % Actions | ? { $_.Properties.'Octopus.Action.Template.Id' -eq $OldTemplateId } | % { 
        Write-Host "Updating $($_.Name)..."
         $_.Properties.'Octopus.Action.Template.Id' = $NewTemplateId
    }
    Write-Host -NoNewLine 'Commiting changes... '
    Invoke-OctopusApi -Uri $process.Links.Self -Method Put -Body $process | Out-Null
    Write-Host -ForegroundColor Green 'done'
}