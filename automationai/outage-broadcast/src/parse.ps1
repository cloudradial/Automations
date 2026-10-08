# === NODE: Read the request ===
# Outage / Incident Broadcast. Called by the ServiceAI Action "Outage Broadcast" (Use in AI), the
# ChatAI /broadcast command, or a manual run. Reads what is down, what to tell clients, which
# companies to target, and whether this run may change anything (confirm, default false).
# Accepts a flat {key:value} body, the CloudRadial {Ticket:{Questions:[...]},Company:{...}} shape,
# or either one wrapped in {trigger:...} (the step's "trigger" parameter is bound to
# {{ nodes.trigger.output }}, as in Password Reset). A value left as a literal @token or {{placeholder}}
# counts as not given. This step makes no calls.
$ErrorActionPreference = 'Stop'

function Get-ObProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

$out = [ordered]@{
    status = 'ok'; message = ''; public_note = ''; internal_note = ''; chatReply = ''; ticket_id = ''
    mode = 'broadcast'; affectedService = ''; notice = ''; confirm = $false
    companies = @(); companyGroup = ''; emailContacts = $false; postBanner = $true; postArticle = $true
    bannerToken = 'ServiceStatus'; articleCategory = 'Service Status'; maxCompanies = 50
    psa = ''; requestedBy = ''; triggerSource = ''; received_keys = @(); received_body = $null
    actions = @(); warnings = @()
}
function Stop-Request {
    param([string]$Why)
    $out.status = 'incomplete'; $out.message = $Why
    $out.chatReply = "I couldn't run the outage broadcast: $Why"
    $out.internal_note = "Outage broadcast stopped before anything was read or changed: $Why"
    Set-NodeOutput $out
}

$raw = Get-NodeInput
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The input was text that is not valid JSON.'; return } }
$wrap = Get-ObProp $raw 'trigger'
if ($null -ne $wrap) { $raw = $wrap; if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The trigger body was text that is not valid JSON.'; return } } }
if ($null -eq $raw) { Stop-Request 'No input was received. Send affectedService and message.'; return }

$answers = @{}
if ($raw -is [System.Collections.IDictionary]) { foreach ($k in @($raw.Keys)) { $answers[[string]$k] = $raw[$k] } }
else { foreach ($p in $raw.PSObject.Properties) { $answers[$p.Name] = $p.Value } }
$crTicket = Get-ObProp $raw 'Ticket'
if ($null -ne $crTicket) {
    foreach ($q in @(Get-ObProp $crTicket 'Questions')) { $qid = [string](Get-ObProp $q 'Id'); if ($qid) { $answers[$qid] = Get-ObProp $q 'Value' } }
    $tid = Get-ObProp $crTicket 'TicketId'; if ($null -ne $tid -and -not $answers.ContainsKey('ticketId')) { $answers['ticketId'] = $tid }
}
# Keep the body for the first test run, so the "performed for a person" field can be mapped (TRIGGERS.md).
$out.received_keys = @($answers.Keys | Sort-Object)
$out.received_body = $raw

function Test-ObBlank { param($v) if ($null -eq $v) { return $true }; $s = ([string]$v).Trim(); return (-not $s -or $s.StartsWith('@') -or $s -match '^\{\{.*\}\}$' -or $s -match '^<.*>$') }
function Get-Field {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary] -or $v -is [array]) { continue }
        if (Test-ObBlank $v) { continue }
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
        if (Test-ObBlank $v) { continue }
        switch -Regex (([string]$v).Trim().ToLowerInvariant()) { '^(true|yes|y|1|on)$' { return $true } '^(false|no|n|0|off)$' { return $false } }
    }
    return $Default
}
function Get-ListField {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        $items = @()
        if ($v -is [array]) { $items = @($v) } elseif ($v -is [string]) { $items = @($v -split '[,;\r\n]+') } elseif ($null -ne $v -and $v -isnot [System.Management.Automation.PSCustomObject]) { $items = @([string]$v) }
        $items = @($items | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and -not (Test-ObBlank $_) })
        if ($items.Count) { return $items }
    }
    return @()
}

$mode = (Get-Field @('mode', 'action', 'phase')).ToLowerInvariant()
if (-not $mode) { $mode = 'broadcast' }
if ($mode -match '^(resolve|resolved|resolution|clear|all-?clear|restored)$') { $mode = 'resolved' }
elseif ($mode -match '^(broadcast|outage|incident|update|post)$') { $mode = 'broadcast' }
else { Stop-Request "mode '$mode' isn't one of: broadcast, resolved."; return }
$out.mode = $mode

$out.affectedService = Get-Field @('affectedService', 'affected_service', 'service', 'serviceName')
$out.notice = Get-Field @('message', 'notice', 'clientMessage', 'update')
$out.ticket_id = Get-Field @('problemTicketId', 'problem_ticket_id', 'ticketId', 'ticket_id', 'TicketId')
# confirm, or its aliases from the tracker's safety line. Only an explicit true allows changes.
$out.confirm = Get-Flag @('confirm', 'approvedToBroadcast', 'approvedToWrite') $false
$out.companies = @(Get-ListField @('companies', 'companyIds', 'companyNames', 'company'))
$out.companyGroup = Get-Field @('companyGroup', 'company_group', 'group')
$out.emailContacts = Get-Flag @('emailContacts', 'email_contacts', 'notifyContacts') $false
$out.postBanner = Get-Flag @('postBanner', 'post_banner', 'banner') $true
$out.postArticle = Get-Flag @('postArticle', 'post_article', 'article') $true
$bt = Get-Field @('bannerToken', 'banner_token'); if ($bt) { $out.bannerToken = $bt.TrimStart('@') }
$ac = Get-Field @('articleCategory', 'article_category'); if ($ac) { $out.articleCategory = $ac }
$mc = Get-Field @('maxCompanies', 'max_companies'); if ($mc) { if ($mc -notmatch '^\d+$' -or [int]$mc -lt 1) { Stop-Request "maxCompanies must be a whole number of 1 or more, not '$mc'."; return }; $out.maxCompanies = [int]$mc }
$out.psa = Get-Field @('psa')
$out.triggerSource = Get-Field @('triggerSource', 'trigger_source')
# Who ran it. ServiceAI fills this from the signed-in technician; the field name is unverified, so try the likely ones.
$out.requestedBy = Get-Field @('requestedBy', 'requested_by', 'requester', 'requesterEmail', 'performedBy', 'performedFor', 'onBehalfOf', 'technician', 'technicianEmail', 'userEmail', 'UserEmail', 'user', 'actor', 'initiatedBy', 'submittedBy')

if (-not $out.affectedService) { Stop-Request 'affectedService is missing. Say which service or system is down.'; return }
if ($out.affectedService.Length -gt 120) { Stop-Request 'affectedService is longer than 120 characters. Use the short name of the service.'; return }
if ($mode -eq 'broadcast' -and -not $out.notice) { Stop-Request 'message is missing. Write the plain-language update for clients.'; return }
if ($out.notice.Length -gt 2000) { Stop-Request 'message is longer than 2000 characters. Keep the client update short.'; return }
if ($out.notice -match '<\s*(script|iframe|object|embed|style)\b' -or $out.notice -match '(?i)javascript:') { Stop-Request 'message contains script or embedded content. Send plain text only.'; return }
if ($out.bannerToken -notmatch '^[A-Za-z][A-Za-z0-9_]{1,49}$') { Stop-Request "bannerToken '$($out.bannerToken)' isn't a valid token name (letters, digits and underscores)."; return }
if (-not $out.postBanner -and -not $out.postArticle -and -not $out.emailContacts) { Stop-Request 'postBanner, postArticle and emailContacts are all off, so there is nothing to post.'; return }
if ($mode -eq 'resolved' -and -not $out.notice) { $out.notice = "The issue affecting $($out.affectedService) has been resolved. Thank you for your patience." }

Set-NodeOutput $out
