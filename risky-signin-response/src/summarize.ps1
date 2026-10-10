# === NODE: Summarize ===
# Turns the run into the standard output: status, a plain-sentence message, a client-safe public_note,
# a technician internal_note (with the risk detail, which is never put in public_note), ticket_id and lists.
$ErrorActionPreference = 'Stop'
function Get-RsProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-RsState {
    param([string]$Needs, [string]$From)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-RsProp $raw 'inputs') -and $null -ne (Get-RsProp $raw 'output')) { $raw = Get-RsProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id', 'tenant_id', 'checked_at')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'risky', 'responses')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs'] -or ($Needs -and -not $st.Contains($Needs))) { throw "This step expects the output of the $From step." }
    return $st
}
function Get-RsPlural { param([int]$n, [string]$one, [string]$many) if ($n -eq 1) { return "1 $one" }; return "$n $many" }
function Get-RsUpns { param($Rows) return (@($Rows | ForEach-Object { [string](Get-RsProp $_ 'upn') }) -join ', ') }

$rs = Read-RsState 'block' 'Block confirmed accounts'
$opt = $rs['inputs']
$preview = [bool](Get-RsProp $opt 'preview')
$confirm = [bool](Get-RsProp $opt 'confirm')
$levelText = if ([string](Get-RsProp $opt 'min_risk') -eq 'medium') { 'medium or high' } else { 'high' }
$resp = @($rs['responses'] | Where-Object { $null -ne $_ })
$handled = @($resp | Where-Object { [string](Get-RsProp $_ 'outcome') -eq 'handled' })
$open = @($resp | Where-Object { [string](Get-RsProp $_ 'outcome') -eq 'already-open' })
$would = @($resp | Where-Object { [string](Get-RsProp $_ 'outcome') -eq 'would-handle' })
$failed = @($resp | Where-Object { [string](Get-RsProp $_ 'outcome') -eq 'error' })
$blk = $rs['block']
$requested = @(Get-RsProp $blk 'requested' | Where-Object { $_ })
$planned = @(Get-RsProp $blk 'planned' | Where-Object { $_ })
$blocked = @(Get-RsProp $blk 'blocked' | Where-Object { $_ })
$skipped = @(Get-RsProp $blk 'skipped' | Where-Object { $null -ne $_ })
$bres = Get-RsProp $blk 'result'
$bfail = Get-RsProp $bres 'failed'

# ---- Message ----
$parts = @()
if (-not $resp.Count) { $parts += "No users are at $levelText risk in Microsoft Entra ID Protection right now." }
else {
    $parts += "$(Get-RsPlural $resp.Count 'user is' 'users are') at $levelText risk."
    if ($handled.Count) {
        $parts += "Opened a ticket and signed the user out of every session for: $(Get-RsUpns $handled)."
        $pwOk = @($handled | Where-Object { [string](Get-RsProp $_ 'password') -eq 'required' })
        $pwHand = @($handled | Where-Object { [string](Get-RsProp $_ 'password') -in @('skipped-synced', 'manual-admin') })
        if ($pwOk.Count) { $parts += "Required a password change at next sign-in for: $(Get-RsUpns $pwOk)." }
        if ($pwHand.Count) { $parts += "Reset the password by hand for: $(Get-RsUpns $pwHand) (synced from on-premises or an admin, so the automation couldn't require it)." }
    }
    if ($would.Count) { $parts += "Preview only, nothing was changed. A real run would open a ticket, sign the user out and require a password change where Microsoft 365 allows it, for: $(Get-RsUpns $would)." }
    if ($open.Count) { $parts += "Already handled, so nothing was repeated: $(@($open | ForEach-Object { if (Get-RsProp $_ 'ticket_id') { "$(Get-RsProp $_ 'upn') (ticket $(Get-RsProp $_ 'ticket_id'))" } else { "$(Get-RsProp $_ 'upn') (logged as handled)" } }) -join ', ')." }
    if ($failed.Count) { $parts += "Problems with: $(@($failed | ForEach-Object { "$(Get-RsProp $_ 'upn') ($(@(Get-RsProp $_ 'errors') -join ' '))" }) -join '; ')" }
    # A ticket whose priority the PSA couldn't set directly (ConnectWise wouldn't list its priorities) is only "requested" critical or high.
    $crit = @($resp | Where-Object { [bool](Get-RsProp $_ 'is_admin') -and [string](Get-RsProp $_ 'outcome') -in @('handled', 'would-handle') -and -not [bool](Get-RsProp $_ 'priority_fallback') })
    if ($crit.Count) { $parts += "$(Get-RsUpns $crit) $(if ($crit.Count -eq 1) { 'holds' } else { 'hold' }) an admin role, so $(if ($crit.Count -eq 1) { 'its ticket is' } else { 'their tickets are' }) critical." }
    $fb = @($resp | Where-Object { [bool](Get-RsProp $_ 'priority_fallback') -and [string](Get-RsProp $_ 'ticket_id') })
    if ($fb.Count) { $parts += "The ticket$(if ($fb.Count -ne 1) { 's' }) for $(@($fb | ForEach-Object { "$(Get-RsProp $_ 'upn') (requested $(Get-RsProp $_ 'priority') priority)" }) -join ', ') couldn't be given $(if ($fb.Count -eq 1) { 'its' } else { 'their' }) priority directly, because the PSA wouldn't list its ticket priorities. Check the priority on $(if ($fb.Count -eq 1) { 'the ticket' } else { 'each ticket' })." }
}
if ($requested.Count) {
    if (-not $confirm) {
        if ($planned.Count) { $parts += "No account was blocked. Run again with confirm set to true to block: $($planned -join ', ')." }
        else { $parts += 'None of the accounts in block_upns can be blocked now.' }
    }
    elseif ($blocked.Count) { $parts += "Blocked sign-in and signed out: $($blocked -join ', ')." }
    elseif (-not $planned.Count) { $parts += 'None of the accounts in block_upns can be blocked now, so nothing was blocked.' }
    if ($null -ne $bfail) { $parts += "Blocking stopped because '$(Get-RsProp $bfail 'description')' failed: $(Get-RsProp $bfail 'error')" }
    if ($skipped.Count) { $parts += "Not blocked: $(@($skipped | ForEach-Object { "$(Get-RsProp $_ 'requested') ($(Get-RsProp $_ 'reason'))" }) -join '; ')" }
}
else { $parts += 'No account was blocked; blocking needs a run with confirm set to true and block_upns.' }
$message = $parts -join ' '

# ---- Status ----
$status = 'success'
if ($failed.Count -or ($confirm -and $null -ne $bfail)) { $status = 'error' }
elseif ($confirm -and $requested.Count -and -not $planned.Count -and -not $handled.Count) { $status = 'rejected' }
elseif (($preview -and $would.Count) -or (-not $confirm -and $planned.Count)) { $status = 'pending_confirmation' }

# ---- Notes ----
$public = ''
if ($handled.Count) { $public = "We noticed unusual sign-in activity on $(Get-RsPlural $handled.Count 'account' 'accounts') and secured $(if ($handled.Count -eq 1) { 'it' } else { 'them' }) as a precaution. Our team is reviewing it." }
if ($blocked.Count) { $public = (("$public We have also temporarily turned off sign-in for $(Get-RsPlural $blocked.Count 'account' 'accounts') while we investigate.").Trim()) }
$lines = @("Risky sign-in response, checked $($rs['checked_at']), Microsoft 365 tenant $($rs['tenant_id']).", $message)
foreach ($r in @($resp | Where-Object { [string](Get-RsProp $_ 'note') })) { $lines += ''; $lines += "== $(Get-RsProp $r 'upn') (ticket $(if (Get-RsProp $r 'ticket_id') { Get-RsProp $r 'ticket_id' } else { 'not opened' })) =="; $lines += [string](Get-RsProp $r 'note') }
$tickets = @($resp | Where-Object { [string](Get-RsProp $_ 'outcome') -in @('handled', 'error') -and [string](Get-RsProp $_ 'ticket_id') } | ForEach-Object { [string](Get-RsProp $_ 'ticket_id') })

$out = [ordered]@{
    status        = $status
    message       = $message
    public_note   = $public
    internal_note = ($lines -join "`n")
    ticket_id     = $(if ($tickets.Count) { $tickets[0] } else { '' })
    tickets       = @($tickets)
    actions       = @(@($rs['actions']) + @($handled | ForEach-Object { "Handled $(Get-RsProp $_ 'upn'): ticket $(Get-RsProp $_ 'ticket_id') ($(if ([bool](Get-RsProp $_ 'priority_fallback')) { "requested $(Get-RsProp $_ 'priority') priority" } else { Get-RsProp $_ 'priority' })), sessions revoked, password change $(Get-RsProp $_ 'password'), manager email $(Get-RsProp $_ 'manager_mail')." }))
    warnings      = @($rs['warnings'])
    tenant_id     = [string]$rs['tenant_id']
    company_id    = [string](Get-RsProp $opt 'company_id')
    preview       = $preview
    confirm       = $confirm
    counts        = [ordered]@{ at_risk = $resp.Count; handled = $handled.Count; already_open = $open.Count; would_handle = $would.Count; errors = $failed.Count; blocked = $blocked.Count }
    responses     = @($resp | ForEach-Object { $src = $_; $x = [ordered]@{}; $names = if ($src -is [System.Collections.IDictionary]) { @($src.Keys) } else { @($src.PSObject.Properties.Name) }; foreach ($k in $names) { if ($k -ne 'note') { $x[[string]$k] = Get-RsProp $src ([string]$k) } }; $x })
    block         = $blk
}
Set-NodeOutput $out
