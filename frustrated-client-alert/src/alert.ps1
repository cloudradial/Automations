# === Step 3: Alert on frustrated clients ===
# Edit this file, then run: node frustrated-client-alert/src/build.js
# Reads the replies from step 1 (ctx) and the AI's scores (score). For each reply scored medium or high it adds
# one internal note to the ticket, marked so a later run never repeats it. Replies at the email level also go into
# one email to the alert address. Writes nothing in preview. The ticket's status, priority and owner never change.

function Read-FcaJson { param($v) if ($null -eq $v) { return $null }; if ($v -isnot [string]) { return $v }; $s = $v.Trim(); if (-not $s) { return $null }; if ($s -match '(?s)\{.*\}') { try { return ($Matches[0] | ConvertFrom-Json) } catch { } }; return $null }

$ctx = Read-FcaJson (Get-NodeInput -Name 'ctx')
if ($null -eq $ctx) { throw 'The alert step got no context from Find new client replies.' }
$warnings = New-Object System.Collections.ArrayList
foreach ($w in @(Get-PsaProp $ctx 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
$replies = @(@(Get-PsaProp $ctx 'replies') | Where-Object { $null -ne $_ })
$preview = [bool](Get-PsaProp $ctx 'preview')
$emailLevel = [string](Get-PsaProp $ctx 'emailLevel')
$alertTo = @(@(Get-PsaProp $ctx 'alertTo') | Where-Object { $_ })

function Write-FcaOutput {
    param([string]$Status, [string]$Message, $Flagged, $Actions)
    Set-NodeOutput ([ordered]@{
            status = $Status; message = $Message; public_note = ''; internal_note = $Message; ticket_id = ''
            preview = $preview; checked = [int](Get-PsaProp $ctx 'ticketsChecked'); scored = $replies.Count
            flagged = @($Flagged); actions = @($Actions); warnings = @($warnings)
        })
}

if (-not $replies.Count) { Write-FcaOutput 'success' "No new client replies in the last $(Get-PsaProp $ctx 'lookbackMinutes') minutes." @() @(); return }

# ---- the AI's scores ----
$ai = Read-FcaJson (Get-NodeInput -Name 'score')
$results = @{}
foreach ($r in @(Get-PsaProp $ai 'results')) {
    if ($null -eq $r) { continue }
    $k = [string](Get-PsaProp $r 'key'); $lv = ([string](Get-PsaProp $r 'level')).Trim().ToLowerInvariant()
    if ($k -and $lv -in @('high', 'medium', 'none')) { $results[$k] = $r }
}
if (-not $results.Count) { $null = $warnings.Add('The AI step gave no readable scores, so no reply was flagged this run.') }

# One alert per ticket per run: several frustrated replies on the same ticket (a client sending three emails in a
# minute) become one note at the highest level, carrying a marker for every reply so none is alerted again.
$flagged = New-Object System.Collections.ArrayList
$byTicket = @{}
$rank = @{ medium = 1; high = 2 }
foreach ($rep in $replies) {
    $k = [string](Get-PsaProp $rep 'key')
    if (-not $results.ContainsKey($k)) { if ($results.Count) { $null = $warnings.Add("The AI step didn't score the reply on ticket #$(Get-PsaProp $rep 'number').") }; continue }
    $r = $results[$k]
    $lv = ([string](Get-PsaProp $r 'level')).Trim().ToLowerInvariant()
    if ($lv -eq 'none') { continue }
    $tid = [string](Get-PsaProp $rep 'ticketId')
    $quote = (Get-PsaText ([string](Get-PsaProp $r 'quote')).Trim() 160)
    $reason = (Get-PsaText ([string](Get-PsaProp $r 'reason')).Trim() 300)
    $created = [string](Get-PsaProp $rep 'created')
    if (-not $byTicket.ContainsKey($tid)) {
        $f = [ordered]@{
            ticketId = $tid; number = [string](Get-PsaProp $rep 'number'); summary = [string](Get-PsaProp $rep 'summary')
            companyName = [string](Get-PsaProp $rep 'companyName'); author = [string](Get-PsaProp $rep 'author'); created = $created
            level = $lv; reason = $reason; quote = $quote; quotes = (New-Object System.Collections.ArrayList); replies = 0
            marker = [string](Get-PsaProp $rep 'marker'); markers = (New-Object System.Collections.ArrayList); email = $false; note = ''; url = ''
        }
        $byTicket[$tid] = $f; $null = $flagged.Add($f)
    }
    $f = $byTicket[$tid]
    $f.replies++
    $null = $f.markers.Add([string](Get-PsaProp $rep 'marker'))
    if ($quote -and -not $f.quotes.Contains($quote)) { $null = $f.quotes.Add($quote) }
    # The highest level wins; at the same level, the newest reply's reason and quote lead.
    if ($rank[$lv] -gt $rank[$f.level] -or ($rank[$lv] -eq $rank[$f.level] -and $created -ge $f.created)) { $f.level = $lv; $f.reason = $reason; if ($quote) { $f.quote = $quote } }
    if ($created -ge $f.created) { $f.created = $created; $f.marker = [string](Get-PsaProp $rep 'marker') }
}
foreach ($f in $flagged) { $f.email = ($emailLevel -eq 'medium' -or ($emailLevel -eq 'high' -and $f.level -eq 'high')) }
if (-not $flagged.Count) { Write-FcaOutput 'success' "Scored $($replies.Count) new client repl$(if ($replies.Count -eq 1) { 'y' } else { 'ies' }); none sounded frustrated." @() @(); return }

$null = Connect-Psa ([string](Get-PsaProp $ctx 'psa'))
$actions = New-Object System.Collections.ArrayList
foreach ($f in $flagged) {
    $f.url = [string](Get-PsaTicketUrl -Id $f.ticketId)
    $label = if ($f.level -eq 'high') { 'Frustrated client' } else { 'Impatient client' }
    $what = if ($f.replies -gt 1) { "the client's last $($f.replies) replies (latest $($f.created)) read" } else { "the client's reply on $($f.created) reads" }
    $lines = @("$label alert: $what as $($f.level) frustration.", "Why: $($f.reason)")
    foreach ($q in @($f.quotes | Select-Object -First 3)) { $lines += "They wrote: `"$q`"" }
    $lines += $(if ($f.level -eq 'high') { 'Suggested next step: call the client today, acknowledge the delay or the repeat issue, and agree the next update time.' } else { 'Suggested next step: reply with a clear status and when they will hear next.' })
    # Add-PsaNote adds the newest reply's marker; the other replies' markers go on lines of their own.
    foreach ($m in @($f.markers | Where-Object { $_ -ne $f.marker })) { $lines += (Get-PsaMarkerTag $m) }
    $f.note = $lines -join "`n"
    if ($preview) { $null = $actions.Add("Preview: would note ticket #$($f.number) ($($f.level))$(if ($f.email) { ' and include it in the alert email' })."); continue }
    try {
        $res = Add-PsaNote -Id $f.ticketId -Text $f.note -Title $label -Internal -Marker $f.marker
        if ($res -eq 'already-present') { $f.email = $false; $null = $actions.Add("Ticket #$($f.number) was already noted by an earlier run.") }
        else { $null = $actions.Add("Added a $($f.level) frustration note to ticket #$($f.number).") }
    }
    catch { $f.email = $false; $null = $warnings.Add("Couldn't add the note to ticket #$($f.number), so it wasn't emailed either (a rerun will try again): $($_.Exception.Message)") }
}

# ---- one email for everything at the email level ----
$toMail = @($flagged | Where-Object { $_.email })
$emailed = $false
if ($toMail.Count -and -not $preview) {
    if (-not $alertTo.Count) { $null = $warnings.Add('No alert address is set (alert_email input or the Sentiment-AlertEmail secret), so the alerts are only on the tickets.') }
    else {
        $subject = if ($toMail.Count -eq 1) { "Frustrated client: #$($toMail[0].number) $(Get-PsaText $toMail[0].summary 60)" } else { "$($toMail.Count) frustrated clients need a call" }
        $txt = @(foreach ($f in $toMail) {
                "#$($f.number) $($f.summary)$(if ($f.companyName) { " ($($f.companyName))" })"
                "  $($f.level): $($f.reason)"
                if ($f.quote) { "  They wrote: `"$($f.quote)`"" }
                if ($f.url) { "  $($f.url)" }
                ''
            }) -join "`n"
        $html = '<p>These client replies sound frustrated. Each ticket has an internal note with the details.</p><ul>' + (@(foreach ($f in $toMail) {
                    $title = ConvertTo-PmHtml "#$($f.number) $($f.summary)"
                    $link = if ($f.url) { "<a href=`"$(ConvertTo-PmHtml $f.url)`">$title</a>" } else { $title }
                    "<li><strong>$link</strong>$(if ($f.companyName) { ' (' + (ConvertTo-PmHtml $f.companyName) + ')' })<br>$(ConvertTo-PmHtml "$($f.level): $($f.reason)")$(if ($f.quote) { '<br><em>' + (ConvertTo-PmHtml "`"$($f.quote)`"") + '</em>' })</li>"
                }) -join '') + '</ul>'
        $mail = Send-PmMail -To $alertTo -Subject $subject -Text $txt -Html $html -Tag 'frustrated-client-alert'
        if ($mail.sent) { $emailed = $true; $null = $actions.Add("Emailed $($alertTo -join ', ') about $($toMail.Count) ticket(s).") }
        else { $null = $warnings.Add("The alert email wasn't sent: $($mail.reason). The notes are on the tickets.") }
    }
}
if ($toMail.Count -and $preview) { $null = $actions.Add("Preview: would email $(if ($alertTo.Count) { $alertTo -join ', ' } else { 'nobody (no alert address is set)' }) about $($toMail.Count) ticket(s).") }

$high = @($flagged | Where-Object { $_.level -eq 'high' }).Count
$msg = "$(if ($preview) { 'Preview: ' })$($flagged.Count) ticket(s) with a frustrated client ($high high), from $($replies.Count) new client repl$(if ($replies.Count -eq 1) { 'y' } else { 'ies' })$(if ($emailed) { '; the alert email was sent' })."
$status = if ($preview) { 'pending_confirmation' } elseif ($warnings.Count) { 'partial' } else { 'success' }
Write-FcaOutput $status $msg @($flagged) @($actions)
