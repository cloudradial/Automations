# Strict-mode tests for _shared/plan.ps1: preview, confirm, mid-plan failure, loop arguments,
# and using it together with graph.ps1 the way a write automation would.
. (Join-Path $PSScriptRoot 'mock.ps1')

Invoke-WithLib @('plan.ps1') {
    $log = New-Object System.Collections.ArrayList
    function New-Demo {
        $p = New-ChangePlan 'Offboard sam@contoso.com'
        Add-PlannedChange $p 'Block sign-in' { $null = $log.Add('block'); 'blocked' }
        Add-PlannedChange $p 'Sign out of every session' { $null = $log.Add('revoke') }
        Add-PlannedChange $p 'Remove the licence' { $null = $log.Add('licence') }
        return $p
    }

    $r = Invoke-ChangePlan (New-Demo)
    Check 'preview: nothing runs by default' ($r.status -eq 'preview' -and $log.Count -eq 0 -and $r.confirmed -eq $false) ($r | ConvertTo-Json -Depth 4 -Compress)
    Check 'preview: lists every change and says how to confirm' ($r.planned.Count -eq 3 -and $r.notRun.Count -eq 3 -and $r.message -match 'Nothing was changed' -and $r.message -match 'confirm' -and $r.message -match 'Block sign-in') $r.message
    $r = Invoke-ChangePlan (New-Demo) -Confirm:$false
    Check 'preview: -Confirm:$false' ($r.status -eq 'preview' -and $log.Count -eq 0) $r.status
    $r = Invoke-ChangePlan (New-Demo) -Confirm 'no'
    Check 'preview: confirm text "no"' ($r.status -eq 'preview' -and $log.Count -eq 0) $r.status

    $r = Invoke-ChangePlan (New-Demo) -Confirm:$true
    Check 'confirm: runs every change in order' ($r.status -eq 'done' -and ($log -join ',') -eq 'block,revoke,licence' -and $r.ran.Count -eq 3 -and $r.notRun.Count -eq 0 -and $null -eq $r.failed) "$($log -join ',') / $($r.status)"
    Check 'confirm: keeps each change''s output' ($r.ran[0].output -eq 'blocked' -and $r.ran[0].description -eq 'Block sign-in') ($r.ran[0] | ConvertTo-Json -Compress)
    Check 'confirm: plain summary' ($r.message -match '^Made all 3 changes') $r.message
    $log.Clear()
    $r = Invoke-ChangePlan (New-Demo) -Confirm 'True'
    Check 'confirm: text "True" from a form or run input' ($r.status -eq 'done' -and $log.Count -eq 3) $r.status

    $log.Clear()
    $p = New-ChangePlan
    Add-PlannedChange $p 'Block sign-in' { $null = $log.Add('block') }
    Add-PlannedChange $p 'Remove from Finance' { throw 'Graph said no.' }
    Add-PlannedChange $p 'Remove the licence' { $null = $log.Add('licence') }
    Add-PlannedChange $p 'Convert the mailbox' { $null = $log.Add('mailbox') }
    $r = Invoke-ChangePlan $p -Confirm:$true
    Check 'failure: stops at the first failure' ($r.status -eq 'failed' -and ($log -join ',') -eq 'block') "$($log -join ',')"
    Check 'failure: reports what ran, what failed and what did not run' ($r.ran.Count -eq 1 -and $r.failed.description -eq 'Remove from Finance' -and $r.failed.error -eq 'Graph said no.' -and ($r.notRun -join '|') -eq 'Remove the licence|Convert the mailbox') ($r | ConvertTo-Json -Depth 4 -Compress)
    Check 'failure: plain message' ($r.message -match "^Made 1 of 4 changes \(Block sign-in\), then stopped because 'Remove from Finance' failed: Graph said no\. Not run: Remove the licence; Convert the mailbox\.$") $r.message

    $p = New-ChangePlan
    Add-PlannedChange $p 'First' { throw 'nope' }
    Add-PlannedChange $p 'Second' { }
    $r = Invoke-ChangePlan $p -Confirm:$true
    Check 'failure on the first change: nothing made' ($r.message -match '^No changes were made' -and $r.ran.Count -eq 0 -and $r.notRun.Count -eq 1) $r.message

    $r = Invoke-ChangePlan (New-ChangePlan) -Confirm:$true
    Check 'empty plan' ($r.status -eq 'empty') $r.status

    # Loop values go through -Arguments: a scriptblock reads variables when it runs.
    $seen = New-Object System.Collections.ArrayList
    $p = New-ChangePlan
    foreach ($g in @('Finance', 'Sales', 'All Staff')) { Add-PlannedChange $p "Remove from $g" { param($group) $null = $seen.Add($group) } -Arguments @($g) }
    $null = Invoke-ChangePlan $p -Confirm:$true
    Check 'arguments: each change keeps its own loop value' (($seen -join ',') -eq 'Finance,Sales,All Staff') ($seen -join ',')

    $m = Get-ThrowMessage { Add-PlannedChange @{} 'x' { } }
    Check 'Add-PlannedChange needs a plan' ($m -match 'New-ChangePlan') $m
    $m = Get-ThrowMessage { Add-PlannedChange (New-ChangePlan) '' { } }
    Check 'Add-PlannedChange needs a description' ($m -match 'description') $m
}

# With graph.ps1, as an offboarding step would use it: preview makes no Graph writes; confirm does.
$Sec = @{ 'M365-TenantId' = 'contoso.onmicrosoft.com'; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret' }
$H = {
    param($c, $n)
    if ($c.Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'tok'; expires_in = 3599 } }
    if ($c.Uri -like '*/groups/g-sales/*') { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
    return $null
}
foreach ($confirm in @($false, $true)) {
    Reset-Mock $Sec.Clone() $H
    Invoke-WithLib @('graph.ps1', 'plan.ps1') {
        $null = Connect-Graph
        $u = 'u1'
        $p = New-ChangePlan "Offboard $u"
        Add-PlannedChange $p 'Block sign-in' { param($id) Set-GraphAccountEnabled $id $false } -Arguments @($u)
        foreach ($g in @('g-finance', 'g-sales', 'g-staff')) { Add-PlannedChange $p "Remove from group $g" { param($gid, $id) Remove-GraphGroupMember $gid $id } -Arguments @($g, $u) }
        $r = Invoke-ChangePlan $p -Confirm:$confirm
        $writes = @($Mock.Calls | Where-Object { $_.Uri -like 'https://graph.microsoft.com/*' })
        if (-not $confirm) {
            Check 'with graph: preview makes no Graph calls' ($r.status -eq 'preview' -and $writes.Count -eq 0) (Show-Calls)
        }
        else {
            Check 'with graph: confirm runs until the 403, then stops' ($r.status -eq 'failed' -and $writes.Count -eq 3 -and $r.ran.Count -eq 2 -and $r.ran[1].output -eq 'removed' -and ($r.notRun -join ',') -eq 'Remove from group g-staff') (Show-Calls)
            Check 'with graph: the failure names the permission' ($r.failed.error -match 'GroupMember.ReadWrite.All' -and $r.message -match 'GroupMember.ReadWrite.All') $r.message
        }
    }
}

Complete-Test
