# Strict-mode tests for _shared/company.ps1: blank input keeps the step's Company, matching by external id,
# name and alias, and refusing no match, several matches, or a step without Include all companies.
. (Join-Path $PSScriptRoot 'mock.ps1')

Invoke-WithLib @('company.ps1') {
    $log = New-Object System.Collections.ArrayList
    function Set-DefaultCompany { param([string]$Company, [string]$Source) $null = $log.Add($Company) }

    # No $companies yet: blank input is fine, a named company isn't.
    $r = Select-RunCompany ''
    Check 'blank: keeps the step''s own Company' ($r.selected -eq $false -and $log.Count -eq 0 -and $r.how -match 'own Company') ($r | ConvertTo-Json -Compress)
    $r = Select-RunCompany '   '
    Check 'whitespace counts as blank' ($r.selected -eq $false) ($r | ConvertTo-Json -Compress)
    $m = Get-ThrowMessage { Select-RunCompany 'Contoso' }
    Check 'named company without Include all companies throws' ($m -match 'Include all companies' -and $log.Count -eq 0) $m

    $companies = @(
        [pscustomobject]@{ externalId = '29684092'; secretSuffix = $null; name = 'Contoso Ltd'; aliases = @('Contoso', 'CON-189'); secretPolicies = @() },
        [pscustomobject]@{ externalId = 'Fabrikam'; secretSuffix = 'fabrikam'; name = 'Fabrikam Inc'; aliases = $null; secretPolicies = @() },
        [pscustomobject]@{ externalId = 'Example MSP'; secretSuffix = 'example-msp'; name = 'Fabrikam Inc'; aliases = @(); secretPolicies = @() },
        @{ externalId = 'NW-1'; name = 'Northwind Traders'; aliases = 'Northwind' }
    )

    $r = Select-RunCompany '29684092'
    Check 'external id: switches to that company' ($r.selected -and $r.externalId -eq '29684092' -and $r.name -eq 'Contoso Ltd' -and $log[-1] -eq '29684092') ($r | ConvertTo-Json -Compress)
    $r = Select-RunCompany '  contoso ltd '
    Check 'name: trimmed and case-insensitive' ($r.externalId -eq '29684092' -and $log[-1] -eq '29684092') ($r | ConvertTo-Json -Compress)
    $r = Select-RunCompany 'con-189'
    Check 'alias: matches' ($r.externalId -eq '29684092') ($r | ConvertTo-Json -Compress)
    $r = Select-RunCompany 'Northwind'
    Check 'hashtable company with a single-string alias' ($r.externalId -eq 'NW-1' -and $r.name -eq 'Northwind Traders') ($r | ConvertTo-Json -Compress)
    $r = Select-RunCompany 'fabrikam'
    Check 'external id wins over a duplicate name' ($r.externalId -eq 'Fabrikam' -and $log[-1] -eq 'Fabrikam') ($r | ConvertTo-Json -Compress)

    $before = $log.Count
    $m = Get-ThrowMessage { Select-RunCompany 'Fabrikam Inc' }
    Check 'two companies with the same name: throws and lists both' ($m -match 'matches 2' -and $m -match 'Example MSP' -and $m -match 'external id' -and $log.Count -eq $before) $m
    $m = Get-ThrowMessage { Select-RunCompany 'Tailspin Toys' }
    Check 'no match: throws without switching' ($m -match "No AutomationAI company matches 'Tailspin Toys'" -and $log.Count -eq $before) $m
}

Complete-Test
