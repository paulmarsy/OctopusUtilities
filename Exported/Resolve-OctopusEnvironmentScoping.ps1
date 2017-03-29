function Resolve-OctopusEnvironmentScoping {
    param(
        [Parameter(Mandatory,Position=0)][string]$Environment,
        [Parameter(Mandatory,Position=1)][string[]]$ProjectsToCheck
    )

    $environmentId = Invoke-OctopusApi '/Environments/All' | ? Name -eq $Environment | % Id
    if ($null -eq $environmentId) {
        throw "Environment $Environment not found"
    }

    ### LifeCycles
    Write-Verbose "Retrieving lifecycles"
    Invoke-OctopusApi "/LifeCycles/All" | % {
        $lifecycleName = $_.Name
        $_.Phases
    } | ? { $environmentId -in $_.OptionalDeploymentTargets -or $environmentId -in $_.AutomaticDeploymentTargets } | % {
        [PSCustomObject]@{
            Type = "LifeCycle"
            Name = $lifecycleName
            Value = "Phase: $($_.Name)"
         }
    } | Format-ScopeCompare

    ### Machines
    Write-Verbose "Retrieving machines"
    Invoke-OctopusApi "/Machines/All" | ? { $environmentId -in $_.EnvironmentIds } | % {
        [PSCustomObject]@{
            Type = "Machine"
            Name = $_.Name
            Value = ($_.Roles -join ', ')
         }
    } | Format-ScopeCompare

    Write-Verbose "Retrieving projects"
    $libraryVariableSets = @()
    Invoke-OctopusApi "/Projects/All" | ? { $_.Name -in $ProjectsToCheck } | % {
        ### DeploymentProcess
        Write-Verbose "Retrieving $($_.Name) deployment process"
        Invoke-OctopusApi $_.Links.DeploymentProcess | % Steps | % {
            $stepName = $_.Name
            $_.Actions
        } | ? { $environmentId -in $_.Environments -or $environmentId -in $_.ExcludedEnvironments } | % { 
            [PSCustomObject]@{
                Type = "DeploymentStep"
                Name = $stepName
                Value = $_.Name
            }
        } | Format-ScopeCompare

        ### Project Variables
        Write-Verbose "Retrieving $($_.Name) variables"
        Invoke-OctopusApi $_.Links.Variables | % Variables | ? { $environmentId -in $_.Scope.Environment } | % {
            [PSCustomObject]@{
                Type = "ProjectVariable"
                Name = $_.Name
                Value = (if ($_.IsSensitive) {'**********'} else {$_.Value})
            }
        } | Format-ScopeCompare
        $_.IncludedLibraryVariableSetIds | ? { $_ -notin $libraryVariableSets } | % { $libraryVariableSets += $_ }
    }

    ### Library VariableSets
    $libraryVariableSets | % {
        Invoke-OctopusApi "/LibraryVariableSets/$_" | % {
            Write-Verbose "Retrieving $($_.Name) variableset"
            Invoke-OctopusApi $_.Links.Variables | % Variables | ? { $environmentId -in $_.Scope.Environment } | % {
                [PSCustomObject]@{
                    Type = "LibraryVariable"
                    Name = $_.Name
                    Value = (if ($_.IsSensitive) {'**********'} else {$_.Value})
                }
            } | Format-ScopeCompare
        }
    }
}