# ---------- src/cc.ps1: a ticket's contact and CC list, and adding a CC, for six PSAs ----------
# Uses Connect-Psa, Invoke-Psa, Get-PsaTicket, Invoke-PsaAtQuery and the Get-Psa* helpers from _shared/psa.ps1.
# Every call here is taken from the vendor's published API reference. None has been proven by a live run yet,
# so each is marked "Unverified"; check them on a test ticket before the first live write.
#   ConnectWise  ticket automaticEmailCc (a ";" list, at most 1000 characters) and automaticEmailCcFlag, by json-patch
#   Autotask     TicketAdditionalContacts: only an existing contact of the ticket's company can be added
#   HaloPSA      ticket emailcclist, updated with POST /Tickets
#   Kaseya BMS   ticket Ccs (a list of { Id, EmailAddress, EntityType }), by json-patch
#   Syncro       no ticket CC in the API, so nothing is changed
#   Zendesk      email_ccs with action "put" on PUT /tickets/{id}

$CcState = @{ CwMaxLength = 1000; AtMaxContacts = 30 }

# The addresses in a ";" or "," separated list (or an array), trimmed, blanks dropped.
function Get-CcEmailList {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -isnot [string]) { return @(@($Value) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) }
    return @(($Value -split '[;,\s]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
function Test-CcSame { param([string]$A, [string]$B) return (([string]$A).Trim() -ieq ([string]$B).Trim() -and ([string]$A).Trim() -ne '') }
function Test-CcIn { param([string]$Email, $List) foreach ($e in @($List)) { if (Test-CcSame $e $Email) { return $true } }; return $false }
# One email address, nothing else: no lists, no spaces, no display name.
function Test-CcEmail {
    param([string]$s)
    if (-not $s -or $s.Length -gt 254) { return $false }
    return ($s -match '^[A-Za-z0-9!#$%&''*+/=?^_`{|}~.-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
}

# '' when the PSA can add a CC, otherwise the plain sentence that ends the run.
function Get-CcUnsupported {
    param([string]$Psa)
    # Vendor docs (Syncro swagger): the ticket update body has no CC or extra-recipient field, and the ticket has none.
    if ($Psa -eq 'syncro') { return "Syncro's API has no way to add a CC to a ticket, so nothing was changed." }
    return ''
}

# The ConnectWise contact's email: the default Email communication item, else the first one.
function Get-CcCwContactEmail {
    param([string]$ContactId)
    # Unverified: GET /company/contacts/{id} and its communicationItems (the same read _shared/psa-tickets.ps1 uses).
    $ct = Invoke-PsaRead "/company/contacts/$ContactId" 'read contacts' 'read companies and contacts'
    $items = @(Get-PsaProp $ct 'communicationItems' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'communicationType') -eq 'Email' })
    $pick = @(@($items | Where-Object { (Get-PsaProp $_ 'defaultFlag') -eq $true }) + $items) | Select-Object -First 1
    if ($pick) { return [string](Get-PsaProp $pick 'value') }
    return ''
}

# A ticket's company, contact email and CC list:
#   @{ id; companyId; companyKeys; contactEmail; cc = @(emails); ccEnabled; raw; extra = @{ ...PSA-specific... } }
# ccEnabled is $false only on ConnectWise when the ticket's "CC" checkbox (automaticEmailCcFlag) is off.
function Get-CcTicket {
    param([string]$Id)
    $c = Get-PsaConn
    $t = Get-PsaTicket $Id
    $raw = $t.raw
    $info = @{ id = $Id; companyId = ([string]$t.companyId).Trim(); companyKeys = @(); contactEmail = ''; cc = @(); ccEnabled = $true; raw = $raw; extra = @{} }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: contactEmailAddress, automaticEmailCc and automaticEmailCcFlag on GET /service/tickets/{id} (CW swagger Ticket model).
            $info.contactEmail = [string](Get-PsaProp $raw 'contactEmailAddress')
            $cid = [string](Get-PsaPath $raw 'contact.id')
            if (-not $info.contactEmail -and -not (Test-PsaBlank $cid)) { $info.contactEmail = Get-CcCwContactEmail $cid }
            $info.cc = @(Get-CcEmailList ([string](Get-PsaProp $raw 'automaticEmailCc')))
            # Unverified: whether CloudRadial's @CompanyPsaId for ConnectWise is the company recid or its identifier, so both match.
            $info.companyKeys = @([string](Get-PsaPath $raw 'company.identifier'))
            $info.ccEnabled = ((Get-PsaProp $raw 'automaticEmailCcFlag') -eq $true)
        }
        'autotask' {
            # Unverified: the ticket's contactID read through GET /Contacts/{id}, and the TicketAdditionalContacts query by ticketID.
            $cid = Get-PsaProp $raw 'contactID'
            if (-not (Test-PsaBlank $cid)) { $info.contactEmail = [string](Get-PsaPath (Invoke-PsaRead "/Contacts/$cid" 'read contacts' 'read contacts') 'item.emailAddress') }
            $rows = @(Invoke-PsaAtQuery 'TicketAdditionalContacts' @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$Id }) @() 100 'read the ticket''s additional contacts')
            $ids = @($rows | ForEach-Object { [string](Get-PsaProp $_ 'contactID') } | Where-Object { -not (Test-PsaBlank $_) })
            $info.extra.additionalIds = $ids
            if ($ids.Count) {
                # Unverified: the "in" filter on Contacts id.
                $cts = @(Invoke-PsaAtQuery 'Contacts' @([ordered]@{ op = 'in'; field = 'id'; value = @($ids | ForEach-Object { [long]$_ }) }) @() 100 'read contacts')
                $info.cc = @($cts | ForEach-Object { [string](Get-PsaProp $_ 'emailAddress') } | Where-Object { $_ })
            }
        }
        'halopsa' {
            # Unverified: user_email, user_id and emailcclist on GET /Tickets/{id} (Halo TicketDto), and GET /Users/{id} emailaddress.
            $info.contactEmail = [string](Get-PsaProp $raw 'user_email')
            $uid = Get-PsaProp $raw 'user_id'
            if (-not $info.contactEmail -and -not (Test-PsaBlank $uid)) { $info.contactEmail = [string](Get-PsaProp (Invoke-PsaRead "/Users/$uid" 'read users' 'read users') 'emailaddress') }
            $info.cc = @(Get-CcEmailList ([string](Get-PsaProp $raw 'emailcclist')))
        }
        'kaseyabms' {
            # Unverified: ContactEmail and CCs ({ Id, EmailAddress, FullName, EntityType }) on GET /v2/servicedesk/tickets/{id} (BMS swagger TicketOutputDto).
            $info.contactEmail = [string](Get-PsaProp $raw 'ContactEmail')
            $ccs = @(Get-PsaProp $raw 'CCs' | Where-Object { $null -ne $_ })
            $info.extra.ccs = $ccs
            $info.cc = @($ccs | ForEach-Object { [string](Get-PsaProp $_ 'EmailAddress') } | Where-Object { $_ })
        }
        'zendesk' {
            # Vendor docs: requester_id and email_cc_ids on the ticket; GET /users/show_many?ids= for their addresses. Unverified live.
            $req = [string](Get-PsaProp $raw 'requester_id')
            $ccIds = @(Get-PsaProp $raw 'email_cc_ids' | Where-Object { -not (Test-PsaBlank $_) } | ForEach-Object { [string]$_ })
            $ids = @(@($req) + $ccIds | Where-Object { -not (Test-PsaBlank $_) } | Select-Object -Unique)
            $mail = @{}
            if ($ids.Count) {
                $r = Invoke-PsaRead "/users/show_many?ids=$($ids -join ',')" 'read users' 'read users'
                foreach ($u in @(Get-PsaProp $r 'users' | Where-Object { $null -ne $_ })) { $mail[[string](Get-PsaProp $u 'id')] = [string](Get-PsaProp $u 'email') }
            }
            if ($req -and $mail.ContainsKey($req)) { $info.contactEmail = $mail[$req] }
            $info.cc = @($ccIds | Where-Object { $mail.ContainsKey($_) -and $mail[$_] } | ForEach-Object { $mail[$_] })
        }
        default { throw "$(Get-PsaName) can't add a CC to a ticket." }
    }
    $info.contactEmail = $info.contactEmail.Trim()
    $info.companyKeys = @(@($info.companyId) + @($info.companyKeys) | Where-Object { -not (Test-PsaBlank $_) })
    return $info
}

# Works out the change without making it (reads only), so a preview shows the same result a real run would.
# Returns @{ ok; why; list = @(the CC list after the change); detail; contactId; ccs }.
function Get-CcPlan {
    param($Info, [string]$Email)
    $c = Get-PsaConn
    $list = @($Info.cc)
    if (-not (Test-CcIn $Email $list)) { $list += $Email }
    $plan = @{ ok = $true; why = ''; list = $list; detail = ''; contactId = ''; ccs = @() }
    switch ($c.Psa) {
        'connectwise' {
            $text = $list -join ';'
            if ($text.Length -gt $CcState.CwMaxLength) { $plan.ok = $false; $plan.why = "Ticket $($Info.id)'s CC list is full (ConnectWise allows $($CcState.CwMaxLength) characters), so nothing was changed." }
            $plan.detail = $(if (Test-CcIn $Email $Info.cc) { 'turn on the ticket''s CC setting' } else { "add $Email to the ticket's CC list and turn on its CC setting" })
        }
        'autotask' {
            # Autotask copies contacts, not bare addresses: the address must belong to an active contact of the ticket's company.
            if ($Info.extra.additionalIds.Count -ge $CcState.AtMaxContacts) { $plan.ok = $false; $plan.why = "Ticket $($Info.id) already has $($CcState.AtMaxContacts) additional contacts, the most Autotask allows, so nothing was changed."; break }
            if (Test-PsaBlank $Info.companyId) { $plan.ok = $false; $plan.why = "Ticket $($Info.id) has no company in Autotask, so no contact can be added to it."; break }
            # Unverified: the Contacts query on companyID, emailAddress and isActive.
            $hit = @(Invoke-PsaAtQuery 'Contacts' @(
                    [ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$Info.companyId },
                    [ordered]@{ op = 'eq'; field = 'emailAddress'; value = $Email },
                    [ordered]@{ op = 'eq'; field = 'isActive'; value = 1 }) @() 5 'read contacts') | Select-Object -First 1
            if (-not $hit) { $plan.ok = $false; $plan.why = "Autotask can only copy contacts of the ticket's company onto a ticket, and $Email isn't one, so nothing was changed."; break }
            $plan.contactId = [string](Get-PsaProp $hit 'id')
            $plan.detail = "add contact $($plan.contactId) ($Email) to the ticket's additional contacts"
        }
        'halopsa' { $plan.detail = "add $Email to the ticket's email CC list" }
        'kaseyabms' {
            # Map the CCs already on the ticket to the input shape, then add the new one. A known contact or employee of the
            # account is added by its Id and EntityType; any other address is added as a bare email address.
            $ccs = @(foreach ($x in @($Info.extra.ccs)) { [ordered]@{ Id = (Get-PsaProp $x 'Id'); EmailAddress = [string](Get-PsaProp $x 'EmailAddress'); EntityType = (Get-PsaProp $x 'EntityType') } })
            $new = [ordered]@{ Id = $null; EmailAddress = $Email }
            if (-not (Test-PsaBlank $Info.companyId)) {
                # Unverified: GET /v2/servicedesk/tickets/ticketCcs/{accountId} with Filter.SearchString lists the people that can be copied.
                $found = $null
                try { $found = @(Get-PsaBmsList (Invoke-Psa GET "/servicedesk/tickets/ticketCcs/$($Info.companyId)?Filter.SearchString=$(ConvertTo-PsaQuery $Email)&PageSize=20") | Where-Object { Test-CcSame ([string](Get-PsaProp $_ 'EmailAddress')) $Email }) | Select-Object -First 1 }
                catch { Add-PsaWarning "Kaseya BMS wouldn't list the people that can be copied on ticket $($Info.id), so $Email is added as an email address. ($($_.Exception.Message))" }
                if ($found) { $new = [ordered]@{ Id = (Get-PsaProp $found 'Id'); EmailAddress = $Email; EntityType = (Get-PsaProp $found 'EntityType') } }
            }
            $plan.ccs = @($ccs) + @($new)
            $plan.detail = "add $Email to the ticket's CC list"
        }
        'zendesk' { $plan.detail = "add $Email to the ticket's email CCs" }
    }
    return $plan
}

# Makes the change in Get-CcPlan. Throws the PSA's own error text (from Invoke-Psa) when the PSA refuses it.
function Send-CcChange {
    param($Info, [string]$Email, $Plan)
    $c = Get-PsaConn
    $id = $Info.id
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: json-patch replace on automaticEmailCc and automaticEmailCcFlag.
            $null = Invoke-Psa PATCH "/service/tickets/$id" @(
                [ordered]@{ op = 'replace'; path = 'automaticEmailCc'; value = ($Plan.list -join ';') },
                [ordered]@{ op = 'replace'; path = 'automaticEmailCcFlag'; value = $true })
        }
        # Unverified: POST /Tickets/{id}/AdditionalContacts (the TicketAdditionalContacts child of Tickets).
        'autotask' { $null = Invoke-Psa POST "/Tickets/$id/AdditionalContacts" ([ordered]@{ ticketID = [long]$id; contactID = [long]$Plan.contactId }) }
        # Unverified: POST /Tickets with id and emailcclist updates the ticket's CC list.
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$id; emailcclist = ($Plan.list -join ';') }) }
        # Unverified: json-patch replace on /Ccs (TicketInputDto.Ccs).
        'kaseyabms' { $null = Invoke-Psa PATCH "/servicedesk/tickets/$id" @([ordered]@{ op = 'replace'; path = '/Ccs'; value = @($Plan.ccs) }) }
        # Vendor docs: email_ccs with action "put" adds the address (and creates the user when needed). Unverified live.
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$id" @{ ticket = @{ email_ccs = @([ordered]@{ user_email = $Email; action = 'put' }) } } }
    }
}
# $true when the ticket, read again, has the address on its CC list (and, on ConnectWise, the CC setting on).
function Test-CcSaved {
    param([string]$Id, [string]$Email)
    $after = Get-CcTicket $Id
    return @{ ok = ((Test-CcIn $Email $after.cc) -and $after.ccEnabled); info = $after }
}
# ---------- end src/cc.ps1 ----------
