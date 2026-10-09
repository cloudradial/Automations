# ---------- src/common.ps1: helpers shared by the Waiting-on-Client Nudge steps ----------
# Paste after _shared/psa.ps1 and _shared/psa-tickets.ps1. Every internal note this workflow writes ends with a marker:
#   [waiting-nudge: <tag>, waiting since <yyyy-MM-ddTHH:mmZ>]
# Tags: "day N" (reminder sent), "closing notice", "closed", "close held" (P1/P2), "failed".
# The markers are how a later run knows what was already sent and when the wait started, so a
# reminder is never sent twice for the same day. The client never sees them: the public reminder and closing
# notice pass their own marker (Get-NudgePublicMarker) to Add-PsaNote -Marker, which shows the client only an
# opaque "Ref: xxxxxxxx" line and checks the ticket again just before writing, so two runs that overlap (a
# Routine and a manual run, or an Action Runs Retry) still send the client one copy. Right after each public
# note, the step writes the companion internal note carrying the readable tag that later runs read.
# Public notes written before this change ended with the bracketed marker; those are still read.

$NudgeMarkerPattern = '\[waiting-nudge: (?<tag>[^,\]]+), waiting since (?<since>[^\]]+)\]'

function Format-NudgeStamp { param($Value) $d = ConvertTo-PsaDate $Value; if ($null -eq $d) { return '' }; return $d.ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture) }
function Format-NudgeDay { param($Value) $d = ConvertTo-PsaDate $Value; if ($null -eq $d) { return '' }; return $d.ToString('dddd, MMMM d, yyyy', [Globalization.CultureInfo]::GetCultureInfo('en-US')) }
function Get-NudgeMarker { param([string]$Tag, $Since) return "[waiting-nudge: $Tag, waiting since $(Format-NudgeStamp $Since)]" }
# The marker for a public note. Distinct from the internal one, so the companion internal note isn't mistaken for it.
function Get-NudgePublicMarker { param([string]$Tag, $Since) return "waiting-nudge public: $Tag, waiting since $(Format-NudgeStamp $Since)" }
# $true for this workflow's own public reminder or closing notice (our wording plus the opaque Ref line), so
# step 1 doesn't count it as a person's note that starts a new wait.
function Test-NudgeOwnPublic { param($n) $t = [string]$n.text; return ((-not $n.internal) -and (-not $n.fromClient) -and $t -match '(?i)(?<![0-9a-z])Ref:\s*[0-9a-f]{8}(?![0-9a-f])' -and $t -match "(?s)^\s*Hello,\s+We('re following up on| haven't heard back about) ticket #") }
function Get-NudgePlural { param([int]$n, [string]$One, [string]$Many) if ($n -eq 1) { return "1 $One" }; return "$n $Many" }

# A PSCustomObject (from the previous step's JSON) as a hashtable, one level deep.
function ConvertTo-NudgeHash {
    param($o)
    if ($null -eq $o) { return @{} }
    if ($o -is [System.Collections.IDictionary]) { $h = @{}; foreach ($k in $o.Keys) { $h[[string]$k] = $o[$k] }; return $h }
    $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; return $h
}

# Reads what the previous step handed on: @{ settings; found; truncated; plan; skipped; warnings }.
function Read-NudgeState {
    $in = Get-NodeInput
    if ($in -is [string]) { $in = $in | ConvertFrom-Json }
    $s = Get-PsaProp $in 'settings'
    if ($null -eq $s) { throw 'This step needs the output of the step before it. Run the workflow from the start.' }
    $settings = ConvertTo-NudgeHash $s
    $settings.reminderDays = @($settings.reminderDays | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
    $settings.preview = [bool]$settings.preview
    return @{
        settings  = $settings
        found     = [int](Get-PsaProp $in 'found')
        truncated = [bool](Get-PsaProp $in 'truncated')
        plan      = @(Get-PsaProp $in 'plan' | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-NudgeHash $_ })
        skipped   = @(Get-PsaProp $in 'skipped' | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-NudgeHash $_ })
        warnings  = @(Get-PsaProp $in 'warnings' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    }
}
function Write-NudgeState {
    param([hashtable]$State)
    Set-NodeOutput ([ordered]@{ settings = $State.settings; found = $State.found; truncated = $State.truncated; plan = @($State.plan); skipped = @($State.skipped); warnings = @($State.warnings) })
}

function Get-NudgeTicketLabel { param($p) $l = "#$($p.number)"; if ($p.companyName) { $l += " ($($p.companyName))" }; return $l }

# The client-facing reminder. Plain, polite, and says when the ticket will close.
function Get-NudgeReminderText {
    param($p)
    $subject = if ($p.summary) { " `"$($p.summary)`"" } else { '' }
    return @(
        'Hello,'
        ''
        "We're following up on ticket #$($p.number)$subject. We're waiting on a reply from you before we can go any further."
        ''
        "When you have a moment, please reply to this message with the details we asked for, or let us know if you no longer need help."
        ''
        "If we don't hear back, we'll close this ticket on $(Format-NudgeDay $p.closeBy). If you need help after that, just reply or contact us and we'll pick it up again."
    ) -join "`n"
}

function Get-NudgeClosingText {
    param($p)
    $subject = if ($p.summary) { " `"$($p.summary)`"" } else { '' }
    return @(
        'Hello,'
        ''
        "We haven't heard back about ticket #$($p.number)$subject for $($p.daysWaiting) days, so we're closing it for now."
        ''
        "If you still need help, just reply to this message or contact us and we'll pick it up again."
    ) -join "`n"
}

# The internal note written right after a public one, carrying the readable marker later runs read. Retry-safe.
# Returns 'written', 'already written' or 'failed' (with a warning added to the state).
function Add-NudgeCompanionNote {
    param($p, [string]$Tag, [string]$Text, $State)
    try { $r = Add-PsaNote -Id $p.ticketId -Text $Text -Title 'Waiting-on-Client Nudge' -Marker (Get-NudgeMarker $Tag $p.since); return $(if ($r -eq 'already-present') { 'already written' } else { 'written' }) }
    catch { $State.warnings += "Couldn't write the internal note on ticket $(Get-NudgeTicketLabel $p): $($_.Exception.Message)"; return 'failed' }
}
function Get-NudgeReminderNote { param($p) return "Waiting-on-Client Nudge sent reminder $($p.reminderNo) of $($p.reminderTotal) (day $($p.day)) to the client as a public note. The ticket has waited $($p.daysWaiting) days, since $(Format-NudgeDay $p.since). It will be closed on $(Format-NudgeDay $p.closeBy) if the client doesn't reply." }
function Get-NudgeNoticeNote { param($p) return "Waiting-on-Client Nudge sent the closing notice to the client as a public note after $($p.daysWaiting) days waiting, since $(Format-NudgeDay $p.since). The ticket is closed next." }
# ---------- end src/common.ps1 ----------
