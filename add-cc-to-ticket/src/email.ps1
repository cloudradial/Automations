# ---------- src/email.ps1: emailing the new CC the ticket's details ----------
# Uses _shared/postmark.ps1 (Test-PmConfigured, Send-PmMail, ConvertTo-PmHtml), _shared/graph.ps1 (Connect-Graph,
# Invoke-Graph), _shared/psa-tickets.ps1 (ConvertTo-PsaTicketRow) and _shared/psa.ps1.
# Transport, in this order:
#   postmark  the Postmark-ServerToken and Postmark-FromEmail secrets are set: the MSP sends it.
#   graph     the AddCc-NotifySender secret names a mailbox: Graph sendMail from it (Mail.Send, M365-* secrets).
#   ''        neither: no email, and the caller falls back to a public note on the ticket.
# The email only ever carries the ticket's own client-facing fields: never internal notes or technician-only fields.

$CcMail = @{ DescriptionMax = 1500; SenderSecret = 'AddCc-NotifySender'; Tag = 'add-cc' }

# The mailbox named in AddCc-NotifySender, or ''.
function Get-CcMailSender { $v = Get-PmSecret $CcMail.SenderSecret; if ([string]::IsNullOrWhiteSpace($v)) { return '' }; return $v.Trim() }
# 'postmark', 'graph' or ''. Reads secrets only, so a preview can call it.
function Get-CcTransport {
    if (Test-PmConfigured) { return 'postmark' }
    if (Get-CcMailSender) { return 'graph' }
    return ''
}
function Get-CcTransportName { param([string]$T) switch ($T) { 'postmark' { return 'Postmark' } 'graph' { return 'Microsoft 365 (Graph)' } }; return '' }

# Plain text from PSA text: HTML stripped, dashes made hyphens, at most Max characters (then "...").
function Get-CcCleanText {
    param([string]$Text, [int]$Max = 0)
    $t = ConvertTo-PsaPlainText $Text
    $t = ($t -replace "[$([char]0x2013)$([char]0x2014)]", '-' -replace "`r`n", "`n").Trim()
    if ($Max -gt 0 -and $t.Length -gt $Max) { $t = $t.Substring(0, $Max).TrimEnd() + '...' }
    return $t
}

# The ticket's client-facing details for the email: @{ number; summary; status; priority; contactName; companyName;
# opened; description }. A field the PSA doesn't give (or a lookup that fails) is ''. Never throws.
function Get-CcEmailDetails {
    param($Info)
    $d = @{ number = [string]$Info.id; summary = (Get-CcCleanText $Info.summary); status = ''; priority = ''; contactName = (Get-CcCleanText $Info.contactName); companyName = ''; opened = ''; description = '' }
    $c = Get-PsaConn
    $row = $null
    try { $row = ConvertTo-PsaTicketRow $Info.raw } catch { $row = $null }
    if ($null -ne $row) {
        # Autotask shows people its ticket number (T20261008.0001), not the record id.
        if ($c.Psa -eq 'autotask' -and $row.number) { $d.number = [string]$row.number }
        # A status only known by its id (HaloPSA "Status 2") or a placeholder priority isn't worth showing.
        if ($row.status -and $row.status -notmatch '^(Status \d+|\d+)$') { $d.status = Get-CcCleanText $row.status }
        if ($row.priority -and $row.priority -notmatch '^\d+$') { $d.priority = Get-CcCleanText $row.priority }
        if (-not $d.contactName -and $row.contactName) { $d.contactName = Get-CcCleanText $row.contactName }
        if ($row.companyName) { $d.companyName = Get-CcCleanText $row.companyName }
        if ($null -ne $row.created) { $d.opened = $row.created.ToString('d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture) }
        $d.description = [string]$row.description
    }
    # The company name, where the ticket only carries its id. Unverified: GET /Companies/{id} (Autotask) and
    # GET /organizations/{id} (Zendesk), the same reads Resolve-PsaTicketNames uses.
    if (-not $d.companyName -and -not (Test-PsaBlank $Info.companyId)) {
        try {
            switch ($c.Psa) {
                'autotask' { $d.companyName = Get-CcCleanText ([string](Get-PsaPath (Invoke-Psa GET "/Companies/$($Info.companyId)") 'item.companyName')) }
                'zendesk' { $d.companyName = Get-CcCleanText ([string](Get-PsaPath (Invoke-Psa GET "/organizations/$($Info.companyId)") 'organization.name')) }
            }
        }
        catch { $d.companyName = '' }
    }
    # ConnectWise keeps the initial request as the ticket's first note. It is used only when that note isn't internal.
    if ($c.Psa -eq 'connectwise') {
        $d.description = ''
        try {
            $first = @(Get-PsaTicketNotes -Id $Info.id -TextOnly) | Select-Object -First 1
            if ($null -ne $first -and -not $first.internal) { $d.description = [string]$first.text }
        }
        catch { $d.description = '' }
    }
    if (-not $d.description -and $c.Psa -ne 'connectwise') { $d.description = [string]$Info.description }
    $d.description = Get-CcCleanText $d.description $CcMail.DescriptionMax
    return $d
}

# The email to the new CC: @{ subject; text; html }.
function New-CcEmail {
    param($Details, [string]$Asker, [bool]$IncludeDescription = $true)
    $num = $Details.number
    $subject = if ($Details.summary) { "You've been copied on ticket ${num}: $($Details.summary)" } else { "You've been copied on ticket $num" }
    $who = if ($Asker) { $Asker } else { 'Our service desk' }
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in @(@('Ticket', $num), @('Subject', $Details.summary), @('Status', $Details.status), @('Priority', $Details.priority), @('Contact', $Details.contactName), @('Company', $Details.companyName), @('Opened', $Details.opened))) {
        if ($p[1]) { $null = $rows.Add($p) }
    }
    $desc = if ($IncludeDescription) { $Details.description } else { '' }
    $intro = "$who asked for you to be kept up to date on this ticket."
    $next = "You'll now get an email each time the ticket is updated. To add information, reply to any of those update emails."
    $safe = 'Our IT team will never ask for your password by email.'
    $lines = @('Hello,', '', $intro, '')
    $lines += @($rows | ForEach-Object { "$($_[0]): $($_[1])" })
    if ($desc) { $lines += @('', 'The original request:', $desc) }
    $lines += @('', $next, '', $safe)
    $enc = { param([string]$s) (ConvertTo-PmHtml $s) -replace "`n", '<br>' }
    $html = "<p>Hello,</p><p>$(& $enc $intro)</p><p>" + ((@($rows | ForEach-Object { "<strong>$(& $enc $_[0]):</strong> $(& $enc $_[1])" })) -join '<br>') + '</p>'
    if ($desc) { $html += "<p><strong>The original request:</strong><br>$(& $enc $desc)</p>" }
    $html += "<p>$(& $enc $next)</p><p>$(& $enc $safe)</p>"
    return @{ subject = $subject; text = ($lines -join "`n"); html = $html }
}

# Sends the email. Never throws: returns @{ sent; reason }.
function Send-CcEmail {
    param([string]$Transport, [string]$To, $Mail)
    if ($Transport -eq 'postmark') {
        $r = Send-PmMail -To @($To) -Subject $Mail.subject -Text $Mail.text -Html $Mail.html -Tag $CcMail.Tag
        return @{ sent = [bool]$r.sent; reason = [string]$r.reason }
    }
    if ($Transport -eq 'graph') {
        $from = Get-CcMailSender
        try {
            $null = Connect-Graph
            $msg = @{ message = @{ subject = $Mail.subject; body = @{ contentType = 'HTML'; content = $Mail.html }; toRecipients = @(@{ emailAddress = @{ address = $To } }) }; saveToSentItems = $false }
            $null = Invoke-Graph -Method POST -Path "/v1.0/users/$([uri]::EscapeDataString($from))/sendMail" -Body $msg -Permission 'Mail.Send'
            return @{ sent = $true; reason = '' }
        }
        catch { return @{ sent = $false; reason = [string]$_.Exception.Message } }
    }
    return @{ sent = $false; reason = 'No email transport is set up.' }
}
# ---------- end src/email.ps1 ----------
