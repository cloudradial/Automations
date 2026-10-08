# Step 3: Post the update to the requester.
# Takes the AI-written update, or a fixed template for the new status when the AI answer is empty or
# unusable, and posts it as a public note so the PSA emails the requester.
# With preview=true it returns the update (status pending_confirmation) and posts nothing.
$stopState = @{ done = $false }
$in = Get-NodeInput
$ctx = Read-StepJson (Get-StepProp $in 'ctx')
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; $tid = ''; if ($null -ne $ctx -and $null -ne $ctx.PSObject.Properties['ticket_id']) { $tid = [string]$ctx.ticket_id }; Set-NodeOutput ([ordered]@{ status = 'error'; message = "The status update for ticket $tid could not be posted: $m"; public_note = ''; internal_note = "Status change update failed: $m"; ticket_id = $tid; posted = $false; written_by = ''; actions = @(); warnings = @() }) }; break }
if ($null -eq $ctx -or $null -eq $ctx.PSObject.Properties['skip']) { throw 'The status change details are missing. Run the workflow from the start.' }
if ($ctx.skip) { $stopState.done = $true; Set-NodeOutput $ctx.result; return }

$id = [string]$ctx.ticket_id
$new = [string]$ctx.new_status
$actions = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.actions)) { if ($x) { $null = $actions.Add([string]$x) } }
$warnings = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.warnings)) { if ($x) { $null = $warnings.Add([string]$x) } }

# ---- the AI answer: a string, or an object holding one ----
function Get-AiText {
    param($v, [int]$Depth = 0)
    if ($null -eq $v) { return '' }
    if ($v -is [string]) { $j = $null; if ($v.Trim().StartsWith('{')) { try { $j = $v | ConvertFrom-Json } catch { } }; if ($null -ne $j -and $Depth -lt 2) { $s = Get-AiText $j ($Depth + 1); if ($s) { return $s } }; return $v }
    if ($Depth -ge 2) { return '' }
    foreach ($k in @('update', 'text', 'content', 'output', 'result', 'response', 'completion', 'message', 'answer')) { $p = Get-StepProp $v $k; if ($null -ne $p) { $s = Get-AiText $p ($Depth + 1); if ($s) { return $s } } }
    $strs = @(@($v.PSObject.Properties) | Where-Object { $_.Value -is [string] -and $_.Value.Trim() })
    if ($strs.Count -eq 1) { return [string]$strs[0].Value }
    return ''
}
$aiRaw = Get-StepProp $in 'ai'
$ai = (Get-AiText $aiRaw).Trim()
$ai = ($ai -replace '^```[a-zA-Z]*\s*', '' -replace '\s*```$', '').Trim()
if ($ai.Length -ge 2 -and (($ai.StartsWith('"') -and $ai.EndsWith('"')) -or ($ai.StartsWith("'") -and $ai.EndsWith("'")))) { $ai = $ai.Substring(1, $ai.Length - 2).Trim() }
$ai = $ai -replace "(`r?`n){3,}", "`n`n"
$why = ''
if (-not $ai) { $why = 'The AI answer was empty' }
elseif ($ai -ieq 'SKIP') { $why = 'The AI answered SKIP' }
elseif ($ai.Length -lt 20) { $why = 'The AI answer was too short' }
elseif ($ai.Length -gt 1200) { $why = 'The AI answer was too long' }
elseif ($ai -match '\{\{|\}\}' -or $ai -match '^\s*[\{\[]') { $why = 'The AI answer was not plain text' }
elseif ($ai -match '(?i)internal note') { $why = 'The AI answer mentioned internal notes' }

# ---- the template for the new status: the templates input first, then the built-in set ----
$summary = [string]$ctx.summary; if (-not $summary) { $summary = 'your request' }
$tpl = ''
if ($null -ne $ctx.templates) { foreach ($p in @($ctx.templates.PSObject.Properties)) { if ($p.Name.Trim() -ieq $new.Trim() -and [string]$p.Value) { $tpl = [string]$p.Value; break } } }
if (-not $tpl) {
    $builtIn = [ordered]@{
        '(?i)wait.*(client|customer|user|you|response|reply)|need.*info|pending.*(client|customer)' = 'We need a little more information from you to keep ticket {ticket} ({summary}) moving. Please reply to this ticket with any details you have, and we''ll pick it straight back up.'
        '(?i)resolv|complet|clos|solved|done|fixed' = 'We believe ticket {ticket} ({summary}) is now resolved. If anything still isn''t working as it should, just reply to this ticket and we''ll take another look.'
        '(?i)in ?progress|working|assigned|acknowledg' = 'A technician is now working on ticket {ticket} ({summary}). We''ll keep you posted as things move forward.'
        '(?i)schedul|appointment|booked' = 'Ticket {ticket} ({summary}) has been scheduled. We''ll be in touch if anything changes before then.'
        '(?i)hold|pending|deferred' = 'Ticket {ticket} ({summary}) is on hold for now. We haven''t forgotten it, and we''ll update you as soon as it moves again.'
        '(?i)re-?open|new|open' = 'Ticket {ticket} ({summary}) is open and in our queue. We''ll update you as soon as someone picks it up.'
    }
    foreach ($k in $builtIn.Keys) { if ($new -match $k) { $tpl = $builtIn[$k]; break } }
    if (-not $tpl) { $tpl = 'Ticket {ticket} ({summary}) is now {status}. We''ll keep you updated as it moves forward.' }
}
$template = $tpl.Replace('{ticket}', $id).Replace('{summary}', $summary).Replace('{status}', $new)
$writtenBy = 'ai'
$text = $ai
if ($why) { $writtenBy = 'template'; $text = $template; $null = $warnings.Add("$why, so the template for $new was used.") }
$note = "$text`n`n$($ctx.footer)"

if ($ctx.preview) {
    $stopState.done = $true
    Set-NodeOutput ([ordered]@{
            status = 'pending_confirmation'; message = "Preview: this update for ticket $id would be posted as a public note. Run again without preview to post it."
            public_note = $note; internal_note = "Status update preview for $new (written by $(if ($writtenBy -eq 'ai') { 'the AI' } else { 'the template' })). Nothing was posted."
            ticket_id = $id; posted = $false; written_by = $writtenBy; old_status = [string]$ctx.old_status; new_status = $new; actions = @($actions); warnings = @($warnings)
        })
    return
}

$conn = Connect-Psa $ctx.psa
Add-PsaNote -Id $id -Text $note -Title "Status update: $new" -Public
$null = $actions.Add("Posted a public status update on ticket $id.")
$stopState.done = $true
Set-NodeOutput ([ordered]@{
        status = 'success'; message = "Posted a status update for $new on ticket $id."
        public_note = $note; internal_note = "Posted a public status update for $new (written by $(if ($writtenBy -eq 'ai') { 'the AI' } else { 'the template' }))."
        ticket_id = $id; posted = $true; written_by = $writtenBy; old_status = [string]$ctx.old_status; new_status = $new; actions = @($actions); warnings = @($warnings)
    })
