# Checks the classifier's pick against the routing table, finds every qualified engineer,
# applies the tie-break, and (only when confirm is true) assigns the ticket and adds an internal note.
function ConvertFrom-MaybeJson { param($v)
    if ($v -is [string]) { $s = $v.Trim() -replace '^```(json)?\s*', '' -replace '\s*```$', ''; if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }
    return $v
}
function Get-Param { param([string]$n)
    # Parameters may arrive as a variable, as a property of the node input, or via Get-NodeInput -Name.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-MaybeJson (Get-NodeInput) } catch { }; $v = Get-Prop $all $n }
    if ($null -eq $v) { try { $v = ConvertFrom-MaybeJson (Get-NodeInput -Name $n) } catch { }; $inner = Get-Prop $v $n; if ($null -ne $inner) { $v = $inner } }
    return (ConvertFrom-MaybeJson $v)
}
$prep = Get-Param 'prep'
$ai = Get-Param 'ai'
# The agent's answer may be wrapped (output / result / structuredOutput) or arrive as JSON text.
foreach ($k in @('output', 'result', 'structuredOutput', 'response')) { if ($null -ne $ai -and $null -eq (Get-Prop $ai 'skill') -and $null -ne (Get-Prop $ai $k)) { $ai = ConvertFrom-MaybeJson (Get-Prop $ai $k) } }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-Prop $prep 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-Prop $prep 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$ticketId = [string](Get-Prop $prep 'ticketId')
$confirm = (Get-Prop $prep 'confirm') -eq $true
$out = [ordered]@{
    status = 'error'; message = ''; public_note = ''; internal_note = ''; ticket_id = $ticketId
    actions = @(); warnings = @(); chatReply = ''
    confirm = $confirm; assignee = $null; skill = ''; role = ''; confidence = $null; reason = ''
    candidates = @(); tieBreak = ''; noMatchApplied = $false
}
function Complete { param([string]$Status, [string]$Msg, [string]$Note = '')
    $out.status = $Status; $out.message = $Msg; $out.internal_note = $(if ($Note) { $Note } else { $Msg }); $out.chatReply = $Msg
    $out.actions = @($actions); $out.warnings = @($warnings)
    Set-NodeOutput $out
}

if ($null -eq $prep) { Complete 'error' 'The Assign step got no output from the Read step.'; return }
if ((Get-Prop $prep 'status') -ne 'ok') { Complete ([string](Get-Prop $prep 'status')) ([string](Get-Prop $prep 'message')); return }

try {
    $table = Get-Prop $prep 'table'
    $s = Get-Prop $table 'settings'
    $set = { param($n, $d) $v = [string](Get-Prop $s $n); if ($v.Trim()) { $v.Trim() } else { $d } }
    $tieBreak = & $set 'tieBreak' 'least-open-tickets'
    $respectMax = (& $set 'respectMaxOpen' 'yes') -match '^(?i)yes$'
    $noMatch = & $set 'noMatch' 'leave-unassigned'
    $fallbackName = ((& $set 'fallbackEngineer' '') -replace '\s+,', ',' -replace ',(?=\S)', ', ').Trim()
    $minConf = [double]::Parse((& $set 'minConfidence' '0.7'), [System.Globalization.CultureInfo]::InvariantCulture)
    $out.tieBreak = $tieBreak
    $engineers = @(Get-Prop $table 'engineers' | Where-Object { $null -ne $_ })
    $rows = @(Get-Prop $table 'rows' | Where-Object { $null -ne $_ })
    $eng = @{}; foreach ($e in $engineers) { $eng[[string](Get-Prop $e 'Engineer')] = $e }

    # ---------- 5. check the AI's pick ----------
    $aiSkill = ([string](Get-Prop $ai 'skill')).Trim()
    $aiRole = ([string](Get-Prop $ai 'role')).Trim()
    $conf = 0.0; $c = Get-Prop $ai 'confidence'; if ($null -ne $c) { try { $conf = [double]$c } catch { $null = $warnings.Add("The classifier's confidence '$c' isn't a number, so it counted as 0.") } }
    $reason = ([string](Get-Prop $ai 'reason')).Trim()
    if ($null -eq $ai) { $null = $warnings.Add('The classifier returned nothing, so this counts as no match.') }
    $out.confidence = $conf; $out.reason = $reason
    # Only a skill that's in the table counts (case and spacing aside). The AI never invents one.
    $skill = @($rows | ForEach-Object { [string](Get-Prop $_ 's') } | Where-Object { $_.Trim() -ieq $aiSkill } | Select-Object -First 1)
    $skill = if ($skill.Count -and $aiSkill) { $skill[0] } else { '' }
    $skillRows = @($rows | Where-Object { $skill -and [string](Get-Prop $_ 's') -eq $skill })
    $role = @($skillRows | ForEach-Object { [string](Get-Prop $_ 'r') } | Where-Object { $_.Trim() -ieq $aiRole } | Select-Object -First 1)
    $role = if ($role.Count -and $aiRole) { $role[0] } else { '' }
    $out.skill = $skill; $out.role = $role
    $pickRows = if ($role) { @($skillRows | Where-Object { [string](Get-Prop $_ 'r') -eq $role }) } else { $skillRows }
    if ($skill -and -not $role) { $null = $warnings.Add("Role '$aiRole' isn't listed for $skill, so every engineer with that skill was considered.") }

    $noMatchWhy = ''
    if (-not $aiSkill) { $noMatchWhy = 'the classifier found no skill in the table that fits this ticket' }
    elseif (-not $skill) { $noMatchWhy = "the classifier picked '$aiSkill', which isn't a skill in the routing table" }
    elseif ($conf -lt $minConf) { $noMatchWhy = "the classifier's confidence ($conf) is below minConfidence ($minConf)" }

    # ---------- candidates, in listed order ----------
    $null = Connect-Psa ([string](Get-Prop $prep 'psa'))
    $cands = New-Object System.Collections.ArrayList
    foreach ($n in @($pickRows | ForEach-Object { [string](Get-Prop $_ 'e') } | Select-Object -Unique)) {
        $e = $eng[$n]
        $cand = [ordered]@{ name = $n; psaUserId = ''; psaRoleId = ''; email = ''; maxOpen = ''; openCount = $null; lastAssigned = $null; skipped = '' }
        if ($null -eq $e) { $cand.skipped = 'not in the engineers table' }
        else {
            $cand.psaUserId = [string](Get-Prop $e 'PsaUserId'); $cand.psaRoleId = [string](Get-Prop $e 'PsaRoleId'); $cand.email = [string](Get-Prop $e 'Email'); $cand.maxOpen = [string](Get-Prop $e 'MaxOpen')
            if ((Get-Prop $e 'Active') -eq $false) { $cand.skipped = 'inactive' }
        }
        $null = $cands.Add($cand)
    }
    $eligible = { @($cands | Where-Object { -not $_.skipped }) }

    # ---------- 6. tie-break ----------
    $needCounts = ($tieBreak -eq 'least-open-tickets') -or ($respectMax -and @(& $eligible | Where-Object { $_.maxOpen }).Count)
    $countsOk = $true
    if (-not $noMatchWhy -and $needCounts -and @(& $eligible).Count) {
        foreach ($cd in (& $eligible)) {
            try { $cd.openCount = Get-PsaOpenCount $cd.psaUserId } catch { $cd.openCount = $null; $null = $warnings.Add("Couldn't count open tickets for $($cd.name): $($_.Exception.Message)") }
            if ($null -eq $cd.openCount) { $countsOk = $false }
        }
        if (-not $countsOk) { $null = $warnings.Add("Open-ticket counts aren't available from $($script:Conn.Psa) for every engineer, so$(if ($tieBreak -eq 'least-open-tickets') { ' listed order was used and' }) Max Open Tickets wasn't enforced.") }
        if ($respectMax -and $countsOk) {
            foreach ($cd in (& $eligible)) { if ($cd.maxOpen -and $cd.openCount -ge [int]$cd.maxOpen) { $cd.skipped = "at the limit ($($cd.openCount) of $($cd.maxOpen) open)" } }
        }
    }
    $pool = @(& $eligible)
    if (-not $noMatchWhy -and -not $pool.Count) { $noMatchWhy = $(if ($cands.Count) { "every engineer for $skill$(if ($role) { " / $role" }) is inactive or at their limit" } else { "no engineer is listed for $skill$(if ($role) { " / $role" })" }) }

    $pick = $null; $usedTie = $tieBreak
    if (-not $noMatchWhy) {
        switch ($tieBreak) {
            'least-open-tickets' { if ($countsOk) { $pick = @($pool | Sort-Object { $_.openCount } -Stable)[0] } else { $usedTie = 'listed-order' } }
            'least-recently-assigned' {
                $ok = $true
                foreach ($cd in $pool) { try { $cd.lastAssigned = Get-PsaLastAssigned $cd.psaUserId } catch { $cd.lastAssigned = $null; $null = $warnings.Add("Couldn't read the last ticket for $($cd.name): $($_.Exception.Message)") }; if ($null -eq $cd.lastAssigned) { $ok = $false } }
                if ($ok) { $pick = @($pool | Sort-Object { $_.lastAssigned } -Stable)[0] } else { $usedTie = 'listed-order'; $null = $warnings.Add("Last-assigned times aren't available from $($script:Conn.Psa), so listed order was used.") }
            }
            'random' { $pick = $pool | Get-Random }
        }
        if ($null -eq $pick) { $pick = $pool[0] }
    }
    $out.tieBreak = $usedTie

    # ---------- no match ----------
    $recommend = @()
    if ($noMatchWhy) {
        $out.noMatchApplied = $true
        if ($noMatch -eq 'assign-fallback') {
            $fe = $eng[$fallbackName]
            if ($null -eq $fe -or (Get-Prop $fe 'Active') -eq $false) { $null = $warnings.Add("fallbackEngineer '$fallbackName' is missing or inactive, so the ticket was left unassigned.") }
            else { $pick = [ordered]@{ name = $fallbackName; psaUserId = [string](Get-Prop $fe 'PsaUserId'); psaRoleId = [string](Get-Prop $fe 'PsaRoleId'); email = [string](Get-Prop $fe 'Email'); openCount = $null; skipped = '' }; $usedTie = 'fallback'; $out.tieBreak = 'fallback' }
        }
        if ($noMatch -eq 'recommend-only') { $recommend = @($pool | Select-Object -First 3 | ForEach-Object { $_.name }) }
    }
    $out.candidates = @($cands | ForEach-Object { [ordered]@{ name = $_.name; openCount = $_.openCount; skipped = $_.skipped } })
    if ($pick) { $out.assignee = [ordered]@{ name = $pick.name; psaUserId = $pick.psaUserId; email = $pick.email } }

    # ---------- the note ----------
    $fmt = { param($cd) "$($cd.name)$(if ($null -ne $cd.openCount) { " ($($cd.openCount) open)" })$(if ($cd.skipped) { ", skipped: $($cd.skipped)" })" }
    $lines = @()
    if ($pick) { $lines += "Ticket routing: assigned to $($pick.name)$(if ($noMatchWhy) { ' (the fallback engineer)' })." }
    else { $lines += "Ticket routing: not assigned, because $noMatchWhy." }
    if ($noMatchWhy -and $pick) { $lines += "No match: $noMatchWhy." }
    if ($aiSkill) { $lines += "Skill: $(if ($skill) { $skill } else { "$aiSkill (not in the table)" })$(if ($role) { ", role: $role" } elseif ($aiRole) { ", role: $aiRole (not listed for this skill)" }). Confidence $conf." }
    if ($reason) { $lines += "Why: $reason" }
    if ($cands.Count) { $lines += "Candidates: $((@($cands | ForEach-Object { & $fmt $_ })) -join '; ')." }
    if ($recommend.Count) { $lines += "Suggested: $($recommend -join ', ')." }
    if ($pick) { $lines += "Tie-break: $usedTie." }
    $note = $lines -join "`n"

    # ---------- 7. write (only when confirm is true) ----------
    if (-not $confirm) {
        $msg = if ($pick) { "Would assign ticket $ticketId to $($pick.name)." } else { "Would leave ticket $ticketId unassigned: $noMatchWhy." }
        $null = $actions.Add('Preview only (confirm is false): nothing was assigned and no note was added.')
        Complete 'pending_confirmation' "$msg Send confirm true to apply it." "PREVIEW (confirm is false; nothing written)`n$note"
        return
    }
    if ($pick) {
        try { Set-PsaAssignee $ticketId $pick.psaUserId $pick.psaRoleId; $null = $actions.Add("Assigned ticket $ticketId to $($pick.name) (PSA user $($pick.psaUserId))") }
        catch { Complete 'error' "Couldn't assign ticket $ticketId to $($pick.name): $($_.Exception.Message)" "$note`nThe assignment failed: $($_.Exception.Message)"; return }
    }
    try { Add-PsaNote $ticketId $note -Internal; $null = $actions.Add('Added the internal routing note') }
    catch { $null = $warnings.Add("The internal note wasn't added: $($_.Exception.Message)") }
    if ($pick) { Complete 'success' "Assigned ticket $ticketId to $($pick.name)$(if ($skill) { " for $skill" })." $note }
    else { Complete 'incomplete' "Ticket $ticketId was left unassigned: $noMatchWhy." $note }
} catch {
    Complete 'error' "Routing failed: $($_.Exception.Message)"
}
