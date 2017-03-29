filter Format-ScopeCompare {
    $_ | Format-Table -GroupBy Type -Property @(
        @{Name = 'Container'; Expression = { if ($_.Type -eq 'VariableSet') {'{0} ({1})' -f $_.OwnerName, $_.OwnerType} else {$_.OwnerName} }; Width = 50 }
        @{Name = 'Name'; Expression = { $_.Name } }
        @{Name = 'Version'; Expression = { $_.Version } }
        @{Name = 'Value'; Expression = { $_.Value } })
}