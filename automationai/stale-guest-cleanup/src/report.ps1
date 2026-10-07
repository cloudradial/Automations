# === NODE: Report and note ===
# Writes a plain-language HTML report into this company's Report Archive "Account Reviews"
# (Compliance > Reports, admins only; never the knowledge base), adds an internal note to ticket_id
# when one was given, and returns the result. A report or note that can't be written becomes a
# warning; the report then stays in the run output as report_html.
$ErrorActionPreference = 'Stop'
function Get-SgProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-SgState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-SgProp $raw 'inputs') -and $null -ne (Get-SgProp $raw 'output')) { $raw = Get-SgProp $raw 'output' }
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
$days = [int](Get-SgProp $opt 'days')
$confirm = [bool](Get-SgProp $opt 'confirm')
$includeGuests = [bool](Get-SgProp $opt 'include_guests')
$cnt = $sg['counts']
$dis = $sg['disable']
$res = Get-SgProp $dis 'result'
$candidates = @($sg['candidates'] | Where-Object { $null -ne $_ })
$members = @($candidates | Where-Object { [string](Get-SgProp $_ 'kind') -eq 'member' })
$guests = @($candidates | Where-Object { [string](Get-SgProp $_ 'kind') -eq 'guest' })
$flagged = @($candidates | Where-Object { -not [bool](Get-SgProp $_ 'can_disable') })
$canDisable = @($candidates | Where-Object { [bool](Get-SgProp $_ 'can_disable') })
$requested = @(Get-SgProp $dis 'requested')
$disabled = @(Get-SgProp $dis 'disabled' | Where-Object { $_ })
$skipped = @(Get-SgProp $dis 'skipped' | Where-Object { $null -ne $_ })
$planned = @(Get-SgProp $dis 'planned' | Where-Object { $_ })
$failed = Get-SgProp $res 'failed'
$notRun = @(Get-SgProp $res 'notRun' | Where-Object { $_ })
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
elseif ($null -ne $failed) { $status = 'error'; $message = "Disabled $(Get-SgPlural $disabled.Count 'account' 'accounts'), then stopped because '$(Get-SgProp $failed 'description')' failed: $(Get-SgProp $failed 'error'). Not run: $(if ($notRun.Count) { $notRun -join '; ' } else { 'nothing' })." }
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
        $last = if ([bool](Get-SgProp $r 'never_signed_in')) { 'Never' } else { [string](Get-SgProp $r 'last_sign_in') }
        $di = [int](Get-SgProp $r 'days_inactive'); $diText = if ($di -ge 0) { [string]$di } else { 'Unknown' }
        $note = [string](Get-SgProp $r 'note'); if (-not $note) { $note = 'Can be disabled if you confirm it.' }
        Add-SgHtml "<tr><td>$(ConvertTo-SgHtml (Get-SgProp $r 'name'))</td><td>$(ConvertTo-SgHtml (Get-SgProp $r 'upn'))</td><td>$(ConvertTo-SgHtml $last)</td><td>$diText</td><td>$(ConvertTo-SgHtml (Get-SgProp $r 'created'))</td><td>$(ConvertTo-SgHtml $note)</td></tr>"
    }
    Add-SgHtml '</table>'
}
$title = if ($confirm) { 'Inactive Microsoft 365 accounts: changes made' } else { 'Inactive Microsoft 365 accounts: review' }
Add-SgHtml "<h2>$(ConvertTo-SgHtml $title)</h2>"
Add-SgHtml "<p>Checked $(ConvertTo-SgHtml $sg['checked_at']) for accounts with no sign-in in the last $days days. Microsoft 365 tenant $(ConvertTo-SgHtml $sg['tenant_id']).</p>"
Add-SgHtml "<p><strong>$(ConvertTo-SgHtml $message)</strong></p>"
if ($confirm) {
    Add-SgHtml '<h3>What was changed</h3>'
    if ($disabled.Count) { Add-SgHtml '<ul>'; foreach ($d in $disabled) { Add-SgHtml "<li>$(ConvertTo-SgHtml $d): sign-in turned off$(if (@(@(Get-SgProp $res 'ran') | Where-Object { [string](Get-SgProp $_ 'description') -eq "Sign $d out of every session" }).Count) { ' and signed out of every session' } else { '; the sign-out did not run' }).</li>" }; Add-SgHtml '</ul>' }
    else { Add-SgHtml '<p>No accounts were changed.</p>' }
    if ($null -ne $failed) { Add-SgHtml "<p>Stopped because '$(ConvertTo-SgHtml (Get-SgProp $failed 'description'))' failed: $(ConvertTo-SgHtml (Get-SgProp $failed 'error'))</p>" }
    if ($notRun.Count) { Add-SgHtml "<p>Not run: $(ConvertTo-SgHtml ($notRun -join '; '))</p>" }
    if ($skipped.Count) {
        Add-SgHtml '<h3>Requested but not changed</h3><ul>'
        foreach ($s in $skipped) { Add-SgHtml "<li>$(ConvertTo-SgHtml (Get-SgProp $s 'requested')): $(ConvertTo-SgHtml (Get-SgProp $s 'reason'))</li>" }
        Add-SgHtml '</ul>'
    }
}
Add-SgHtml "<p>Accounts reviewed: $([int](Get-SgProp $cnt 'members_reviewed')) members and $([int](Get-SgProp $cnt 'guests_reviewed')) guests. Not counted as inactive: $([int](Get-SgProp $cnt 'skipped_disabled')) already disabled, $([int](Get-SgProp $cnt 'skipped_new')) created in the last $days days$(if (-not $includeGuests) { ", $([int](Get-SgProp $cnt 'skipped_guests')) guests (guests were not included)" }).</p>"
Add-SgTable 'Needs manual review (never disabled by this workflow)' $flagged 'No inactive account holds an admin role or is synced from on-premises.'
Add-SgTable 'Inactive member accounts' @($members | Where-Object { [bool](Get-SgProp $_ 'can_disable') }) 'None.'
if ($includeGuests) { Add-SgTable 'Inactive guest accounts' @($guests | Where-Object { [bool](Get-SgProp $_ 'can_disable') }) 'None.' }
Add-SgHtml '<p>Nothing is disabled automatically. To disable accounts from this list, run the workflow again with confirm set to true and disable_ids listing their sign-in names. Only accounts that are still inactive at that time are changed.</p>'
$html = $sgHtml.ToString()

# ---- Report Archive ----
$reportInfo = [ordered]@{ action = 'not-written'; location = '' }
$cid = [string](Get-SgProp $opt 'company_id')
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
$top = @($candidates | Select-Object -First 25 | ForEach-Object { "$(Get-SgProp $_ 'upn') ($(if ([bool](Get-SgProp $_ 'never_signed_in')) { 'never signed in' } else { "last sign-in $(Get-SgProp $_ 'last_sign_in')" })$(if ([string](Get-SgProp $_ 'flag')) { ", $(Get-SgProp $_ 'flag'), review manually" }))" })
$noteLines = @("Inactive Microsoft 365 account review ($days days).", $message)
if (-not $confirm -and $top.Count) { $noteLines += "Inactive accounts$(if ($candidates.Count -gt 25) { ' (first 25)' }): $($top -join '; ')." }
if ($confirm -and $skipped.Count) { $noteLines += "Skipped: $(@($skipped | ForEach-Object { "$(Get-SgProp $_ 'requested') ($(Get-SgProp $_ 'reason'))" }) -join '; ')" }
$noteLines += $(if ($reportOk) { "Full report: $($reportInfo.location)." } else { 'The report could not be archived; it is in the workflow run output.' })
$internal = $noteLines -join "`n"

$tid = [string]$sg['ticket_id']
if ($tid) {
    try {
        $null = Connect-Psa -Psa (Get-PsaType ([string](Get-SgProp $opt 'psa')))
        Add-PsaNote -Id $tid -Text $internal -Title 'Inactive account review'
        $actions += "Added an internal note to ticket $tid."
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
