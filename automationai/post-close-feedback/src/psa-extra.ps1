# ---------- src/psa-extra.ps1: PSA calls _shared/psa.ps1 doesn't have yet ----------
# Candidate to move into automationai/_shared/psa.ps1. It needs _shared/psa.ps1 pasted above it
# (Connect-Psa, Invoke-Psa, Get-PsaConn, Get-PsaProp, Get-PsaAtPicklist, Get-PsaSecret).
# Calls marked "Unverified" are not in reference/build-kit/PSA.md yet. Check each one against a real
# tenant before the first live run, then record it in PSA.md.

# Plain text from a note body that may be HTML.
function ConvertTo-PsaPlainText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text -replace '(?i)<br\s*/?>', "`n" -replace '(?i)</p>', "`n" -replace '<[^>]+>', ''
    $t = $t -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
    return ($t -replace "(`r?`n){3,}", "`n`n").Trim()
}

# Notes on a ticket, newest first: @(@{ text; public; created; raw }).
# public is $true when the client can see the note.
function Get-PsaNotes {
    param([string]$Id, [int]$Max = 50)
    $c = Get-PsaConn
    $rows = New-Object System.Collections.ArrayList
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: list form of GET /service/tickets/{id}/notes (PSA.md has the first-note read only).
            foreach ($n in @(Invoke-Psa GET "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=$Max")) {
                if ($null -eq $n) { continue }
                $pub = (Get-PsaProp $n 'detailDescriptionFlag') -eq $true -or (Get-PsaProp $n 'resolutionFlag') -eq $true
                $null = $rows.Add(@{ text = [string](Get-PsaProp $n 'text'); public = $pub; created = [string](Get-PsaProp $n 'dateCreated'); raw = $n })
            }
        }
        'autotask' {
            # Unverified: the Tickets/{id}/Notes child collection read. Internal notes are the publish values whose label says Internal.
            $internal = @(Get-PsaAtPicklist 'TicketNotes' 'publish' | Where-Object { [string](Get-PsaProp $_ 'label') -match '(?i)internal' } | ForEach-Object { [string](Get-PsaProp $_ 'value') })
            $r = Invoke-Psa GET "/Tickets/$Id/Notes"
            foreach ($n in @(Get-PsaProp $r 'items')) {
                if ($null -eq $n) { continue }
                $pub = $internal -notcontains [string](Get-PsaProp $n 'publish')
                $null = $rows.Add(@{ text = [string](Get-PsaProp $n 'description'); public = $pub; created = [string](Get-PsaProp $n 'createDateTime'); raw = $n })
            }
        }
        'halopsa' {
            # Unverified: GET /api/Actions?ticket_id= returns { actions: [...] } with note, hiddenfromuser and datetime.
            $r = Invoke-Psa GET "/Actions?ticket_id=$Id&count=$Max"
            $list = @(Get-PsaProp $r 'actions'); if (-not @($list | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $list = @($r) }
            foreach ($n in $list) {
                if ($null -eq $n) { continue }
                $txt = [string](Get-PsaProp $n 'note'); if (-not $txt) { $txt = [string](Get-PsaProp $n 'note_html') }
                $null = $rows.Add(@{ text = (ConvertTo-PsaPlainText $txt); public = ((Get-PsaProp $n 'hiddenfromuser') -ne $true); created = [string](Get-PsaProp $n 'datetime'); raw = $n })
            }
        }
        'kaseyabms' {
            # Unverified: GET /v2/servicedesk/tickets/{id}/notes returns Result: [{ Details, IsInternal, NoteDate }].
            $r = Invoke-Psa GET "/servicedesk/tickets/$Id/notes"
            foreach ($n in @(Get-PsaProp $r 'Result')) {
                if ($null -eq $n) { continue }
                $null = $rows.Add(@{ text = [string](Get-PsaProp $n 'Details'); public = ((Get-PsaProp $n 'IsInternal') -ne $true); created = [string](Get-PsaProp $n 'NoteDate'); raw = $n })
            }
        }
        'syncro' {
            # Comments come with the ticket (PSA.md, Get ticket).
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$Id") 'ticket'
            foreach ($n in @(Get-PsaProp $t 'comments')) {
                if ($null -eq $n) { continue }
                $null = $rows.Add(@{ text = [string](Get-PsaProp $n 'body'); public = ((Get-PsaProp $n 'hidden') -ne $true); created = [string](Get-PsaProp $n 'created_at'); raw = $n })
            }
        }
        'zendesk' {
            # GET /tickets/{id}/comments returns { comments: [{ body, public, created_at }] } (vendor docs).
            $r = Invoke-Psa GET "/tickets/$Id/comments?sort_order=desc"
            foreach ($n in @(Get-PsaProp $r 'comments')) {
                if ($null -eq $n) { continue }
                $null = $rows.Add(@{ text = [string](Get-PsaProp $n 'body'); public = ((Get-PsaProp $n 'public') -eq $true); created = [string](Get-PsaProp $n 'created_at'); raw = $n })
            }
        }
    }
    # Newest first. Notes without a readable date keep the order the PSA returned.
    $i = 0
    $keyed = @(foreach ($r in $rows) { $d = [datetime]::MinValue; if ($r.created) { $null = [datetime]::TryParse($r.created, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d) }; $i++; [pscustomobject]@{ d = $d; i = $i; n = $r } })
    if (@($keyed | Where-Object { $_.d -ne [datetime]::MinValue }).Count -eq $keyed.Count -and $keyed.Count) { $keyed = @($keyed | Sort-Object -Property @{ Expression = 'd'; Descending = $true }, @{ Expression = 'i'; Descending = $false }) }
    return @($keyed | Select-Object -First $Max | ForEach-Object { $_.n })
}

# A link a technician can open, or '' when this PSA's link can't be worked out.
# -Template wins: {id} (or {ticketId}) is replaced with the ticket id.
function Get-PsaTicketUrl {
    param([string]$Id, [string]$Template = '')
    if ($Template -and -not $Template.StartsWith('@')) { return ($Template -replace '\{(id|ticketId)\}', [uri]::EscapeDataString($Id)) }
    $c = Get-PsaConn
    $u = $null; try { $u = [uri]$c.Base } catch { return '' }
    $root = "$($u.Scheme)://$($u.Host)"
    switch ($c.Psa) {
        # Unverified: the ConnectWise ticket screen link, with the api- prefix of cloud hosts removed.
        'connectwise' { return "$($root -replace '://api-', '://')/v4_6_release/services/system_io/Service/fv_sr100_request.rpt?service_recid=$Id" }
        # Unverified: the web UI host mirrors the API zone host (webservices5 -> ww5).
        'autotask' { return "$($root -replace '://webservices', '://ww')/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=$Id" }
        # Unverified: the HaloPSA agent ticket link.
        'halopsa' { return "$root/ticket?id=$Id" }
        'kaseyabms' { return '' }
        # Unverified: the Syncro ticket page.
        'syncro' { return "$root/tickets/$Id" }
        'zendesk' { return "$root/agent/tickets/$Id" }
    }
    return ''
}

# A readable status name. Autotask and HaloPSA hand out status ids; the others already use names.
function Get-PsaStatusName {
    param([string]$Status)
    $s = ([string]$Status).Trim()
    if ($s -notmatch '^\d+$') { return $s }
    $c = Get-PsaConn
    switch ($c.Psa) {
        'autotask' {
            $hit = @(Get-PsaAtPicklist 'Tickets' 'status' | Where-Object { [string](Get-PsaProp $_ 'value') -eq $s }) | Select-Object -First 1
            if ($hit) { return [string](Get-PsaProp $hit 'label') }
        }
        'halopsa' {
            # Unverified: GET /api/Status/{id} returns { id, name }.
            try { $r = Invoke-Psa GET "/Status/$s"; $n = [string](Get-PsaProp $r 'name'); if ($n) { return $n } } catch { }
        }
    }
    return $s
}
# ---------- end src/psa-extra.ps1 ----------
