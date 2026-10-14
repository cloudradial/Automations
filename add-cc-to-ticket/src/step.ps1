# ---------- src/step.ps1: reading the trigger body ----------
# The body arrives flat ({"ticketNumber": "...", "ccEmail": "..."}), wrapped in "trigger" (the step's
# {{ nodes.trigger.output }} parameter), as a JSON string, in the CloudRadial
# {Ticket:{Questions:[{Id, Answer}]}, Company:{...}, User:{...}} shape, or from a CloudRadial Action on the form:
# the answers as top-level keys by Field ID, next to the portal's own ticket {id}, company {psaId} and user {email}
# objects, with no Questions.

function Get-StepProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-StepJson { param($v) if ($null -eq $v) { return $null }; if ($v -is [string]) { if (-not $v.Trim()) { return $null }; try { return ($v | ConvertFrom-Json) } catch { return $null } }; return $v }
function Test-StepTrue { param($v) if ($v -eq $true) { return $true }; return (@('true', 'yes', 'y', '1') -contains ([string]$v).Trim().ToLowerInvariant()) }
# A value as trimmed text. A CloudRadial token that wasn't filled in arrives as literal "@name", which counts as missing.
function Get-StepText { param($v) if ($null -eq $v) { return '' }; $s = ([string]$v).Trim(); if ($s.StartsWith('@')) { return '' }; return $s }

# Returns @{ flat; answers; portal }, flat and answers keyed case-insensitively.
#   flat     the body's own simple fields, plus Company.*, User.* and Ticket.* fields under those prefixes.
#            These are set by whoever configured the webhook (or by CloudRadial tokens), not typed by the submitter.
#   answers  the form's question answers (Ticket.Questions or Questions), by question Id. The submitter types these,
#            so the ownership fields (requester_email, company_psa_id, technician_run and so on) are never read from here.
#   portal   true for a CloudRadial Action: the portal's objects are there and there are no Questions. Its top-level
#            keys are then the form's answers, so they go into answers, not flat, and flat holds only the Company.*,
#            User.* and Ticket.* fields from the portal's objects.
# Ticket.TicketId is the NEW ticket the form created, so it is kept only as Ticket.TicketId and never used as the target.
function Read-StepTrigger {
    param($Raw)
    $in = Read-StepJson $Raw
    $w = Get-StepProp $in 'trigger'; if ($null -ne $w) { $in = Read-StepJson $w }
    $flat = @{}; $answers = @{}
    if ($null -eq $in -or $in -is [string] -or $in -is [array] -or $in.GetType().IsValueType) { return @{ flat = $flat; answers = $answers; portal = $false } }
    $pairsOf = {
        param($obj)
        if ($obj -is [System.Collections.IDictionary]) { return @($obj.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $obj[$_] } }) }
        return @($obj.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
    }
    $simple = { param($v) return ($null -ne $v -and ($v -is [string] -or $v.GetType().IsValueType)) }
    $groups = 0
    foreach ($group in @('Company', 'User', 'Ticket')) {
        $g = Get-StepProp $in $group
        if ($null -eq $g -or (& $simple $g) -or $g -is [array]) { continue }
        $groups++
        foreach ($p in (& $pairsOf $g)) { if (& $simple $p.Value) { $flat["$group.$($p.Name)"] = $p.Value } }
    }
    $qs = @()
    $t = Get-StepProp $in 'Ticket'
    if ($null -ne $t -and -not (& $simple $t)) { $qs += @(Get-StepProp $t 'Questions') }
    $qs += @(Get-StepProp $in 'Questions')
    $qs = @($qs | Where-Object { $null -ne $_ -and -not (& $simple $_) })
    $portal = ($groups -gt 0 -and $qs.Count -eq 0)
    foreach ($p in (& $pairsOf $in)) {
        if (-not (& $simple $p.Value)) { continue }
        if (-not $portal) { $flat[$p.Name] = $p.Value }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$p.Value) -and -not $answers.ContainsKey($p.Name)) { $answers[$p.Name] = [string]$p.Value }
    }
    foreach ($q in $qs) {
        $qid = [string](Get-StepProp $q 'Id')
        if (-not $qid) { continue }
        $ans = Get-StepProp $q 'Answer'
        if ([string]::IsNullOrWhiteSpace([string]$ans)) { $ans = Get-StepProp $q 'Value' }
        if (-not [string]::IsNullOrWhiteSpace([string]$ans) -and -not $answers.ContainsKey($qid)) { $answers[$qid] = [string]$ans }
    }
    return @{ flat = $flat; answers = $answers; portal = $portal }
}
# The first non-empty field among the names (a leftover @token counts as empty).
function Get-StepField { param([hashtable]$A, [string[]]$Names) foreach ($n in $Names) { if ($A.ContainsKey($n)) { $v = Get-StepText $A[$n]; if ($v) { return $v } } }; return '' }
# ---------- end src/step.ps1 ----------
