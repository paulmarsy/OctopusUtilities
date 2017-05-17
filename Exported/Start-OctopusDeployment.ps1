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
    $machine = Invoke-OctopusApi '/api/machines/all' | ? Name -eq 'Step Template Runner'
    $Chain_CreateOption = if ($CreateRelease) { 'True' } else { 'False' }
    $Chain_SnapshotVariables = if ($UpdateSnapshot) { 'True' } else { 'False' }
    $task = Invoke-OctopusApi '/api/tasks' -Method Post -Body @{
        Name = 'AdHocScript'
        Description = "Deploy $Project release $Release to $Environment"
        Arguments =@{
            ActionTemplateId = $stepTemplate.Id
            Properties = @{
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
                Chain_DeploySchedule = $Schedule
            }
            MachineIds = @($machine.Id)
        }
    }
    $logs = [System.Collections.Generic.HashSet[string]]::new()
    $isCompleted = $false
    $status = 'Submitted'
    do {
        Start-Sleep -Seconds 1
        $details = Invoke-OctopusApi ('/api/tasks/{0}/details?verbose=false&tail=20' -f $task.Id)
        if ($status -ne $details.ActivityLogs.Status) {
            Write-Host -ForegroundColor White "$($details.Task.Description) ($($status) -> $($details.ActivityLogs.Status))"
            $status = $details.ActivityLogs.Status
        }
        foreach ($logEntry in $details.ActivityLogs.LogElements) {
            if ($logs.Add(($logEntry.OccurredAt,$logEntry.MessageText -join '/'))) {
                switch ($logEntry.Category) {
                    'Fatal' { throw $logEntry.MessageText }
                    'Error' { Write-Error -Message ('ERROR: {0}' -f $logEntry.MessageText) -ErrorId NativeCommandErrorMessage }
                    'Warning' { Write-Warning $logEntry.MessageText }
                    default { Write-Host $logEntry.MessageText }
                }
            }
        }
        Write-Host $isCompleted
    } while (!$details.Task.IsCompleted)
}