# Step: Add CC to ticket.
# Adds one email address to an EXISTING ticket's email CC list, from a CloudRadial service-request form, then
# leaves an internal note. Only the ticket's own people can do it: the ticket's company must be the requester's
# company (company_psa_id, sent as @CompanyPsaId), and the requester (requester_email, sent as @UserEmail) must be
# the ticket's contact or already on its CC list. allow_company_colleagues relaxes the second part to "same company".
# preview=true says what would happen and changes nothing. Already on the list: success, no change, no note.
# Status: success, rejected (nothing changed), error (nothing changed unless the message says so) or
# pending_confirmation (a preview). A setup problem (no ticket number, no address, no requester or company) is an
# error, so the step fails and shows in the run history; a refusal that is the rule working stays rejected.
# Once added, the new CC is emailed the ticket's details directly (src/email.ps1: Postmark, else Graph from the
# AddCc-NotifySender mailbox). Only when no email went (none set up, or it failed) is the public note added instead,
# so a PSA that emails CCs on public notes doesn't send them two emails. notify_cc=false turns both off.
$ccRun = @{ ticketId = ''; ccEmail = ''; done = $false; emailed = $false; transport = ''; subject = ''; body = '' }
$ccWarnings = New-Object System.Collections.ArrayList
$ccActions = New-Object System.Collections.ArrayList

function Add-CcWarning { param([string]$Text) if ($Text -and -not $ccWarnings.Contains($Text)) { $null = $ccWarnings.Add($Text) } }
# The step's output. Messages are plain sentences; any dash a PSA's error text carries is made a plain hyphen.
function New-CcResult {
    param([string]$Status, [string]$Message, [bool]$Added = $false, $CcList = @(), [string]$Note = '', [string]$PublicNote = '')
    foreach ($w in @($PsaState.Warnings)) { Add-CcWarning ([string]$w) }
    $clean = { param([string]$s) return (([string]$s) -replace "[$([char]0x2013)$([char]0x2014)]", '-') }
    return [ordered]@{
        status = $Status; message = (& $clean $Message); ticket_id = $ccRun.ticketId; cc_email = $ccRun.ccEmail; added = $Added
        cc_list = @($CcList); actions = @($ccActions | ForEach-Object { & $clean $_ }); warnings = @($ccWarnings | ForEach-Object { & $clean $_ })
        internal_note = (& $clean $Note); public_note = (& $clean $PublicNote)
        emailed = [bool]$ccRun.emailed; email_transport = $ccRun.transport; email_subject = (& $clean $ccRun.subject); email_body = (& $clean $ccRun.body)
    }
}

# An address as typed: a mailto: prefix and angle brackets are dropped.
function Get-CcAddress { param($v) return ((([string]$v) -replace '^(?i)mailto:', '').Trim().Trim('<', '>').Trim()) }
# The one form answer that fits, when the question's Field ID isn't one of the expected names (the portal makes a
# Field ID from the question's label, for example emailAddressToAdd). Answers whose Field ID matches KeyPattern and
# whose value passes Test count. None: ''. One value: that value. Several different values: a setup error, since
# guessing could change the wrong ticket or copy the wrong person. Who-is-asking Field IDs never count.
function Find-CcAnswer {
    param([hashtable]$Answers, [string]$KeyPattern, [scriptblock]$Test, [string]$What, [string]$FieldId)
    $skip = @('requester_email', 'requesterEmail', 'UserEmail', 'userPrincipalName', 'upn', 'company_psa_id', 'companyPsaId', 'CompanyPsaId')
    $hits = [ordered]@{}
    foreach ($k in @($Answers.Keys | Sort-Object)) {
        if ($skip -contains $k -or $k -notmatch $KeyPattern) { continue }
        $v = Get-StepText $Answers[$k]
        if (-not $v -or -not (& $Test $v)) { continue }
        $key = $v.ToLowerInvariant(); if (-not $hits.Contains($key)) { $hits[$key] = @{ value = $v; ids = @() } }
        $hits[$key].ids += $k
    }
    if ($hits.Count -eq 0) { return '' }
    if ($hits.Count -gt 1) {
        $ids = @($hits.Values | ForEach-Object { $_.ids }) -join ', '
        throw "The form sent more than one $What ($ids), so it can't tell which to use and nothing was changed. Set the Field ID of the one to use to $FieldId."
    }
    return @($hits.Values)[0].value
}

function Invoke-CcMain {
    param($Raw)
    $in = Read-StepTrigger $Raw
    $f = $in.flat; $q = $in.answers
    # Ticket and address: the webhook body first, then the form's answers.
    $ticketRef = Get-StepField $f @('ticket_number', 'ticketNumber', 'ticketId', 'ticket_id')
    if (-not $ticketRef) { $ticketRef = Get-StepField $q @('ticket_number', 'ticketNumber', 'ticketId', 'ticket_id') }
    # A ticket-number question with another Field ID: the one answer whose Field ID mentions "ticket" and that looks
    # like a ticket number. This comes before the form's own ticket, so a renamed question never sends the CC there.
    if (-not $ticketRef) { $ticketRef = Find-CcAnswer $q '(?i)ticket' { param($v) (($v -replace '^(?i)\s*ticket\s*', '').Trim()) -match '^#?[A-Za-z0-9.-]{1,40}$' } 'ticket number' 'ticketNumber' }
    # From a CloudRadial Action with no ticket-number question, the target is the ticket the form itself created
    # (for example a Password Reset form that also asks who to copy). The ownership check below still applies, so the
    # requester must be that ticket's contact, which the person who submitted the form is.
    $ownTicket = $false
    if (-not $ticketRef -and $in.portal) { $ticketRef = Get-StepField $f @('Ticket.Id', 'Ticket.Reference'); $ownTicket = [bool]$ticketRef }
    $ccIn = Get-StepField $f @('cc_email', 'ccEmail', 'cc', 'email', 'contactEmail')
    if (-not $ccIn) { $ccIn = Get-StepField $q @('cc_email', 'ccEmail', 'cc', 'email', 'contactEmail') }
    # Who is asking, and the rules: the webhook body only (CloudRadial fills @UserEmail and @CompanyPsaId at submit;
    # the submitter can't change them), or on an Action the portal's user and company objects. A form answer never sets
    # these, and on an Action the switches below (technician_run, preview and so on) can't be set at all.
    $requester = Get-StepField $f @('requester_email', 'requesterEmail', 'UserEmail', 'User.Email', 'User.UserEmail')
    $companyPsa = Get-StepField $f @('company_psa_id', 'companyPsaId', 'CompanyPsaId', 'Company.CompanyPsaId', 'Company.PsaId')
    $techRun = Test-StepTrue (Get-StepField $f @('technician_run', 'technicianRun'))
    $colleagues = Test-StepTrue (Get-StepField $f @('allow_company_colleagues', 'allowCompanyColleagues'))
    $domainsIn = Get-StepField $f @('allowed_domains', 'allowedDomains')
    $preview = Test-StepTrue (Get-StepField $f @('preview', 'dryRun', 'dry_run'))
    # The new CC is told what the ticket is about: by email, else by a public note. On unless notify_cc is false.
    $notifyIn = Get-StepField $f @('notify_cc', 'notifyCc')
    $notify = if ($notifyIn) { Test-StepTrue $notifyIn } else { $true }
    # The email carries the ticket's original request unless email_include_description is false.
    $descIn = Get-StepField $f @('email_include_description', 'emailIncludeDescription')
    $withDesc = if ($descIn) { Test-StepTrue $descIn } else { $true }
    $psaIn = Get-StepField $f @('psa')
    # An email question with another Field ID: the one answer whose Field ID mentions mail or cc, that is a single
    # address, and that isn't the requester's own address.
    if (-not $ccIn) { $ccIn = Find-CcAnswer $q '(?i)mail|cc' { param($v) $a = Get-CcAddress $v; (Test-CcEmail $a) -and $a -ine $requester } 'email address to add' 'ccEmail' }

    # ---- the request itself ----
    $ticketRef = ($ticketRef -replace '^(?i)\s*ticket\s*', '').Trim()
    if (-not $ticketRef) { throw 'The request has no ticket number, so nothing was changed. Check the form has a ticket number question (Field ID ticketNumber).' }
    if ($ticketRef -notmatch '^#?[A-Za-z0-9.-]{1,40}$') { return (New-CcResult 'rejected' "'$ticketRef' isn't a ticket number, so nothing was changed.") }
    $ccRun.ticketId = $ticketRef.TrimStart('#')
    $cc = Get-CcAddress $ccIn
    if (-not $cc) {
        # On the form's own ticket the question is optional: left blank, nobody is added.
        if ($ownTicket) { return (New-CcResult 'success' "Nobody was named to copy on ticket $($ccRun.ticketId), so nothing changed.") }
        throw 'The request has no email address to add, so nothing was changed. Check the form has an Email question for the address to add (Field ID ccEmail).'
    }
    if (-not (Test-CcEmail $cc)) { return (New-CcResult 'rejected' "'$cc' isn't a single email address, so nothing was changed.") }
    $ccRun.ccEmail = $cc
    $domains = @(Get-CcEmailList $domainsIn | ForEach-Object { $_.TrimStart('@').ToLowerInvariant() } | Where-Object { $_ })
    if ($domains.Count) {
        $dom = ($cc -split '@')[-1].ToLowerInvariant()
        if ($domains -notcontains $dom) { return (New-CcResult 'rejected' "$cc isn't in an allowed domain ($($domains -join ', ')), so nothing was changed.") }
    }
    if ($requester -and -not (Test-CcEmail $requester)) { return (New-CcResult 'rejected' "The requester '$requester' isn't an email address, so nothing was changed.") }
    if ($companyPsa -and $companyPsa -notmatch '^[A-Za-z0-9-]{1,40}$') { return (New-CcResult 'rejected' "The company id '$companyPsa' isn't a PSA company id, so nothing was changed.") }
    $missing = @(); if (-not $requester) { $missing += 'requester_email' }; if (-not $companyPsa) { $missing += 'company_psa_id' }
    if ($missing.Count) {
        if (-not $techRun) { throw "The request didn't include $($missing -join ' and ') (map requester_email to @UserEmail and company_psa_id to @CompanyPsaId in the webhook body), so nothing was changed." }
        Add-CcWarning "technician_run is set and the request had no $($missing -join ' or '), so only the checks the request had data for were made. Don't send technician_run from a client-facing form."
    }

    # ---- the PSA ----
    $psa = Get-PsaType $psaIn
    if (-not $psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
    $unsupported = Get-CcUnsupported $psa
    if ($unsupported) { throw $unsupported }
    $null = Connect-Psa $psa
    $id = Resolve-PsaTicketId $ticketRef
    $ccRun.ticketId = $id
    $info = Get-CcTicket $id
    $null = $ccActions.Add("Read ticket $id from $(Get-PsaName).")

    # ---- ownership ----
    # The message never says whose ticket it is: a ticket from another company gets the same answer as one that doesn't exist for them.
    if ($companyPsa -and -not (Test-CcIn $companyPsa $info.companyKeys)) {
        return (New-CcResult 'rejected' "Ticket $ticketRef isn't one you can change, so nothing was changed." -Note "Add CC refused: ticket $id belongs to PSA company '$($info.companyId)', not the requester's company '$companyPsa'.")
    }
    $isContact = Test-CcSame $info.contactEmail $requester
    $isCopied = Test-CcIn $requester $info.cc
    if ($requester -and -not $isContact -and -not $isCopied) {
        if (-not $colleagues) {
            return (New-CcResult 'rejected' "Only the ticket's contact, or someone already copied on it, can add people to ticket $ticketRef, so nothing was changed." -Note "Add CC refused: $requester is not the contact on ticket $id or on its CC list.")
        }
        if (-not $companyPsa) { return (New-CcResult 'rejected' "Ticket $ticketRef isn't one you can change, so nothing was changed." -Note "Add CC refused: allow_company_colleagues needs company_psa_id to check that $requester is at the ticket's company.") }
        $null = $ccActions.Add("Allowed $requester to add a CC as a colleague at the ticket's company (allow_company_colleagues).")
    }
    $who = if ($requester) { $requester } else { 'a technician (technician_run)' }

    # ---- already there ----
    if (Test-CcSame $info.contactEmail $cc) {
        return (New-CcResult 'success' "$cc is already the contact on ticket $id, so nothing changed." -CcList $info.cc)
    }
    if ((Test-CcIn $cc $info.cc) -and $info.ccEnabled) {
        return (New-CcResult 'success' "$cc is already on the CC list for ticket $id, so nothing changed." -CcList $info.cc)
    }

    # ---- the change ----
    $plan = Get-CcPlan $info $cc
    if (-not $plan.ok) { return (New-CcResult 'rejected' $plan.why -CcList $info.cc) }
    $note = "Added $cc to the email CC list at the request of $who (self-service form)."
    if (Test-CcIn $cc $info.cc) { $note = "Turned on the email CC list, which already had $cc on it, at the request of $who (self-service form)." }
    # The public note names the ticket so the new CC knows what it is about. Never anything internal.
    $about = if ($info.summary) { "ticket $id, `"$($info.summary)`"" } else { "ticket $id" }
    $asker = if ($requester) { $requester } else { 'our service desk' }
    $publicNote = ''
    if ($notify) { $publicNote = "$cc has been copied on $about at the request of $asker, and will now receive email updates on it. To add information, reply to any update email." }
    # The email to the new CC, built from the ticket's own client-facing fields (reads only).
    $transport = if ($notify) { Get-CcTransport } else { '' }
    $mail = $null
    if ($transport) {
        try {
            $mail = New-CcEmail (Get-CcEmailDetails $info) $requester $withDesc
            $ccRun.transport = $transport; $ccRun.subject = $mail.subject; $ccRun.body = $mail.text
        }
        catch { Add-CcWarning "The email to $cc couldn't be put together, so a public note tells them instead: $($_.Exception.Message)"; $transport = '' }
    }
    if ($preview) {
        $then = if (-not $notify) { 'add an internal note' }
        elseif ($transport) { "email $cc the ticket's details through $(Get-CcTransportName $transport) and add an internal note" }
        else { 'add an internal note and a public note telling them what the ticket is about (no email transport is set up)' }
        $null = $ccActions.Add("Would $($plan.detail) on ticket $id, then $then.")
        $previewPublic = if ($transport) { '' } else { $publicNote }
        return (New-CcResult 'pending_confirmation' "Preview: $cc would be added to the CC list on ticket $id; run again without preview to add it." -CcList $plan.list -Note $note -PublicNote $previewPublic)
    }
    $PsaState.LastWriteRedirect = $null
    $saved = $null
    try { Send-CcChange $info $cc $plan }
    catch {
        # A write answered with a redirect may still have been saved, so it is never resent: the ticket is read back.
        if ($null -eq $PsaState.LastWriteRedirect) { throw "Couldn't add $cc to ticket ${id}: $($_.Exception.Message)" }
        $first = [string]$_.Exception.Message
        $saved = Test-CcSaved $id $cc
        if (-not $saved.ok) { throw "Couldn't add $cc to ticket ${id}: $first Reading the ticket back showed $cc isn't on its CC list." }
        Add-CcWarning "$(Get-PsaName) answered the CC change on ticket $id with a redirect; reading the ticket back showed it was saved, so it was not sent again."
    }
    if ($null -eq $saved) { $saved = Test-CcSaved $id $cc }
    if (-not $saved.ok) { throw "$(Get-PsaName) accepted the CC change on ticket $id, but reading the ticket back shows $cc isn't on its CC list, so check the ticket's CC settings in $(Get-PsaName)." }
    $null = $ccActions.Add("Added $cc to the CC list on ticket $id.")

    # ---- the email to the new CC (a failure is a warning: the CC is already added, and the public note stands in) ----
    # Sent before the internal note so that one note records both the change and whether the email went.
    if ($transport) {
        $how = Get-CcTransportName $transport
        $sent = Send-CcEmail $transport $cc $mail
        if ($sent.sent) {
            $ccRun.emailed = $true
            $null = $ccActions.Add("Emailed $cc the ticket's details through $how.")
            $note += " Emailed $cc the ticket's details through $how."
        }
        else {
            Add-CcWarning "$cc was added, but the email with the ticket's details couldn't be sent through ${how}: $($sent.reason) A public note on the ticket tells them instead."
            $note += " The email to $cc through $how failed, so a public note tells them instead."
        }
    }

    # ---- the internal note (a failure is a warning: the CC is already added) ----
    try {
        Add-PsaNote -Id $id -Text $note -Title 'CC added'
        $null = $ccActions.Add("Added an internal note to ticket $id.")
        try { if (-not (Test-PsaNoteSaved -Id $id -Text $note)) { Add-CcWarning "The internal note on ticket $id was sent, but reading the ticket back didn't show it yet." } }
        catch { Add-CcWarning "The internal note on ticket $id was sent, but the ticket's notes couldn't be read back to check it: $($_.Exception.Message)" }
    }
    catch { Add-CcWarning "$cc was added, but the internal note on ticket $id couldn't be added: $($_.Exception.Message)" }

    # ---- the public note to the new CC, only when no email went (a failure is a warning) ----
    $sentPublic = ''
    if ($notify -and -not $ccRun.emailed) {
        try {
            Add-PsaNote -Id $id -Text $publicNote -Title 'You have been copied on this ticket' -Public
            $null = $ccActions.Add("Added a public note to ticket $id telling $cc what the ticket is about.")
            $sentPublic = $publicNote
        }
        catch { Add-CcWarning "$cc was added, but the public note on ticket $id couldn't be added, so they weren't told what the ticket is about: $($_.Exception.Message)" }
    }
    return (New-CcResult 'success' "Added $cc to the CC list on ticket $id." -Added $true -CcList $saved.info.cc -Note $note -PublicNote $sentPublic)
}

try {
    $ccOut = Invoke-CcMain (Get-NodeInput)
    $ccRun.done = $true
    Set-NodeOutput $ccOut
}
catch {
    $m = [string]$_.Exception.Message
    if (-not $ccRun.done) {
        $ccRun.done = $true
        Set-NodeOutput (New-CcResult 'error' $m -Note "Add CC to ticket failed: $m")
    }
    throw
}
