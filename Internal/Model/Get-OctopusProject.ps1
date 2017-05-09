function Get-OctopusProject {
    param($ProjectName)
    $project = Invoke-OctopusApi '/api/projects/all' | ? Name -eq $ProjectName
    if ($project) { Write-Host "Found project $($project.Name) ($($project.Id))" }
    else { throw "Unable to find project $ProjectName" }
    return $project
}