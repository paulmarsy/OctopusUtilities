function Select-DeploymentStep {
    param($DeploymentProcess)    
     $stepNum = 0
    Show-ChoicePrompt 'Deployment Process' 'Select step to copy' ($deploymentProcess.Steps | % {
        $stepNum++
        $step = $_ | ConvertTo-Json -Depth 10 |ConvertFrom-Json 
        [ChoiceItem]::Create($stepNum, $_.Name, $step)
        if ($_.Actions.Length -gt 1) {
            $actionNum = 0
        $_.Actions | % { 
            $actionNum++
            $step.Actions = @($_)
            [ChoiceItem]::Create("${stepNum}.${actionNum}", $_.Name, $step)
        } 
         }
    })
}