filter Format-ScopeCompare {
    $_ | Format-Table -GroupBy Type -Property @(
        @{Name = 'Name'; Expression = { $_.Name } }
        @{Name = 'Value'; Expression = { $_.Value } })
}