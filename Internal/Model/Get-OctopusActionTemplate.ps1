function Get-OctopusActionTemplate {
    param($ActionTemplateName)
    $stepTemplate = Invoke-OctopusApi '/api/actiontemplates/all' | ? Name -eq $ActionTemplateName
    if ($stepTemplate) { Write-Host "Found step template $($stepTemplate.Name) ($($stepTemplate.Id))" }
    else { throw "Unable to find step template $ActionTemplateName" }
    return $stepTemplate
}