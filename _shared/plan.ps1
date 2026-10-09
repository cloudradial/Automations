# ---------- _shared/plan.ps1: preview first, change on confirm ----------
# Edit this file, then run: node _shared/inject.js <automation-folder>
# AutomationAI has no approval step, so every automation that writes builds a plan:
#   $plan = New-ChangePlan 'Offboard sam@contoso.com'
#   Add-PlannedChange $plan 'Block sign-in' { param($u) Set-GraphAccountEnabled $u $false } -Arguments @($userId)
#   $result = Invoke-ChangePlan $plan -Confirm:$confirm
# Without confirm nothing runs and the result is a preview. With confirm the changes run in order
# and stop at the first failure, and the result says what ran and what didn't.
# Pass loop values through -Arguments: a scriptblock reads variables when it runs, not when it was added.
# Don't use .GetNewClosure() either; a closure can't see functions defined in the step.

function New-ChangePlan {
    param([string]$Title = '')
    return @{ title = $Title; changes = (New-Object System.Collections.ArrayList) }
}

function Add-PlannedChange {
    param($Plan, [string]$Description, [scriptblock]$Action, [object[]]$Arguments = @())
    if ($null -eq $Plan -or -not ($Plan -is [System.Collections.IDictionary]) -or -not $Plan.Contains('changes')) { throw 'Add-PlannedChange needs a plan from New-ChangePlan.' }
    if ([string]::IsNullOrWhiteSpace($Description)) { throw 'Each planned change needs a description.' }
    if ($null -eq $Action) { throw "Planned change '$Description' has no scriptblock." }
    $null = $Plan.changes.Add(@{ description = $Description; action = $Action; arguments = @($Arguments) })
}

# Returns @{ status; confirmed; message; planned; ran; notRun; failed }:
#   status    'preview' (nothing ran), 'done' (everything ran), 'failed' (stopped part way) or 'empty'
#   planned   every description, in order
#   ran       @(@{ description; output }) for the changes that finished
#   notRun    descriptions that didn't run (all of them in a preview)
#   failed    $null, or @{ description; error } for the change that stopped the run
function Invoke-ChangePlan {
    param($Plan, $Confirm = $false)
    if ($null -eq $Plan -or -not ($Plan -is [System.Collections.IDictionary]) -or -not $Plan.Contains('changes')) { throw 'Invoke-ChangePlan needs a plan from New-ChangePlan.' }
    $ok = $false
    if ($Confirm -is [bool]) { $ok = $Confirm } elseif ($null -ne $Confirm) { $ok = ([string]$Confirm).Trim() -match '^(?i)(true|yes|y|1)$' }
    $all = @($Plan.changes)
    $planned = @($all | ForEach-Object { [string]$_.description })
    $res = [ordered]@{ status = ''; confirmed = $ok; title = [string]$Plan.title; message = ''; planned = $planned; ran = @(); notRun = @(); failed = $null }
    $n = $all.Count
    $things = if ($n -eq 1) { '1 change' } else { "$n changes" }
    if ($n -eq 0) { $res.status = 'empty'; $res.message = 'There is nothing to change.'; return $res }
    if (-not $ok) {
        $res.status = 'preview'; $res.notRun = $planned
        $res.message = "Nothing was changed. Run again with confirm set to true to make these $($things): $($planned -join '; ')."
        return $res
    }
    $ran = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $n; $i++) {
        $c = $all[$i]
        try {
            $args2 = @($c.arguments)
            $out = & $c.action @args2
            $null = $ran.Add(@{ description = [string]$c.description; output = $out })
        }
        catch {
            $res.failed = @{ description = [string]$c.description; error = [string]$_.Exception.Message }
            $res.ran = @($ran)
            $res.notRun = @($planned | Select-Object -Skip ($i + 1))
            $res.status = 'failed'
            $done = if ($ran.Count -eq 0) { 'No changes were made' } else { "Made $($ran.Count) of $n changes ($(@($ran | ForEach-Object { $_.description }) -join '; '))" }
            $left = if ($res.notRun.Count) { " Not run: $($res.notRun -join '; ')." } else { '' }
            $res.message = "$done, then stopped because '$($c.description)' failed: $($res.failed.error.Trim().TrimEnd('.')).$left"
            return $res
        }
    }
    $res.ran = @($ran); $res.status = 'done'
    $res.message = "Made $(if ($n -eq 1) { 'the change' } else { "all $n changes" }): $($planned -join '; ')."
    return $res
}
# ---------- end _shared/plan.ps1 ----------
