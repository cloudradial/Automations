# ---------- src/step.ps1: helpers every step in this workflow uses ----------
# Reading the trigger body (flat or the CloudRadial {Ticket, Company} shape), reading the previous
# step's context, and emailing staff through Postmark. Needs _shared/psa.ps1 above it (Get-PsaSecret).

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

# Emails staff through Postmark. Returns @{ sent; id; reason }. Never throws: when Postmark isn't
# set up or refuses the message, sent is $false and reason says why, so the caller can fall back
# to an internal note. Secrets: Postmark-ServerToken, Postmark-FromEmail, optional Postmark-ApiUrl.
function Send-StepEmail {
    param([string[]]$To, [string]$Subject, [string]$Text, [string]$Html = '', [string]$Tag = '')
    $to2 = @($To | Where-Object { Test-StepEmail $_ })
    if (-not $to2.Count) { return @{ sent = $false; id = ''; reason = 'there is no valid recipient address' } }
    $token = Get-PsaSecret 'Postmark-ServerToken'; $from = Get-PsaSecret 'Postmark-FromEmail'; $api = Get-PsaSecret 'Postmark-ApiUrl'
    if (-not $token -or -not $from) { return @{ sent = $false; id = ''; reason = 'Postmark is not set up (add the Postmark-ServerToken and Postmark-FromEmail secrets)' } }
    if (-not $api) { $api = 'https://api.postmarkapp.com' }
    $b = [ordered]@{ From = $from; To = ($to2 -join ','); Subject = $Subject; TextBody = $Text; MessageStream = 'outbound' }
    if ($Html) { $b.HtmlBody = $Html }
    if ($Tag) { $b.Tag = $Tag }
    try {
        $r = Invoke-RestMethod -Method POST -Uri "$($api.TrimEnd('/'))/email" -Headers @{ 'X-Postmark-Server-Token' = $token; Accept = 'application/json' } -Body (ConvertTo-Json -InputObject $b -Depth 5 -Compress) -ContentType 'application/json' -ErrorAction Stop
        return @{ sent = $true; id = [string](Get-StepProp $r 'MessageID'); reason = '' }
    }
    catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        $why = ''; try { $why = [string](Get-StepProp ($_.ErrorDetails.Message | ConvertFrom-Json) 'Message') } catch { }
        if (-not $why) { $why = [string]$_.Exception.Message }
        return @{ sent = $false; id = ''; reason = "Postmark refused the email$(if ($code) { " (HTTP $code)" }): $why" }
    }
}
function ConvertTo-StepHtml { param([string]$s) if ($null -eq $s) { return '' }; return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;') }
# ---------- end src/step.ps1 ----------
