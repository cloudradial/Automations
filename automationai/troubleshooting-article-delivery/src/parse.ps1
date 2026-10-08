# === NODE: Read the request ===
# Dynamic Troubleshooting Article Delivery. Two entry points on one webhook:
#   mode "send" (default): the ServiceAI Action "Send Troubleshooting Article" (Use in Triage) sends the
#     ticket, the contact, the knowledge base article the triage AI matched, and its confidence (0 to 1).
#   mode "reply": a second triage Action sends the ticket and the customer's reply text, so a clear
#     "fixed" closes the ticket.
# Accepts a flat body, the CloudRadial {Ticket:{Questions:[...]},Company:{...}} shape, or either one wrapped
# in {trigger:...} (the step's "trigger" parameter is bound to {{ nodes.trigger.output }}). A value left as a
# literal @token, {{placeholder}} or <placeholder> counts as not given. This step makes no calls.
$ErrorActionPreference = 'Stop'

function Get-TaProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

$out = [ordered]@{
    status = 'ok'; message = ''; public_note = ''; internal_note = ''; chatReply = ''; ticket_id = ''
    mode = 'send'; contactEmail = ''; articleTitle = ''; articleUrl = ''; confidence = $null; minConfidence = 0.75
    replyText = ''; replyFrom = ''; crCompanyId = 0; mspCompanyId = 0; allowedLinkHosts = @(); autoClose = $true; dryRun = $false
    psa = ''; triggerSource = ''; received_keys = @()
    actions = @(); warnings = @()
}
function Stop-Request {
    param([string]$Why)
    $out.status = 'incomplete'; $out.message = $Why
    $out.chatReply = "The troubleshooting article action didn't run: $Why"
    $out.internal_note = "Troubleshooting article delivery stopped before anything was read or sent: $Why"
    Set-NodeOutput $out
}

$raw = Get-NodeInput
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The input was text that is not valid JSON.'; return } }
$wrap = Get-TaProp $raw 'trigger'
if ($null -ne $wrap) { $raw = $wrap; if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The trigger body was text that is not valid JSON.'; return } } }
if ($null -eq $raw) { Stop-Request 'No input was received.'; return }

$answers = @{}
if ($raw -is [System.Collections.IDictionary]) { foreach ($k in @($raw.Keys)) { $answers[[string]$k] = $raw[$k] } }
else { foreach ($p in $raw.PSObject.Properties) { $answers[$p.Name] = $p.Value } }
$crTicket = Get-TaProp $raw 'Ticket'
if ($null -ne $crTicket) {
    foreach ($q in @(Get-TaProp $crTicket 'Questions')) { $qid = [string](Get-TaProp $q 'Id'); if ($qid) { $answers[$qid] = Get-TaProp $q 'Value' } }
    $tid = Get-TaProp $crTicket 'TicketId'; if ($null -ne $tid -and -not $answers.ContainsKey('ticketId')) { $answers['ticketId'] = $tid }
}
$out.received_keys = @($answers.Keys | Sort-Object)

function Test-TaBlank { param($v) if ($null -eq $v) { return $true }; $s = ([string]$v).Trim(); return (-not $s -or $s.StartsWith('@') -or $s -match '^\{\{.*\}\}$' -or $s -match '^<[^>]*>$') }
function Get-Field {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary] -or $v -is [array]) { continue }
        if (Test-TaBlank $v) { continue }
        return ([string]$v).Trim()
    }
    return ''
}
function Get-Flag {
    param([string[]]$Names, [bool]$Default)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($v -is [bool]) { return $v }
        if (Test-TaBlank $v) { continue }
        switch -Regex (([string]$v).Trim().ToLowerInvariant()) { '^(true|yes|y|1|on)$' { return $true } '^(false|no|n|0|off)$' { return $false } }
    }
    return $Default
}
# A confidence of 0 to 1. "90%", 90 and 0.9 all mean 0.9. Returns $null when it isn't a number in range.
function ConvertTo-TaScore {
    param([string]$s)
    $t = $s.Trim().TrimEnd('%').Trim()
    $d = 0.0
    if (-not [double]::TryParse($t, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $null }
    if ($s.Trim().EndsWith('%') -or ($d -gt 1 -and $d -le 100)) { $d = $d / 100 }
    if ($d -lt 0 -or $d -gt 1) { return $null }
    return [Math]::Round($d, 4)
}

$mode = (Get-Field @('mode', 'action')).ToLowerInvariant()
if (-not $mode) { $mode = 'send' }
if ($mode -match '^(reply|response|customer-reply|confirm-fixed)$') { $mode = 'reply' }
elseif ($mode -match '^(send|deliver|article)$') { $mode = 'send' }
else { Stop-Request "mode '$mode' isn't one of: send, reply."; return }
$out.mode = $mode

$out.ticket_id = Get-Field @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber', 'id')
$out.psa = Get-Field @('psa')
$out.triggerSource = Get-Field @('triggerSource', 'trigger_source')
$out.dryRun = Get-Flag @('dry_run', 'dryRun') $false
$out.autoClose = Get-Flag @('autoClose', 'auto_close') $true
$cc = Get-Field @('companyId', 'crCompanyId'); if ($cc) { if ($cc -notmatch '^\d+$') { Stop-Request "companyId must be a CloudRadial company id (a number), not '$cc'."; return }; $out.crCompanyId = [int]$cc }
$mc = Get-Field @('mspCompanyId', 'msp_company_id'); if ($mc) { if ($mc -notmatch '^\d+$') { Stop-Request "mspCompanyId must be a number, not '$mc'."; return }; $out.mspCompanyId = [int]$mc }
$hosts = Get-Field @('allowedLinkHosts', 'allowed_link_hosts')
if ($hosts) { $out.allowedLinkHosts = @($hosts -split '[,;\s]+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) }
$mn = Get-Field @('min_confidence', 'minConfidence', 'threshold')
if ($mn) { $m = ConvertTo-TaScore $mn; if ($null -eq $m) { Stop-Request "min_confidence must be a number from 0 to 1, not '$mn'."; return }; $out.minConfidence = $m }

if (-not $out.ticket_id) { Stop-Request 'ticketId is missing.'; return }
if ($out.ticket_id -notmatch '^[A-Za-z0-9-]{1,40}$') { Stop-Request "ticketId '$($out.ticket_id)' isn't a ticket number."; return }

if ($mode -eq 'reply') {
    $out.replyText = Get-Field @('replyText', 'reply_text', 'reply', 'text', 'comment', 'lastReply', 'message')
    $out.replyFrom = (Get-Field @('replyFrom', 'reply_from', 'fromEmail', 'contactEmail')).ToLowerInvariant()
    if (-not $out.replyText) { Stop-Request 'replyText is missing. Send the customer reply to check.'; return }
    if ($out.replyText.Length -gt 20000) { $out.replyText = $out.replyText.Substring(0, 20000) }
    Set-NodeOutput $out; return
}

$out.contactEmail = (Get-Field @('contactEmail', 'contact_email', 'requesterEmail')).ToLowerInvariant()
$out.articleTitle = Get-Field @('articleTitle', 'article_title')
$out.articleUrl = Get-Field @('articleUrl', 'article_url')
$conf = Get-Field @('confidence', 'score')
if (-not $out.contactEmail) { Stop-Request 'contactEmail is missing.'; return }
if ($out.contactEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Stop-Request "contactEmail '$($out.contactEmail)' isn't an email address."; return }
if (-not $out.articleTitle) { Stop-Request 'articleTitle is missing.'; return }
if (-not $out.articleUrl) { Stop-Request 'articleUrl is missing.'; return }
$u = $null
if (-not [uri]::TryCreate($out.articleUrl, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'https') { Stop-Request 'articleUrl must be a full https:// link.'; return }
if (-not $conf) { Stop-Request 'confidence is missing.'; return }
$score = ConvertTo-TaScore $conf
if ($null -eq $score) { Stop-Request "confidence must be a number from 0 to 1, not '$conf'."; return }
$out.confidence = $score

Set-NodeOutput $out
