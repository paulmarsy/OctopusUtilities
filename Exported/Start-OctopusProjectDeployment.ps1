$StepTemplate_BaseUrl = $OctopusParameters['Octopus.Web.BaseUrl'].Trim('/')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-OctopusApi {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments, Mandatory)]$Uri,
        [ValidateSet("Get", "Post", "Put")]$Method = 'Get',
        $Body = $null,
        [switch]$NullOnError
    )
    if ([string]::IsNullOrWhiteSpace($Uri)) { $Uri = '/' }
    $absoluteUri = '{0}/{1}' -f $StepTemplate_BaseUrl, $Uri.Trim('/')

    $wait = 0
    $shouldRetry = $true
    while ($shouldRetry) {	
        try {
            $json = ConvertTo-Json -InputObject $Body -Depth 99
            if ($Method -ne 'Get') {
                Write-Verbose "$($Method.ToUpperInvariant()) $absoluteUri"
                Write-Verbose $json
            }
            Invoke-WebRequest -Uri $absoluteUri -Method $Method -Body:$json -Headers @{ "X-Octopus-ApiKey" = $StepTemplate_ApiKey } -UseBasicParsing | % Content | ConvertFrom-Json | Write-Output
            $shouldRetry = $false
        } catch {
            if (($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) -or ($NullOnError -and $_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::InternalServerError)) {
                return $null
            }
            if ($wait -eq 120) { throw $_ }
            $wait = switch ($wait) {
                0 { 30 }
                30 { 60 }
                60 { 120 }
            }
            Write-Warning "Octopus API call ($($Method.ToUpperInvariant()):$absoluteUri) failed & will be retried in $wait seconds:`n$($_.Exception.Message)"
            Start-Sleep -Seconds $wait
        }
    }
}

class DeploymentFactory {
    $BaseUrl
    DeploymentFactory($baseUrl) {
        $this.BaseUrl = $baseUrl
    }
    $Project
    [void] SetProject($projectName) {
        $this.Project = Invoke-OctopusApi /api/projects/all | ? Name -eq $projectName
        if ($null -eq $this.Project) { throw "Project $projectName not found" }
        Write-Host "Project: $($this.Project.Name)"
        Write-Verbose "`t$($this.BaseUrl)$($this.Project.Links.Self)"
    }
    $Channel
    [void] SetChannel($channelName) {
        $this.Channel = Invoke-OctopusApi $this.Project.Links.Channels | % Items | ? Name -eq $channelName
        if ($null -eq $this.Channel) { throw "Channel $channelName not found" }
        Write-Host "Channel: $($this.Channel.Name)"
        Write-Verbose "`t$($this.BaseUrl)$($this.Channel.Links.Self)"
    }
    $Release
    [void] SetRelease($releaseVersion) {
        $this.Release = Invoke-OctopusApi $this.Channel.Links.Releases | % Items | ? { ([string]::IsNullOrWhiteSpace($releaseVersion)) -or $_.Version -eq $releaseVersion } | Select-Object -First 1
        if ($null -eq $this.Release) { throw "Release $releaseVersion not found" }
        Write-Host "Release: $($this.Release.Version)"
        Write-Verbose "`t$($this.BaseUrl)/api/releases/$($this.Release.Id)"
    }
    [void] CreateRelease($releaseVersion) {
        if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
            Write-Host "Getting next version increment for channel: $($this.Channel.Name)"
            $template = Invoke-OctopusApi "$($this.Project.Links.DeploymentProcess)/template?channel=$($this.Channel.Id)"
            if (!$template.NextVersionIncrement -and $template.VersioningPackageStepName) {
                $donorPackageReference = $template.Packages | ? StepName -eq $template.VersioningPackageStepName
                $donorPackage = Invoke-OctopusApi "/api/feeds/$($donorPackageReference.FeedId)/packages?packageId=$($donorPackageReference.PackageId)&partialMatch=false&includeMultipleVersions=false&includeNotes=false&includePreRelease=true&take=1" 
                Write-Host "Found $($donorPackage.Title), version $($donorPackage.Version) published $($donorPackage.Published)"
                $releaseVersion = $donorPackage.Version
            }
            else {
                $releaseVersion = $template.NextVersionIncrement
            }
        }
        $ruleTest = Invoke-OctopusApi "/api/"
        Write-Host "Creating new release with version: $releaseVersion"
        $this.Release = Invoke-OctopusApi /api/releases -Method Post -Body @{
            ProjectId = $this.Project.Id
            Version = $releaseVersion
        }
    }
    [void] UpdateVariableSnapshot() {
        $this.Release = Invoke-OctopusApi $this.Release.Links.SnapshotVariables -Method Post
        Write-Host " `nVariables snapshot update performed. The release now references the latest variables."
    }
    $Environment
    [void] SetEnvironment($environmentName) {
        $this.Environment = Invoke-OctopusApi /api/environments/all | ? Name -eq $environmentName
        if ($null -eq $this.Environment) { throw "Environment $environmentName not found" }
        Write-Host "Environment: $($this.Environment.Name)"
        Write-Verbose "`t$($this.BaseUrl)$($this.Environment.Links.Self)"
    }
    $Tenants
    [void] SetTenants($tenantTags) {
        $encodedTags = [uri]::EscapeUriString((($tenantTags.Split("`n") | % { $_.Trim() }) -join ','))
        $this.Tenants = Invoke-OctopusApi "/api/tenants/all?projectId=$($this.Project.Id)&tags=$encodedTags" -NullOnError | ? { $_.ProjectEnvironments.$($this.Project.Id) -contains $this.Environment.Id }
        if ($null -eq $this.Tenants) { throw "Tenants for $tenantTags not found" }
        Write-Host "Tenants: $(($this.Tenants | % Name) -join ', ')"
    }
  
    [void] WriteLinks() {
		Write-Host " `nRelated Links:"
        Write-Host "`t$($this.BaseUrl)$($this.Project.Links.Web)"
        Write-Host "`t$($this.BaseUrl)$($this.Release.Links.Web)"
    }

    [Deployment] CreateDeployment() {
        Write-Verbose "Pre-Deployment Snapshots:"
        Write-Verbose "$($this.BaseUrl)$($this.Release.Links.ProjectDeploymentProcessSnapshot)"
        Write-Verbose "$($this.BaseUrl)$($this.Release.Links.ProjectVariableSnapshot)"
        $this.Release.LibraryVariableSetSnapshotIds | % { Write-Verbose "$($this.BaseUrl)/api/variables/$_" }

        return [Deployment]::new($this.BaseUrl, $this.Release, $this.Environment)
    }
}
enum GuidedFailure {
    Default
    Enabled
    Disabled
    RetryIgnore
    RetryAbort
    Ignore
}
class Deployment {
    $BaseUrl
    $DeploymentPreview
    Deployment($baseUrl, $release, $environment) {
        $this.BaseUrl = $baseUrl
        $this.Release = $release
        $this.Environment = $environment
        $this.DeploymentPreview = Invoke-OctopusApi "/api/releases/$($this.Release.Id)/deployments/preview/$($this.Environment.Id)"
        $this.FormValues = @{}
        $this.DeploymentPreview.Form.Values | Get-Member -MemberType NoteProperty | % {
            $this.FormValues.Add($_.Name, $this.DeploymentPreview.Form.Values.$($_.Name))
        }
    }
	
    $Release
    $Environment

    [string[]]$SkipActions = @()
    [void] SetStepsToSkip($stepsToSkip) {
        $comparisonArray = $stepsToSkip.Split("`n") | % Trim
        $this.SkipActions = $this.DeploymentPreview.StepsToExecute | ? {
            $_.CanBeSkipped -and ($_.ActionName -in $comparisonArray -or $_.ActionNumber -in $comparisonArray)
        } | % {
            Write-Host "Skipping Step $($_.ActionNumber): $($_.ActionName)"
            $_.ActionId
        }
    }
    [hashtable]$FormValues
    [void] SetFormValues($formValuesToSet) {
        $formValuesToSet.Split("`n") | % {
            $entry = $_.Split('=') | % Trim
            $this.DeploymentPreview.Form.Elements | ? { $_.Control.Name -ieq $entry[0] } | % {
                Write-Host "Setting Form Value '$($_.Control.Label)' to: $($entry[1])"
                $this.FormValues[$_.Name] = $entry[1]
            }
        }
    }
    [bool]$UseGuidedFailure
    [string[]]$GuidedFailureActions
    [string]$GuidedFailureMessage
    [void] SetGuidedFailure([GuidedFailure]$guidedFailure, $guidedFailureMessage) {
        $this.UseGuidedFailure = switch ($guidedFailure) {
            ([GuidedFailure]::Default) { $global:OctopusUseGuidedFailure }
            ([GuidedFailure]::Enabled) { $true }
            ([GuidedFailure]::Disabled) { $false }
            ([GuidedFailure]::RetryIgnore) { $true }
            ([GuidedFailure]::RetryAbort) { $true }
            ([GuidedFailure]::Ignore) { $true } 
        }
        Write-Host "Setting Guided Failure: $($this.UseGuidedFailure)"

        $this.GuidedFailureActions = switch ($guidedFailure) {
            ([GuidedFailure]::Default) { $null }
            ([GuidedFailure]::Enabled) { $null }
            ([GuidedFailure]::Disabled) { $null }
            ([GuidedFailure]::RetryIgnore) { @('Retry', 'Ignore') }
            ([GuidedFailure]::RetryAbort) { @('Retry', 'Abort') }
            ([GuidedFailure]::Ignore) { @('Ignore') } 
        }
        $this.GuidedFailureMessage = $guidedFailureMessage
    }

    [ServerTask] CreateServerTask() {
        return $this.CreateServerTask($null)
    }
    [ServerTask] CreateServerTask($tenant) {
        $request = @{
            ReleaseId = $this.Release.Id
            EnvironmentId = $this.Environment.Id
            SkipActions = $this.SkipActions
            FormValues = $this.FormValues
            UseGuidedFailure = $this.UseGuidedFailure
        }
        if ($tenant) { $request.Add('TenantId', $tenant.Id) }
        
        $deployment = Invoke-OctopusApi 'api/deployments' -Method Post -Body $request
        Write-Host "Queued $($deployment.Name)..."
        Write-Host "`t$($this.BaseUrl)$($deployment.Links.Web)"
        Write-Verbose "`t$($this.BaseUrl)$($deployment.Links.Self)"
        Write-Verbose "`t$($this.BaseUrl)/api/deploymentprocesses/$($deployment.DeploymentProcessId)"
        Write-Verbose "`t$($this.BaseUrl)$($deployment.Links.Variables)"
        Write-Verbose "`t$($this.BaseUrl)$($deployment.Links.Task)/details"

        return [ServerTask]::new($deployment, $tenant, $this.GuidedFailureActions, $this.GuidedFailureMessage)
    }
}

class ServerTask {
    [object]$Deployment
    [object]$Tenant
    [bool] $IsCompleted = $false
    [bool] $FinishedSuccessfully
    [string] $ErrorMessage

    hidden [string[]]$GuidedFailureActions
    hidden [string]$GuidedFailureMessage
    hidden [string]$LogPrefix
    hidden [int]$PollCount = 0
    hidden [bool]$HasInterruptions = $false
    hidden [hashtable]$TaskStatePersist = @{}
    hidden [hashtable]$TaskStatePend = @{}
 
    ServerTask($deployment, $tenant, $guidedFailureActions, $guidedFailureMessage) {
        $this.Deployment = $deployment
        $this.Tenant = $tenant
        $this.GuidedFailureActions = $guidedFailureActions
        $this.GuidedFailureMessage = $guidedFailureMessage
        if ($tenant) {
            $this.LogPrefix = "[$($tenant.Name)] "
        }
    }
    
    [void] Poll() {
        if ($this.IsCompleted) { return }
	
        $details = Invoke-OctopusApi "/api/tasks/$($this.Deployment.TaskId)/details?verbose=false&tail=20"
        $this.IsCompleted = $details.Task.IsCompleted
        $this.FinishedSuccessfully = $details.Task.FinishedSuccessfully
        $this.ErrorMessage = $details.Task.ErrorMessage

        $this.PollCount++
        if ($this.PollCount % 10 -eq 0) {
            $this.Verbose("$($details.Task.State). $($details.Task.Duration), $($details.Progress.EstimatedTimeRemaining)")
        }
        $this.LogQueuePosition($details.Task)
        
        if ($details.Task.HasPendingInterruptions) { $this.HasInterruptions = $true }
        
        $activityLogs = $this.FlattenActivityLogs($details.ActivityLogs)    
        $this.WriteLogMessages($activityLogs)
    }
	
    hidden [bool] StartState($id) {
        $exists = $this.TaskStatePersist.ContainsKey($id)
        if (!$exists) { $this.TaskStatePersist[$id] = @{} 
        }
        $this.TaskStatePend[$id] = $this.TaskStatePersist[$id].Clone()
        return !$exists
    }
    hidden [object] GetState($id, $key) {
        if ($this.TaskStatePersist.ContainsKey($id)) { return $this.TaskStatePersist[$id][$key] }
        else { return $null }
    }
    hidden [bool] SetAndCheckState($id, $key, $value) {
        $this.TaskStatePend[$id][$key] = $value
        if ($this.TaskStatePersist.ContainsKey($id)) { return $this.TaskStatePersist[$id][$key] -ine $this.TaskStatePend[$id][$key] }
        else { return $true }
    }
    hidden [void] ResetState($id, $key) {
        if ($this.TaskStatePersist.ContainsKey($id)) { $this.TaskStatePersist[$id].Remove($key) }
        if ($this.TaskStatePend.ContainsKey($id)) { $this.TaskStatePend[$id].Remove($key) }
    }
    hidden [void] CommitState($id) {
        $this.TaskStatePersist[$id] = $this.TaskStatePend[$id]
        $this.TaskStatePend.Remove($id)
    }

    hidden [void] Error($message) { Write-Host "##octopus[stdout-error]`n$($this.LogPrefix)${message}`n##octopus[stdout-default]" }
    hidden [void] Warn($message) { Write-Host "##octopus[stdout-warning]`n$($this.LogPrefix)${message}`n##octopus[stdout-default]" }
    hidden [void] Host($message) { Write-Host "##octopus[stdout-default]`n$($this.LogPrefix)${message}`n##octopus[stdout-default]" }   
    hidden [void] Verbose($message) { Write-Host "##octopus[stdout-verbose]`n$($this.LogPrefix)${message}`n##octopus[stdout-default]" }

    hidden [psobject[]] FlattenActivityLogs($ActivityLogs) {
        return $this.FlattenActivityLogs($ActivityLogs, $null, {@()}.Invoke())
    }
    hidden [psobject[]] FlattenActivityLogs($ActivityLogs, $Parent, $IntoArray) {
        $ActivityLogs | % {
            $log = $_
            $log | Add-Member -MemberType NoteProperty -Name Parent -Value $Parent
            $insertBefore = $null -eq $log.Parent -and $log.Status -eq 'Running'	
            if ($insertBefore) { $IntoArray.Add($log) }
            $_.Children | % { $this.FlattenActivityLogs($_, $log, $IntoArray) }
            if (!$insertBefore) { $IntoArray.Add($log) }
        }
        return $IntoArray
    }
    hidden [void] LogQueuePosition($Task) {
        if ($Task.HasBeenPickedUpByProcessor) {
            $this.ResetState($Task.Id, 'QueuePosition')
            return
        }
		
        $this.StartState($Task.Id)
        $queuePosition = (Invoke-OctopusApi "/api/tasks/$($this.Deployment.TaskId)/queued-behind").Items.Count
        if ($this.SetAndCheckState($Task.Id, 'QueuePosition', $queuePosition) -and $queuePosition -ne 0) {
            $this.Host("Queued behind $queuePosition tasks...")
        }
        $this.CommitState($Task.Id)
    }
    hidden [void] WriteLogMessages($ActivityLogs) {
        $interrupts = if ($this.HasInterruptions) {
            Invoke-OctopusApi "/api/interruptions?regarding=$($this.Deployment.TaskId)" | % Items
        }
        foreach ($activity in $ActivityLogs) {
            $this.StartState($activity.Id)
            $correlatedInterrupts = $interrupts | ? CorrelationId -eq $activity.Id         
            $correlatedInterrupts | ? IsPending -eq $false | % { $this.LogInterruptMessages($activity, $_) }

            $this.LogStepTransition($activity)         
            $this.LogErrorsAndWarnings($activity)
            $correlatedInterrupts | ? IsPending -eq $true | % { 
                $this.LogInterruptMessages($activity, $_)
                $this.HandleInterrupt($_)
            }
            
            $this.CommitState($activity.Id)
        }
    }
    hidden [void] LogStepTransition($ActivityLog) {
        if ($ActivityLog.ShowAtSummaryLevel -and $this.SetAndCheckState($ActivityLog.Id, 'Status', $ActivityLog.Status) -and $ActivityLog.Status -ne 'Pending') {
            $existingState = $this.GetState($ActivityLog.Id, 'Status')
            $existingStateText = if ($existingState) {  "$existingState -> " }
            $this.Host("$($ActivityLog.Name) ($existingStateText$($ActivityLog.Status))")
        }
    }
    hidden [void] LogErrorsAndWarnings($ActivityLog) {
        $ActivityLog.LogElements | ? Category -ne 'Info' | % {
            $log = $_
            if ($this.SetAndCheckState($ActivityLog.Id, $log.OccurredAt, $log.MessageText)) {
                switch ($log.Category) {
                    'Fatal' {
                        if ($ActivityLog.Parent) {
                            $this.Error("FATAL: During $($ActivityLog.Parent.Name)")
                            $this.Error("FATAL: $($log.MessageText)")
                        }
                    }
                    'Error' { $this.Error("[$($ActivityLog.Parent.Name)] $($log.MessageText)") }
                    'Warning' { $this.Warn("[$($ActivityLog.Parent.Name)] $($log.MessageText)") }
                }
            }
        }
    }
    hidden [void] LogInterruptMessages($ActivityLog, $Interrupt) {
        $message = $Interrupt.Form.Elements | ? Name -eq Instructions | % Control | % Text
        if ($this.StartState($Interrupt.Id)) {
            $this.Warn("Deployment is paused at '$($ActivityLog.Parent.Name)' for manual intervention: $message")
        }
        if ($this.SetAndCheckState($Interrupt.Id, 'ResponsibleUserId', $Interrupt.ResponsibleUserId)) {
            $user = Invoke-OctopusApi $Interrupt.Links.User
            $this.Warn("$($user.DisplayName) ($($user.EmailAddress)) has taken responsibility for the manual intervention")
        }
        if ($null -ne ($Interrupt.Form.Elements | ? Name -eq Result)) {
            $action = $Interrupt.Form.Values.Result
            if ($this.SetAndCheckState($Interrupt.Id, 'Action', $action)) {
                $this.Warn("Manual intervention action '$action' submitted with notes: $($Interrupt.Form.Values.Notes)")
            }
        }
        if ($null -ne ($Interrupt.Form.Elements | ? Name -eq Guidance)) {
            $action = $Interrupt.Form.Values.Guidance
            if ($this.SetAndCheckState($Interrupt.Id, 'Action', $action)) {
                $this.Warn("Failure guidance to '$action' submitted with notes: $($Interrupt.Form.Values.Notes)")
            }
        }
        $this.CommitState($Interrupt.Id)
    }
    hidden [void] HandleInterrupt($Interrupt) {
        $isGuidedFailure = $null -ne ($Interrupt.Form.Elements | ? Name -eq Guidance)
        if (!$isGuidedFailure -or !$this.GuidedFailureActions -or !$Interrupt.IsPending) {
            return
        }
        $id = @($Interrupt.CorrelationId, 'AutoGuidance') -join '/'
        if ($this.StartState($id)) {
            $this.SetAndCheckState($id, 'ActionIndex', 0)
        }
        if ($Interrupt.CanTakeResponsibility -and $null -eq $Interrupt.ResponsibleUserId) {
            Invoke-OctopusApi $Interrupt.Links.Responsible -Method Put
        }
        if ($Interrupt.HasResponsibility) {
            $guidanceIndex = $this.GetState($id, 'ActionIndex')
            $guidance = $this.GuidedFailureActions[$guidanceIndex]
            $guidanceIndex++
            
            Invoke-OctopusApi $Interrupt.Links.Submit -Body @{
                Notes = $this.GuidedFailureMessage.Replace('#{GuidedFailureActionIndex}', $guidanceIndex).Replace('#{GuidedFailureAction}', $guidance)
                Guidance = $guidance
            } -Method Post

            $this.SetAndCheckState($id, 'ActionIndex', $guidanceIndex)
        }
        $this.CommitState($id)
    }
}

function Show-Heading {
    param($Text)
    $padding = ' ' * ((80 - 2 - $Text.Length) / 2)
    Write-Host " `n"
    Write-Host (@(("`t "), ([string][char]0x2554), (([string][char]0x2550) * 80), ([string][char]0x2557)) -join '')
    Write-Host "`t" "$(([string][char]0x2551))$padding $Text $padding$([string][char]0x2551)"  
    Write-Host (@(("`t "), ([string][char]0x255A), (([string][char]0x2550) * 80), ([string][char]0x255D)) -join '')
    Write-Host " `n"
}

if (!$OctopusParameters['Octopus.Action.RunOnServer']) {
    Write-Warning "For optimal performance use 'Run On Server' for this action"
}

Show-Heading 'Getting Deployment Context'
$deploymentFactory = [DeploymentFactory]::new($StepTemplate_BaseUrl)
$deploymentFactory.SetProject($StepTemplate_Project)
$deploymentFactory.SetChannel($StepTemplate_Channel)
if ($StepTemplate_CreateNewRelease -ieq 'True') {
    $deploymentFactory.CreateRelease($StepTemplate_Release)
}
else {
    $deploymentFactory.SetRelease($StepTemplate_Release)
}
$deploymentFactory.SetEnvironment($StepTemplate_Environment)
if (![string]::IsNullOrWhiteSpace($StepTemplate_TenantTags)) {
    $deploymentFactory.SetTenants($StepTemplate_TenantTags)
}
if ($StepTemplate_SnapshotVariables -ieq 'True') {
    $deploymentFactory.UpdateVariableSnapshot()
}
$deploymentFactory.WriteLinks()

Show-Heading 'Configuring Deployment'
$deployment = $deploymentFactory.CreateDeployment()
if (![string]::IsNullOrWhiteSpace($StepTemplate_StepsToSkip)) {
    $deployment.SetStepsToSkip($StepTemplate_StepsToSkip)
}
if (![string]::IsNullOrWhiteSpace($StepTemplate_FormValues)) {
    $deployment.SetFormValues($StepTemplate_FormValues)
}
$guidedFailureMessage = $OctopusParameters['Octopus.Actions.GuidedFailureMessage']
if ([string]::IsNullOrWhiteSpace($guidedFailureMessage)) {
    if ([string]::IsNullOrWhiteSpace($OctopusParameters['Octopus.Deployment.CreatedBy.EmailAddress'])) {
        $email = $null
    }
    else {
        $email = "($($OctopusParameters['Octopus.Deployment.CreatedBy.EmailAddress']))"
    }
    $guidedFailureMessage = @"
Automatic Failure Guidance will #{GuidedFailureAction} (###{GuidedFailureActionIndex})
Origin Deployment: $($OctopusParameters['Octopus.Task.Name'])
Deploying User: $($OctopusParameters['Octopus.Deployment.CreatedBy.DisplayName']) $email
$($OctopusParameters['Octopus.Web.BaseUrl'])$($OctopusParameters['Octopus.Web.DeploymentLink'])
"@
}
$deployment.SetGuidedFailure($StepTemplate_GuidedFailure, $guidedFailureMessage)

Show-Heading 'Queue Deployment'
$tasks = @()
if ([string]::IsNullOrWhiteSpace($StepTemplate_TenantTags)) {
    Write-Host 'Queueing untenanted deployment...'
    $tasks += $deployment.CreateServerTask()
}
else {
    Write-Host 'Queueing tenant deployments...'
    $deploymentFactory.Tenants | ? { $null -ne $_ } | % {
        $tasks += $deployment.CreateServerTask($_)
    }
}

if (!$StepTemplate_WaitForDeployment) {
    Write-Host "WaitForDeployment is False, proceeding to next deployment step"
    return
}

Show-Heading 'Waiting For Deployment'
$tasksStillRunning = $true
while ($tasksStillRunning) {
    Start-Sleep -Seconds 1
    $tasksStillRunning = $false
    foreach ($task in $tasks) {
        $task.Poll()
        if (!$task.IsCompleted) { $tasksStillRunning = $true }
    }
}
if ($tasks | ? FinishedSuccessfully -eq $false) {
    Show-Heading 'Deployment Error'
    Write-Error (($tasks | % ErrorMessage) -join "`n") -ErrorAction Stop
}

if ([string]::IsNullOrWhiteSpace($StepTemplate_PostDeploy)) {
    return 
}
Show-Heading 'Post-Deploy Script'
$rawPostDeployScript = Invoke-OctopusApi "/api/releases/$($OctopusParameters['Octopus.Release.Id'])" |
    % { Invoke-OctopusApi $_.Links.ProjectDeploymentProcessSnapshot } |
    % Steps | ? Id -eq $OctopusParameters['Octopus.Step.Id'] |
    % Actions | ? Id -eq $OctopusParameters['Octopus.Action.Id'] |
    % { $_.Properties.StepTemplate_PostDeploy }
Write-Verbose "Raw Post-Deploy Script:`n$rawPostDeployScript"

Add-Type -Path (Get-WmiObject Win32_Process | ? ProcessId -eq $PID | % { Get-Process -Id $_.ParentProcessId } | % { Join-Path (Split-Path -Path $_.Path -Parent) 'Octostache.dll' })

$tasks | % {
    $deployment = $_.Deployment
    $tenant = $_.Tenant
    $variablesDictionary = [Octostache.VariableDictionary]::new()
    Invoke-OctopusApi "/api/variables/$($_.Deployment.ManifestVariableSetId)" | % Variables | ? {
        ($_.IsSensitive -eq $false) -and `
        ($_.Scope.Private -ne 'True') -and `
		($null -eq $_.Scope.Action) -and `
		($null -eq $_.Scope.Machine) -and `
        ($null -eq $_.Scope.TargetRole) -and `
		($null -eq $_.Scope.Role) -and `
        ($null -eq $_.Scope.Tenant -or $_.Scope.Tenant -contains $tenant.Id) -and `
		($null -eq $_.Scope.TenantTag -or $_.Scope.TenantTag -in $tenant.TenantTags) -and `
        ($null -eq $_.Scope.Environment -or $_.Scope.Environment -contains $deployment.EnvironmentId) -and `
		($null -eq $_.Scope.Channel -or $_.Scope.Channel -contains $deployment.ChannelId) -and `
		($null -eq $_.Scope.Project -or $_.Scope.Project -contains $deployment.ProjectId)
    } | % { $variablesDictionary.Set($_.Name, $_.Value) }
    $postDeployScript = $variablesDictionary.Evaluate($rawPostDeployScript)
    Write-Host "$($_.LogPrefix)Evaluated Post-Deploy Script:"
    Write-Host $postDeployScript
    Write-Host "Script output:"
    [scriptblock]::Create($postDeployScript).Invoke()
}
