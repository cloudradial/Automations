# ---------- src/common.ps1: helpers shared by the Password Expiry Reminder steps ----------
# Pasted into every step by src/build.js. Needs no other file. Every name starts with Pe so it can't clash
# with the _shared libraries. Run-wide state is one ordered hashtable that the steps change in place, because
# the runner runs each step in a child scope where $script: variables don't behave.

function Get-PeProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

# The first non-empty value among Names, as trimmed text. A list is joined with commas. A value CloudRadial
# left as a literal @token (for example "@resetUrl") counts as not given.
function Get-PeText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-PeProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join ',') }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}

# The first runner Key Vault secret among Names that has a value, or ''.
function Get-PeSecret { param([string[]]$Names) foreach ($n in $Names) { $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue } catch { }; if (-not [string]::IsNullOrWhiteSpace($v)) { return ([string]$v).Trim() } }; return '' }

# A date from Graph (a DateTime or an ISO string) as UTC, or $null.
function ConvertTo-PeDate {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { if ($v.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($v, [DateTimeKind]::Utc) }; return $v.ToUniversalTime() }
    $t = [string]$v; if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($t, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)) { return $d }
    return $null
}

# A date as yyyy-MM-ddTHH:mm:ssZ. The runner turns ISO text into a DateTime between steps, so format it again.
function Format-PeIso { param($v) $d = ConvertTo-PeDate $v; if ($null -eq $d) { return '' }; return $d.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }

function New-PeCounts {
    return [ordered]@{ checked = 0; expiringSoon = 0; due = 0; emailed = 0; alreadySentToday = 0; failed = 0; skippedSynced = 0; skippedNeverExpires = 0; skippedDisabled = 0; skippedGuests = 0; skippedNoMail = 0; skippedOther = 0; alreadyExpired = 0 }
}

# An object from the previous step's JSON as an ordered hashtable, one level deep.
function ConvertTo-PeHash {
    param($o)
    $h = [ordered]@{}
    if ($null -eq $o) { return $h }
    if ($o -is [System.Collections.IDictionary]) { foreach ($k in $o.Keys) { $h[[string]$k] = $o[$k] }; return $h }
    foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

# The run state handed on by the step before, with every key this workflow reads filled in.
function Read-PeState {
    $raw = Get-NodeInput
    if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { $raw = $null } }
    if ($null -ne $raw -and $null -eq (Get-PeProp $raw 'inputs') -and $null -ne (Get-PeProp $raw 'output')) { $raw = Get-PeProp $raw 'output' }
    $st = ConvertTo-PeHash $raw
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs']) { throw 'This step needs the output of the step before it. Run the workflow from the start.' }
    foreach ($k in @('status', 'message', 'tenant_id', 'checked_at', 'sent_via')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('due', 'emailed', 'skipped', 'actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k] | Where-Object { $null -ne $_ }) } }
    if (-not $st.Contains('done')) { $st['done'] = $false }
    $c = New-PeCounts
    if ($st.Contains('counts') -and $null -ne $st['counts']) { foreach ($k in @($c.Keys)) { $v = Get-PeProp $st['counts'] $k; if ($null -ne $v) { $c[$k] = [int]$v } } }
    $st['counts'] = $c
    return $st
}

# Ends the run: writes the state with the status and message, then throws so the run shows as failed.
function Stop-PeRun {
    param($St, [string]$Status, [string]$Msg)
    $St['status'] = $Status; $St['message'] = $Msg
    Set-NodeOutput $St
    throw $Msg
}

# "a, b, c and 4 more" for a warning or message.
function Join-PeNames { param($Names, [int]$Max = 10) $all = @($Names | Where-Object { $_ }); if ($all.Count -le $Max) { return ($all -join ', ') }; return ((@($all | Select-Object -First $Max) -join ', ') + " and $($all.Count - $Max) more") }
function Get-PePlural { param([int]$n, [string]$One, [string]$Many) if ($n -eq 1) { return "1 $One" }; return "$n $Many" }
# ---------- end src/common.ps1 ----------
