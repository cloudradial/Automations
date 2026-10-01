# Reads the request, the routing table (two CloudRadial KB articles) and the ticket.
# Writes nothing. Its output feeds the classifier and the Assign step.
$in = Get-NodeInput
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
$b = Get-Prop $in 'body'; if ($null -ne $b -and ($b -is [string] -or $null -ne (Get-Prop $b 'ticketId') -or $null -ne (Get-Prop $b 'id'))) { $in = $b }
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }

$warnings = New-Object System.Collections.ArrayList; $actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'ok'; message = ''; internal_note = ''; skip = $false
    ticketId = ''; psa = ''; confirm = $false; reassign = $false; triggerSource = ''
    summary = ''; description = ''; currentAssignee = ''; skillList = ''; roles = ''
    table = $null; warnings = @(); actions = @()
}
function Stop-Prepare { param([string]$Status, [string]$Msg)
    $out.status = $Status; $out.message = $Msg; $out.internal_note = $Msg; $out.skip = $true
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}
# A value is missing when it's blank or still an unreplaced placeholder (@token or {{field}}).
function Get-In { param([string[]]$Names)
    foreach ($n in $Names) {
        $v = if ($n -like '*.*') { Get-Path $in $n } else { Get-Prop $in $n }
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject]) { continue }
        $s = ([string]$v).Trim()
        if ($s -eq '' -or $s.StartsWith('@') -or $s.StartsWith('{{')) { continue }
        return $s
    }
    return ''
}
function Test-Yes { param([string]$v) return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }

try {
    if ($null -eq $in) { Stop-Prepare 'incomplete' 'No request body was received. Send {"ticketId":"..."} or the PSA ticket.'; return }

    # ---------- 1. the request ----------
    $out.ticketId = Get-In @('ticketId', 'id', 'ticketID', 'TicketID', 'TicketId', 'Id', 'ticket.id', 'Ticket.TicketId', 'ticket_id')
    $out.triggerSource = Get-In @('triggerSource')
    $out.confirm = Test-Yes (Get-In @('confirm'))
    $out.reassign = Test-Yes (Get-In @('reassign'))
    $psa = (Get-In @('psa')).ToLowerInvariant(); if (-not $psa) { $psa = ([string](Secret 'PSA-Type')).Trim().ToLowerInvariant() }
    $out.psa = $psa
    if (-not $out.ticketId) { Stop-Prepare 'incomplete' 'No ticket id was found in ticketId, id, ticketID, TicketID or ticket.id. Nothing was assigned.'; return }
    if (-not $psa) { Stop-Prepare 'incomplete' 'No PSA was given. Send psa, or set the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk).'; return }
    if (-not $script:PsaSecrets.ContainsKey($psa)) { Stop-Prepare 'incomplete' "psa '$psa' isn't one of: connectwise, autotask, halopsa, kaseyabms, syncro, zendesk."; return }

    # ---------- 2. the routing table ----------
    $companyId = Get-In @('routingCompanyId'); if (-not $companyId) { $companyId = ([string](Secret 'Routing-CompanyId')).Trim() }
    if ($companyId -notmatch '^\d+$') { Stop-Prepare 'incomplete' 'No routing company was given. Set the Routing-CompanyId secret to the CloudRadial company id that holds the routing articles.'; return }
    $skillsSubject = Get-In @('skillsArticle'); if (-not $skillsSubject) { $skillsSubject = 'Ticket Routing: Skills' }
    $engSubject = Get-In @('engineersArticle'); if (-not $engSubject) { $engSubject = 'Ticket Routing: Engineers and Settings' }

    $crBase = [string](Secret 'CloudRadial-BaseUrl'); $crPub = Secret 'CloudRadial-PublicKey'; $crPriv = Secret 'CloudRadial-PrivateKey'
    if (-not $crBase -or -not $crPub -or -not $crPriv) { Stop-Prepare 'error' 'Add these secrets to the runner Key Vault: CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey'; return }
    $crHeaders = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPub):$($crPriv)")); Accept = 'application/json' }
    $crBase = $crBase.TrimEnd('/')
    function Get-Article { param([string]$Subject)
        $f = "companyId eq $companyId and subject eq '$($Subject -replace "'", "''")'"
        $list = @(Get-Prop (Invoke-RestMethod -Method GET -Uri "$crBase/v2/odata/article?`$filter=$([uri]::EscapeDataString($f))&`$select=articleId,subject" -Headers $crHeaders) 'value' | Where-Object { $null -ne $_ })
        if (-not $list.Count) { return $null }
        if ($list.Count -gt 1) { $null = $warnings.Add("$($list.Count) articles in company $companyId are titled '$Subject'. The first one was used.") }
        $a = Invoke-RestMethod -Method GET -Uri "$crBase/v2/article/$(Get-Prop $list[0] 'articleId')" -Headers $crHeaders
        $body = Get-Prop $a 'body'; if ($null -eq $body) { $body = Get-Path $a 'data.body' }
        return [string]$body
    }
    $skillsHtml = Get-Article $skillsSubject
    $engHtml = Get-Article $engSubject
    $missingArticles = @(); if ($null -eq $skillsHtml) { $missingArticles += "'$skillsSubject'" }; if ($null -eq $engHtml) { $missingArticles += "'$engSubject'" }
    if ($missingArticles.Count) { Stop-Prepare 'incomplete' "The routing table wasn't found: no article titled $($missingArticles -join ' or ') in CloudRadial company $companyId. Nothing was assigned."; return }

    $sk = Split-RoutingSections (ConvertFrom-ArticleBody $skillsHtml)
    $en = Split-RoutingSections (ConvertFrom-ArticleBody $engHtml)
    # Skills come from the skills article; engineers and settings from the other. A section in the wrong article still counts.
    $skillLines = if (@(Select-FromHeader @($sk.Skills) 'Skill').Count) { @($sk.Skills) } else { @($en.Skills) }
    $engLines = if ($en.Engineers.Count) { @($en.Engineers) } else { @($sk.Engineers) }
    $setLines = @($en.Settings) + @($sk.Settings)
    $table = Read-RoutingTable $skillLines $engLines $setLines
    $check = Test-RoutingData $table $psa
    foreach ($w in @($check.Warnings)) { $null = $warnings.Add($w) }
    if ($check.Errors.Count) { Stop-Prepare 'incomplete' ("The routing table has errors, so nothing was assigned. Fix them in the KB articles (Test-RoutingTable.ps1 shows the same list):`n- " + ($check.Errors -join "`n- ")); return }
    $null = $actions.Add("Read the routing table: $(@($table.Skills).Count) skills rows, $(@($table.Engineers).Count) engineers")

    # ---------- 3. the ticket ----------
    $null = Connect-Psa $psa
    $ticket = Get-PsaTicket $out.ticketId
    $null = $actions.Add("Read ticket $($out.ticketId) from $psa")
    $out.summary = $ticket.summary
    $d = [string]$ticket.description
    $d = ($d -replace '(?is)<(script|style)[^>]*>.*?</\1>', '' -replace '<[^>]+>', ' ' -replace '[ \t]{2,}', ' ').Trim()
    if ($d.Length -gt 4000) { $d = $d.Substring(0, 4000) }
    $out.description = $d
    $out.currentAssignee = $ticket.assigneeId
    $out.table = [ordered]@{
        settings = $table.Settings
        engineers = @($table.Engineers)
        rows = @($table.Skills | Where-Object { $_.Skill -and $_.Skill -ne 'Role only' } | ForEach-Object { [ordered]@{ s = $_.Skill; r = $_.Role; e = $_.Engineer } })
    }
    $out.skillList = Get-ClassifierSkillList $table
    $out.roles = (@($table.Skills | ForEach-Object { $_.Role } | Where-Object { $_ } | Select-Object -Unique) -join ', ')

    if ($ticket.assigneeId -and -not $out.reassign) {
        $who = @($table.Engineers | Where-Object { $_.PsaUserId -eq $ticket.assigneeId -or @($ticket.assigneeIds) -contains $_.PsaUserId } | ForEach-Object { $_.Engineer }) | Select-Object -First 1
        Stop-Prepare 'rejected' "Ticket $($out.ticketId) is already assigned to $(if ($who) { $who } else { "PSA user $($ticket.assigneeId)" }), so it was left alone. Send reassign true to route it anyway."
        return
    }
    if (-not $out.summary -and -not $out.description) { Stop-Prepare 'incomplete' "Ticket $($out.ticketId) has no summary or description to classify."; return }

    $out.message = "Ticket $($out.ticketId) read; ready to classify."
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
} catch {
    Stop-Prepare 'error' "Couldn't read the request, routing table or ticket: $($_.Exception.Message)"
}
