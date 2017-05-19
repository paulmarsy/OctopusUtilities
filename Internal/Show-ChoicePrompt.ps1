class ChoiceItem {
    ChoiceItem($key, $label, $value, $isDefault) {
        $this.Key = $key
        $this.Label = $label
        $this.Value = $value
        $this.IsDefault = $isDefault
    }
 [string]$Key
 [string]$Label
 [object]$Value
 [bool]$IsDefault   
 [string] GetMessage() { return ('[{0}] {1}' -f $this.Key, $this.Label) }
 static [ChoiceItem] Default([string]$key, [string]$label, [object]$value) { return [ChoiceItem]::new($key, $label, $value, $true) } 
 static [ChoiceItem] Create([string]$key, [string]$label, [object]$value) { return [ChoiceItem]::new($key, $label, $value, $false) } 
}
function Show-ChoicePrompt {
    param(
        $Caption,
        $Prompt,
        [ChoiceItem[]]$Choices
    )

    Write-Host
    Write-Host -ForegroundColor White "`t$Caption"
    $defaultKey = $null
    foreach ($item in $Choices) {
        if ($item.IsDefault) {
            Write-Host -ForegroundColor Yellow $item.GetMessage()
            $defaultKey = $item.Key
        } else {
            Write-Host $item.GetMessage()
        }
    }
    $Prompt = if ($defaultKey) { '{0} [{1}]' -f $Prompt, $defaultKey } else { $Prompt }
    $selected = $null
    do {
        $read = Read-Host -Prompt $Prompt
        $read = if ([string]::IsNullOrWhiteSpace($read)) { $defaultKey } else { $read }
        $selected = $Choices | ? Key -ieq $read | % Value
    } while ($null -eq $selected)

    return $selected
}