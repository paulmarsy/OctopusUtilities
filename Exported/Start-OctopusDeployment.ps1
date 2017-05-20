function Start-OctopusDeployment {
    param(
        [Parameter(Mandatory)]$Project,
        $Channel,
        $Release,
        [switch]$CreateRelease,
        [switch]$UpdateSnapshot,
        [Parameter(Mandatory)]$Environment,
        $Tenant,
        $FormValues,
        $SkipSteps,
        $Schedule = 'WaitForDeployment'
    )

    $stepTemplate = Get-OctopusActionTemplate 'Chain Deployment'
    $environmentId = Invoke-OctopusApi '/api/environments/all' | ? Name -ieq $Environment | % Id
    
    $machine = Invoke-OctopusApi '/api/machines/all' | ? { $_.EnvironmentIds -contains $environmentId -and $_.IsInProcess -eq $false -and $_.IsDisabled -eq $false } | Select-Object -First 1
    Write-Verbose "Will run on $($machine.Name)" -Verbose
    $Chain_CreateOption = if ($CreateRelease) { 'True' } else { 'False' }
    $Chain_SnapshotVariables = if ($UpdateSnapshot) { 'True' } else { 'False' }
    $task = Invoke-OctopusApi '/api/tasks' -Method Post -Body @{
        Name = 'AdHocScript'
        Description = "Deploy $Project release $Release to $Environment"
        Arguments =@{
            ActionTemplateId = $stepTemplate.Id
            Properties = @{
                'Octopus.Web.BaseUrl' = $ExecutionContext.SessionState.Module.PrivateData['OctopusApi'].BaseUri
                Chain_ApiKey = @{ NewValue = $ExecutionContext.SessionState.Module.PrivateData['OctopusApi'].ApiKey }
                Chain_ProjectName = $Project
                Chain_Channel = $Channel
                Chain_ReleaseNum = $Release
                Chain_CreateOption = $Chain_CreateOption
                Chain_SnapshotVariables = $Chain_SnapshotVariables
                Chain_DeployTo = $Environment
                Chain_Tenants = $Tenant
                Chain_FormValues = $FormValues
                Chain_StepsToSkip = $SkipSteps
                Chain_GuidedFailure = 'Disabled'
                Chain_DeploySchedule = $Schedule
            }
            MachineIds = @($machine.Id)
        }
    }
    
    $logs = [System.Collections.Generic.HashSet[string]]::new()
    $isCompleted = $false
    $status = 'Submitted'
    do {
        Start-Sleep -Milliseconds 100
        $details = Invoke-OctopusApi ('/api/tasks/{0}/details?verbose=false&tail=20' -f $task.Id)
        if ($status -ne $details.ActivityLogs.Status) {
            Write-Host -ForegroundColor White "$($details.Task.Description) ($($status) -> $($details.ActivityLogs.Status))"
            $status = $details.ActivityLogs.Status
        }
        foreach ($logEntry in $details.ActivityLogs.Children.LogElements) {
            if ($logs.Add(($logEntry.OccurredAt,$logEntry.MessageText -join '/'))) {
                if ($logEntry.MessageText -like '* additional lines not shown') { continue }
                switch ($logEntry.Category) {
                    'Fatal' { Write-Host -ForegroundColor DarkRed ('FATAL: {0}' -f $logEntry.MessageText) }
                    'Error' { Write-Host -ForegroundColor Red ('ERROR: {0}' -f $logEntry.MessageText) }
                    'Warning' { Write-Host -ForegroundColor Yellow ('WARNING: {0}' -f $logEntry.MessageText) }
                    default { Write-Host $logEntry.MessageText }
                }
            }
        }
    } while (!$details.Task.IsCompleted)
}