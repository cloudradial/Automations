# ---------- src/step.ps1: helpers every step in this workflow uses ----------
# Reading the trigger body (flat or the CloudRadial {Ticket, Company} shape), reading the previous
# step's context. Staff email uses Send-PmMail from _shared/postmark.ps1.

function Get-StepProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-StepJson { param($v) if ($null -eq $v) { return $null }; if ($v -is [string]) { if (-not $v.Trim()) { return $null }; try { return ($v | ConvertFrom-Json) } catch { return $null } }; return $v }
function Test-StepTrue { param($v) if ($v -eq $true) { return $true }; return (@('true', 'yes', 'y', '1') -contains ([string]$v).Trim().ToLowerInvariant()) }
# A value as trimmed text. A CloudRadial token that wasn't filled in arrives as literal "@name", which counts as missing.
function Get-StepText { param($v) if ($null -eq $v) { return '' }; $s = ([string]$v).Trim(); if ($s.StartsWith('@')) { return '' }; return $s }
# A list from a comma, semicolon or line separated value (or an array). Items are trimmed; an item may start with @ (an @domain).
function Get-StepList { param($v) if ($null -eq $v) { return @() }; if ($v -isnot [string]) { return @(@($v) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) }; return @(($v -split '[,;\r\n]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
function Test-StepEmail { param([string]$s) return ($s -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') }

# Every simple field of the trigger body, keyed case-insensitively. Handles a body wrapped in "trigger",
# a JSON string, and the CloudRadial {Ticket:{TicketId, Questions:[{Id, Value}]}, Company:{...}} shape.
function Read-StepTrigger {
    param($Raw)
    $in = Read-StepJson $Raw
    $w = Get-StepProp $in 'trigger'; if ($null -ne $w) { $in = Read-StepJson $w }
    $a = @{}
    if ($null -eq $in -or $in -is [string] -or $in -is [array]) { return $a }
    $addProps = {
        param($obj, [string]$prefix)
        $pairs = if ($obj -is [System.Collections.IDictionary]) { @($obj.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $obj[$_] } }) } else { @($obj.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }) }
        foreach ($p in $pairs) {
            if ($null -eq $p.Value) { continue }
            if ($p.Value -is [string] -or $p.Value.GetType().IsValueType) { $a["$prefix$($p.Name)"] = $p.Value }
        }
    }
    & $addProps $in ''
    $t = Get-StepProp $in 'Ticket'
    if ($null -ne $t -and $t -isnot [string]) {
        & $addProps $t 'Ticket.'
        foreach ($q in @(Get-StepProp $t 'Questions')) { $qid = [string](Get-StepProp $q 'Id'); if ($qid) { $a[$qid] = Get-StepProp $q 'Value' } }
        foreach ($k in @('TicketId', 'Status', 'StatusName', 'Subject', 'Summary', 'ContactEmail', 'Priority')) { if ($a.ContainsKey("Ticket.$k") -and -not $a.ContainsKey($k)) { $a[$k] = $a["Ticket.$k"] } }
    }
    $co = Get-StepProp $in 'Company'
    if ($null -ne $co -and $co -isnot [string]) {
        & $addProps $co 'Company.'
        foreach ($k in @('CompanyName', 'CompanyId', 'CompanyPsaId', 'CompanyTenantId')) { if ($a.ContainsKey("Company.$k") -and -not $a.ContainsKey($k)) { $a[$k] = $a["Company.$k"] } }
        if ($a.ContainsKey('Company.Name') -and -not $a.ContainsKey('CompanyName')) { $a['CompanyName'] = $a['Company.Name'] }
    }
    return $a
}
# The first non-empty field among the names.
function Get-StepField { param([hashtable]$A, [string[]]$Names) foreach ($n in $Names) { if ($A.ContainsKey($n)) { $v = Get-StepText $A[$n]; if ($v) { return $v } } }; return '' }

# The previous step's context, carried in its output as ctx (an object) or ctx_json (a string).
function Read-StepContext {
    param($Raw)
    $in = Read-StepJson $Raw
    $ctx = Read-StepJson (Get-StepProp $in 'ctx_json')
    if ($null -eq $ctx) { $ctx = Read-StepJson (Get-StepProp $in 'ctx') }
    return $ctx
}
# ---------- end src/step.ps1 ----------
