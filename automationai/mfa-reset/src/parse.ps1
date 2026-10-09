# === NODE: Read the request ===
# Self-service MFA reset from a CloudRadial portal form. Reads who submitted the form (the TRUSTED
# portal tokens @UserEmail and @UserOfficeId, which a form answer can't override) and whose sign-in
# methods to clear. Accepts a flat {key:value} body (portal form webhook, ServiceAI Action, manual run),
# the CloudRadial {Ticket:{Questions:[...]},Company:{...}} shape, or either one wrapped in {trigger:...}.
# A value CloudRadial left as a literal @token (for example "@targetUpn") counts as not given.
# Input, as in Password Reset: the step's "trigger" parameter is bound to {{ nodes.trigger.output }}, so
# Get-NodeInput returns {trigger: <webhook body>} and the body is unwrapped below. A manual run's input
# without the wrapper is read as the body itself.
# This step makes no calls. The checks run in the next step.
$ErrorActionPreference = 'Stop'

function Get-Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Stop-Request {
    param([string]$Why, [string]$TicketId = '')
    $pub = 'We could not process this request automatically. A technician will follow up shortly.'
    Set-NodeOutput ([ordered]@{
            status = 'incomplete'; message = $Why; public_note = $pub; chatReply = $pub
            internal_note = "MFA reset stopped before any account lookup: $Why"
            ticket_id = $TicketId; actions = @(); warnings = @()
        })
    throw $Why
}

$raw = Get-NodeInput
if ($null -eq $raw) { Stop-Request 'No input was received. This workflow expects the portal form webhook body (submittedByUpn = @UserEmail, userOfficeId = @UserOfficeId).' }
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The input was text that is not valid JSON.' } }
$wrap = Get-Prop $raw 'trigger'; if ($null -ne $wrap) { $raw = $wrap; if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Request 'The trigger body was text that is not valid JSON.' } } }

# Every simple value, then the CloudRadial nested answers on top.
$answers = @{}
if ($raw -is [System.Collections.IDictionary]) { foreach ($k in @($raw.Keys)) { $answers[[string]$k] = $raw[$k] } }
else { foreach ($p in $raw.PSObject.Properties) { $answers[$p.Name] = $p.Value } }
$crTicket = Get-Prop $raw 'Ticket'
if ($null -ne $crTicket) {
    foreach ($q in @(Get-Prop $crTicket 'Questions')) { $qid = [string](Get-Prop $q 'Id'); if ($qid) { $answers[$qid] = Get-Prop $q 'Value' } }
    $tid = Get-Prop $crTicket 'TicketId'; if ($null -ne $tid) { $answers['ticketId'] = $tid }
    # The submitter recorded on the ticket, used only when the trusted token wasn't sent.
    foreach ($sf in @('SubmittedByEmail', 'SubmitterEmail', 'ContactEmail', 'RequesterEmail', 'UserEmail')) { $sv = [string](Get-Prop $crTicket $sf); if ($sv -like '*@*' -and -not $answers.ContainsKey('ticketSubmitter')) { $answers['ticketSubmitter'] = $sv } }
}
$crCompany = Get-Prop $raw 'Company'
if ($null -ne $crCompany) {
    foreach ($pair in @(@('CompanyTenantId', 'companyTenantId'), @('CompanyPsaId', 'psaCompanyId'))) { $v = Get-Prop $crCompany $pair[0]; if ($null -ne $v) { $answers[$pair[1]] = $v } }
}
function Get-Field {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if (-not $s -or $s.StartsWith('@') -or $s -match '^\{\{.*\}\}$') { continue }
        return $s
    }
    return ''
}
function Get-Flag {
    param([string[]]$Names, [bool]$Default)
    $s = Get-Field $Names
    if (-not $s) { return $Default }
    switch -Regex ($s.ToLowerInvariant()) { '^(true|yes|y|1|on)$' { return $true } '^(false|no|n|0|off)$' { return $false } }
    return $Default
}

$submitter = Get-Field @('submittedByUpn', 'submitted_by', 'submitterUpn', 'UserEmail', 'userEmail')
$submitterSource = 'token'
if (-not $submitter) { $submitter = Get-Field @('ticketSubmitter'); if ($submitter) { $submitterSource = 'ticket' } }
$target = Get-Field @('userPrincipalName', 'upn', 'targetUpn', 'target_upn', 'email')
$officeId = Get-Field @('userOfficeId', 'UserOfficeId', 'user_office_id')
$ticketId = Get-Field @('ticketId', 'ticket_id', 'TicketId')

if (-not $target -and -not $submitter -and -not $officeId) { Stop-Request 'Neither the account to reset nor the submitter was sent. Map submittedByUpn to @UserEmail and userOfficeId to @UserOfficeId in the form webhook.' $ticketId }
# Self-service: with no target named, the account is the submitter's own.
$targetSource = 'form'
if (-not $target) { $target = $(if ($submitter) { $submitter } else { $officeId }); $targetSource = 'submitter' }

Set-NodeOutput ([ordered]@{
        status          = 'ok'
        ticket_id       = $ticketId
        upn             = $target
        target_source   = $targetSource
        submittedByUpn  = $submitter
        submitter_source = $(if ($submitter) { $submitterSource } else { '' })
        userOfficeId    = $officeId
        companyTenantId = (Get-Field @('companyTenantId', 'company_tenant_id', 'CompanyTenantId', 'tenantId'))
        psa             = (Get-Field @('psa'))
        psaCompanyId    = (Get-Field @('psaCompanyId', 'psa_company_id', 'CompanyPsaId'))
        issue_tap       = (Get-Flag @('issue_tap', 'issueTap', 'issueTemporaryAccessPass') $false)
        dry_run         = (Get-Flag @('dry_run', 'dryRun') $false)
        revokeSessions  = (Get-Flag @('revokeSessions', 'revoke_sessions') $true)
        actions         = @()
        warnings        = @()
    })
