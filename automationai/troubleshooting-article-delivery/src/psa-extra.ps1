# ---------- troubleshooting-article-delivery/src/psa-extra.ps1: PSA calls _shared/psa.ps1 doesn't have yet ----------
# Candidate to move into automationai/_shared/psa.ps1. Needs _shared/psa.ps1 pasted above it (Connect-Psa, Invoke-Psa).
# Edit this file, then run: node src/build.js
# Only the ConnectWise, Syncro and Zendesk note reads follow PSA.md's [vendor docs] rows; the rest say "Unverified".

# The ticket's notes, newest last where the PSA says, as @(@{ text; internal }), or $null when they can't be read.
# internal is $true, $false, or $null when the PSA doesn't say.
function Get-PsaNotes {
    param([string]$Id)
    $c = Get-PsaConn
    $rows = @()
    switch ($c.Psa) {
        'connectwise' {
            # PSA.md [vendor docs]: GET /service/tickets/{id}/notes. internalAnalysisFlag marks the Internal tab.
            $r = @(Invoke-Psa GET "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=200")
            $rows = @(foreach ($n in @($r | Where-Object { $null -ne $_ })) { @{ text = [string](Get-PsaProp $n 'text'); internal = ((Get-PsaProp $n 'internalAnalysisFlag') -eq $true) } })
        }
        'autotask' {
            # Unverified: TicketNotes query on ticketID. publish is a per-tenant picklist, so internal is left unknown.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$Id }); MaxRecords = 500 }
            $r = Invoke-Psa GET "/TicketNotes/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))"
            $rows = @(foreach ($n in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) { @{ text = "$([string](Get-PsaProp $n 'title'))`n$([string](Get-PsaProp $n 'description'))"; internal = $null } })
        }
        'halopsa' {
            # Unverified: GET /api/Actions?ticket_id= returns { actions: [...] } with note and hiddenfromuser.
            $r = Invoke-Psa GET "/Actions?ticket_id=$Id&count=200"
            $list = @(Get-PsaProp $r 'actions'); if (-not @($list | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $list = @($r) }
            $rows = @(foreach ($n in @($list | Where-Object { $null -ne $_ })) { @{ text = [string](Get-PsaProp $n 'note'); internal = ((Get-PsaProp $n 'hiddenfromuser') -eq $true) } })
        }
        'kaseyabms' {
            # Unverified: GET /v2/servicedesk/tickets/{id}/notes returns Result [{ Details, IsInternal }].
            $r = Invoke-Psa GET "/servicedesk/tickets/$Id/notes"
            $rows = @(foreach ($n in @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })) { @{ text = [string](Get-PsaProp $n 'Details'); internal = ((Get-PsaProp $n 'IsInternal') -eq $true) } })
        }
        'syncro' {
            # PSA.md [vendor docs]: the ticket carries its comments; hidden marks a private one.
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$Id") 'ticket'
            $rows = @(foreach ($n in @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ })) { @{ text = "$([string](Get-PsaProp $n 'subject'))`n$([string](Get-PsaProp $n 'body'))"; internal = ((Get-PsaProp $n 'hidden') -eq $true) } })
        }
        'zendesk' {
            # Zendesk docs: GET /tickets/{id}/comments returns { comments: [{ body, public }] }.
            $r = Invoke-Psa GET "/tickets/$Id/comments?per_page=100"
            $rows = @(foreach ($n in @(Get-PsaProp $r 'comments' | Where-Object { $null -ne $_ })) { @{ text = [string](Get-PsaProp $n 'body'); internal = ((Get-PsaProp $n 'public') -eq $false) } })
        }
        default { return $null }
    }
    # The comma keeps an empty list a list (otherwise the caller would get $null, which means "can't read").
    return ,@($rows)
}
# ---------- end troubleshooting-article-delivery/src/psa-extra.ps1 ----------
