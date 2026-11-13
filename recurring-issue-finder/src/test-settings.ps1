# Strict-mode harness for settings.ps1. Runs the step the way the runner does: a child scope
# through [scriptblock]::Create, never dot-sourced.
#   pwsh -NoProfile -File recurring-issue-finder/src/test-settings.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script = Get-Content -Raw (Join-Path $PSScriptRoot 'settings.ps1')
$state = @{ pass = 0; fail = 0 }

function Invoke-Step {
    param($Input1)
    $global:RifIn = $Input1
    $global:RifOut = $null
    function global:Get-NodeInput { return $global:RifIn }
    function global:Set-NodeOutput { param($o) $global:RifOut = $o }
    & ([scriptblock]::Create($script))
    return $global:RifOut
}

function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { $state.pass += 1; Write-Host "PASS $Name" } else { $state.fail += 1; Write-Host "FAIL $Name" }
}

$o = Invoke-Step $null
Check 'no input uses defaults' ($o.lookback_days -eq 30 -and $o.min_tickets -eq 3 -and $o.max_proposals -eq 3 -and @($o.warnings).Count -eq 0)
Check 'request names the date' ($o.request -match 'Today is \d{4}-\d{2}-\d{2}')

$o = Invoke-Step ([pscustomobject]@{ lookback_days = 14; min_tickets = '4'; max_proposals = 2 })
Check 'object input is read' ($o.lookback_days -eq 14 -and $o.min_tickets -eq 4 -and $o.max_proposals -eq 2)
Check 'request carries the values' ($o.request -match 'last 14 days' -and $o.request -match 'at most 2')

$o = Invoke-Step '{"lookback_days": 200, "max_proposals": "lots"}'
Check 'bad values fall back with warnings' ($o.lookback_days -eq 30 -and $o.max_proposals -eq 3 -and @($o.warnings).Count -eq 2)

$o = Invoke-Step @{ trigger = @{ min_tickets = 5 } }
Check 'trigger envelope is unwrapped' ($o.min_tickets -eq 5)

$o = Invoke-Step 'run it'
Check 'plain text input uses defaults' ($o.status -eq 'success' -and $o.lookback_days -eq 30)

Write-Host "$($state.pass) passed, $($state.fail) failed"
if ($state.fail -gt 0) { exit 1 }
