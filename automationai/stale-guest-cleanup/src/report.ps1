# === NODE: Report and note ===
# Writes a plain-language HTML report into this company's Report Archive "Account Reviews"
# (Compliance > Reports, admins only; never the knowledge base), adds an internal note to ticket_id
# when one was given, and returns the result. A report or note that can't be written becomes a
# warning; the report then stays in the run output as report_html.
$ErrorActionPreference = 'Stop'
function Read-SgState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-PsaProp $raw 'inputs') -and $null -ne (Get-PsaProp $raw 'output')) { $raw = Get-PsaProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id', 'checked_at', 'tenant_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'candidates')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs'] -or -not $st.Contains('counts') -or -not $st.Contains('disable')) { throw 'This step expects the output of the Disable confirmed accounts step.' }
    return $st
}
function ConvertTo-SgHtml { param($v) return [System.Net.WebUtility]::HtmlEncode([string]$v) }
function Get-SgPlural { param([int]$n, [string]$one, [string]$many) if ($n -eq 1) { return "1 $one" }; return "$n $many" }

$sg = Read-SgState
$opt = $sg['inputs']
$days = [int](Get-PsaProp $opt 'days')
$confirm = [bool](Get-PsaProp $opt 'confirm')
$includeGuests = [bool](Get-PsaProp $opt 'include_guests')
$cnt = $sg['counts']
$dis = $sg['disable']
$res = Get-PsaProp $dis 'result'
$candidates = @($sg['candidates'] | Where-Object { $null -ne $_ })
$members = @($candidates | Where-Object { [string](Get-PsaProp $_ 'kind') -eq 'member' })
$guests = @($candidates | Where-Object { [string](Get-PsaProp $_ 'kind') -eq 'guest' })
$flagged = @($candidates | Where-Object { -not [bool](Get-PsaProp $_ 'can_disable') })
$canDisable = @($candidates | Where-Object { [bool](Get-PsaProp $_ 'can_disable') })
$requested = @(Get-PsaProp $dis 'requested')
$disabled = @(Get-PsaProp $dis 'disabled' | Where-Object { $_ })
$skipped = @(Get-PsaProp $dis 'skipped' | Where-Object { $null -ne $_ })
$planned = @(Get-PsaProp $dis 'planned' | Where-Object { $_ })
$failed = Get-PsaProp $res 'failed'
$notRun = @(Get-PsaProp $res 'notRun' | Where-Object { $_ })
$warnings = @($sg['warnings'])
$actions = @($sg['actions'])

# ---- Status and message ----
$scope = if ($includeGuests) { 'accounts and guests' } else { 'member accounts (guests were not included)' }
$found = "$(Get-SgPlural $candidates.Count 'account has' 'accounts have') not signed in for $days days or more ($(Get-SgPlural $members.Count 'member' 'members'), $(Get-SgPlural $guests.Count 'guest' 'guests'))"
$flagText = if ($flagged.Count) { " $(Get-SgPlural $flagged.Count 'of them is' 'of them are') flagged for manual review (admin role or synced from on-premises) and will not be disabled by this workflow." } else { '' }
$status = ''; $message = ''
if (-not $confirm) {
    if ($candidates.Count -eq 0) { $status = 'success'; $message = "No Microsoft 365 $scope have gone $days days without signing in. Nothing was changed." }
    else {
        $status = $(if ($canDisable.Count) { 'pending_confirmation' } else { 'success' })
        $message = "$found.$flagText Nothing was changed. The full list is in the Account Reviews report."
        if ($canDisable.Count) { $message += ' To disable some of them, run again with confirm set to true and disable_ids listing their sign-in names or ids.' }
        if ($planned.Count) { $message += " With confirm set to true, this run would disable: $($planned -join ', ')." }
    }
}
elseif (-not $requested.Count) { $status = 'incomplete'; $message = 'confirm was true but disable_ids was empty, so nothing was changed. List the sign-in names or ids to disable.' }
elseif (-not $planned.Count) { $status = 'rejected'; $message = "None of the accounts in disable_ids are on the current inactive list or allowed to be disabled, so nothing was changed. $(Get-SgPlural $skipped.Count 'account was' 'accounts were') skipped; see the report for why." }
elseif ($null -ne $failed) { $status = 'error'; $message = "Disabled $(Get-SgPlural $disabled.Count 'account' 'accounts'), then stopped because '$(Get-PsaProp $failed 'description')' failed: $(Get-PsaProp $failed 'error'). Not run: $(if ($notRun.Count) { $notRun -join '; ' } else { 'nothing' })." }
else {
    $status = 'success'
    $message = "Disabled $(Get-SgPlural $disabled.Count 'account' 'accounts') and signed $(if ($disabled.Count -eq 1) { 'it' } else { 'them' }) out of every session: $($disabled -join ', ')."
    if ($skipped.Count) { $message += " $(Get-SgPlural $skipped.Count 'requested account was' 'requested accounts were') skipped; see the report for why." }
}

# ---- HTML report ----
$sgHtml = New-Object System.Text.StringBuilder
function Add-SgHtml { param([string]$s) $null = $sgHtml.Append($s) }
function Add-SgTable {
    param([string]$Title, $Rows, [string]$Empty)
    Add-SgHtml "<h3>$(ConvertTo-SgHtml $Title)</h3>"
    if (-not @($Rows).Count) { Add-SgHtml "<p>$(ConvertTo-SgHtml $Empty)</p>"; return }
    Add-SgHtml '<table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse"><tr><th>Name</th><th>Sign-in name</th><th>Last sign-in</th><th>Days inactive</th><th>Created</th><th>Review note</th></tr>'
    foreach ($r in @($Rows)) {
        $last = if ([bool](Get-PsaProp $r 'never_signed_in')) { 'Never' } else { [string](Get-PsaProp $r 'last_sign_in') }
        $di = [int](Get-PsaProp $r 'days_inactive'); $diText = if ($di -ge 0) { [string]$di } else { 'Unknown' }
        $note = [string](Get-PsaProp $r 'note'); if (-not $note) { $note = 'Can be disabled if you confirm it.' }
        Add-SgHtml "<tr><td>$(ConvertTo-SgHtml (Get-PsaProp $r 'name'))</td><td>$(ConvertTo-SgHtml (Get-PsaProp $r 'upn'))</td><td>$(ConvertTo-SgHtml $last)</td><td>$diText</td><td>$(ConvertTo-SgHtml (Get-PsaProp $r 'created'))</td><td>$(ConvertTo-SgHtml $note)</td></tr>"
    }
    Add-SgHtml '</table>'
}
$title = if ($confirm) { 'Inactive Microsoft 365 accounts: changes made' } else { 'Inactive Microsoft 365 accounts: review' }
Add-SgHtml "<h2>$(ConvertTo-SgHtml $title)</h2>"
Add-SgHtml "<p>Checked $(ConvertTo-SgHtml $sg['checked_at']) for accounts with no sign-in in the last $days days. Microsoft 365 tenant $(ConvertTo-SgHtml $sg['tenant_id']).</p>"
Add-SgHtml "<p><strong>$(ConvertTo-SgHtml $message)</strong></p>"
if ($confirm) {
    Add-SgHtml '<h3>What was changed</h3>'
    if ($disabled.Count) { Add-SgHtml '<ul>'; foreach ($d in $disabled) { Add-SgHtml "<li>$(ConvertTo-SgHtml $d): sign-in turned off$(if (@(@(Get-PsaProp $res 'ran') | Where-Object { [string](Get-PsaProp $_ 'description') -eq "Sign $d out of every session" }).Count) { ' and signed out of every session' } else { '; the sign-out did not run' }).</li>" }; Add-SgHtml '</ul>' }
    else { Add-SgHtml '<p>No accounts were changed.</p>' }
    if ($null -ne $failed) { Add-SgHtml "<p>Stopped because '$(ConvertTo-SgHtml (Get-PsaProp $failed 'description'))' failed: $(ConvertTo-SgHtml (Get-PsaProp $failed 'error'))</p>" }
    if ($notRun.Count) { Add-SgHtml "<p>Not run: $(ConvertTo-SgHtml ($notRun -join '; '))</p>" }
    if ($skipped.Count) {
        Add-SgHtml '<h3>Requested but not changed</h3><ul>'
        foreach ($s in $skipped) { Add-SgHtml "<li>$(ConvertTo-SgHtml (Get-PsaProp $s 'requested')): $(ConvertTo-SgHtml (Get-PsaProp $s 'reason'))</li>" }
        Add-SgHtml '</ul>'
    }
}
Add-SgHtml "<p>Accounts reviewed: $([int](Get-PsaProp $cnt 'members_reviewed')) members and $([int](Get-PsaProp $cnt 'guests_reviewed')) guests. Not counted as inactive: $([int](Get-PsaProp $cnt 'skipped_disabled')) already disabled, $([int](Get-PsaProp $cnt 'skipped_new')) created in the last $days days$(if (-not $includeGuests) { ", $([int](Get-PsaProp $cnt 'skipped_guests')) guests (guests were not included)" }).</p>"
Add-SgTable 'Needs manual review (never disabled by this workflow)' $flagged 'No inactive account holds an admin role or is synced from on-premises.'
Add-SgTable 'Inactive member accounts' @($members | Where-Object { [bool](Get-PsaProp $_ 'can_disable') }) 'None.'
if ($includeGuests) { Add-SgTable 'Inactive guest accounts' @($guests | Where-Object { [bool](Get-PsaProp $_ 'can_disable') }) 'None.' }
Add-SgHtml '<p>Nothing is disabled automatically. To disable accounts from this list, run the workflow again with confirm set to true and disable_ids listing their sign-in names. Only accounts that are still inactive at that time are changed.</p>'
$html = $sgHtml.ToString()

# ---- Report Archive ----
$reportInfo = [ordered]@{ action = 'not-written'; location = '' }
$cid = [string](Get-PsaProp $opt 'company_id')
$subject = if ($confirm) { "Inactive accounts changes $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC" } else { "Inactive accounts review $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))" }
$reportOk = $false
if ($cid -match '^\d+$') {
    try {
        $null = Connect-Cr
        $w = Add-CrArchiveReport -CompanyId ([int]$cid) -ArchiveName 'Account Reviews' -Subject $subject -Html $html -Category 'Security' -IsError:($status -eq 'error')
        $reportInfo = [ordered]@{ action = [string]$w.action; location = [string]$w.location }
        $reportOk = $true
        $actions += "Wrote the report to the Account Reviews archive (item '$subject')."
    }
    catch { $warnings += "Couldn't write the report to Report Archives: $($_.Exception.Message) The report is in report_html." }
}
else { $warnings += 'No CloudRadial company id (company_id input or CloudRadial-CompanyId secret), so the report was not archived. It is in report_html.' }

# ---- Internal note ----
$top = @($candidates | Select-Object -First 25 | ForEach-Object { "$(Get-PsaProp $_ 'upn') ($(if ([bool](Get-PsaProp $_ 'never_signed_in')) { 'never signed in' } else { "last sign-in $(Get-PsaProp $_ 'last_sign_in')" })$(if ([string](Get-PsaProp $_ 'flag')) { ", $(Get-PsaProp $_ 'flag'), review manually" }))" })
$noteLines = @("Inactive Microsoft 365 account review ($days days).", $message)
if (-not $confirm -and $top.Count) { $noteLines += "Inactive accounts$(if ($candidates.Count -gt 25) { ' (first 25)' }): $($top -join '; ')." }
if ($confirm -and $skipped.Count) { $noteLines += "Skipped: $(@($skipped | ForEach-Object { "$(Get-PsaProp $_ 'requested') ($(Get-PsaProp $_ 'reason'))" }) -join '; ')" }
$noteLines += $(if ($reportOk) { "Full report: $($reportInfo.location)." } else { 'The report could not be archived; it is in the workflow run output.' })
$internal = $noteLines -join "`n"

$tid = [string]$sg['ticket_id']
# Retry guard: the note carries a marker, so a ServiceAI Retry or a re-run Routine doesn't add it twice.
# A review is keyed by the UTC day and settings; a confirm run by a short hash of the accounts it was asked
# to disable (never the sign-in names themselves).
if ($confirm) {
    $sgReq = @(@(Get-PsaProp $dis 'requested') | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique) -join ','
    $sgSha = [System.Security.Cryptography.SHA256]::Create()
    try { $sgHash = (-join ($sgSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sgReq)) | ForEach-Object { $_.ToString('x2') })).Substring(0, 8) } finally { $sgSha.Dispose() }
    $noteMarker = "stale-guest-cleanup: disable $sgHash"
}
else { $noteMarker = "stale-guest-cleanup: review $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')) $($days)d$(if ($includeGuests) { ' with guests' })" }
if ($tid) {
    try {
        $null = Connect-Psa -Psa (Get-PsaType ([string](Get-PsaProp $opt 'psa')))
        $noteWrite = Add-PsaNote -Id $tid -Text $internal -Title 'Inactive account review' -Marker $noteMarker
        if ($noteWrite -eq 'already-present') { $actions += "The internal note was already on ticket $tid, so it was not added again." }
        else { $actions += "Added an internal note to ticket $tid." }
    }
    catch { $warnings += "Couldn't add the internal note to ticket $($tid): $($_.Exception.Message)" }
}

$public = if ($confirm -and $disabled.Count) { "We turned off $(Get-SgPlural $disabled.Count 'unused Microsoft 365 account' 'unused Microsoft 365 accounts') that you approved." } elseif ($confirm) { 'No Microsoft 365 accounts were changed.' } else { 'We reviewed Microsoft 365 accounts that have not been used recently. No changes were made.' }

$out = [ordered]@{
    status        = $status
    message       = $message
    public_note   = $public
    internal_note = $internal
    ticket_id     = $tid
    actions       = @($actions)
    warnings      = @($warnings)
    company_id    = $cid
    tenant_id     = [string]$sg['tenant_id']
    days          = $days
    confirm       = $confirm
    counts        = $cnt
    candidates    = @($candidates)
    disabled      = @($disabled)
    skipped       = @($skipped)
    report        = $reportInfo
}
if (-not $reportOk) { $out['report_html'] = $html }
Set-NodeOutput $out
