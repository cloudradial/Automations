# Strict-mode harness for Thank-You Close. Runs the step exactly as shipped in ../thank-you-close.yml (via
# build.js --dump), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, against the mock
# PSAs in mock-psa.ps1. Placeholder data only.
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install in _shared, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'one PowerShell step' (($MockSteps.Keys -join ',') -eq 'node-close') ($MockSteps.Keys -join ', ')

$Waiting = @{ connectwise = 'Waiting Customer'; autotask = 'Waiting Customer'; halopsa = 'Waiting on User'; syncro = 'Waiting on Customer'; zendesk = 'pending' }
$Resolved = @{ connectwise = 'Resolved'; autotask = 'Resolved'; halopsa = 'Resolved'; syncro = 'Resolved'; zendesk = 'Resolved' }
# 301 Resolved, short thanks: close         302 Waiting, thanks but still broken: leave
# 303 Resolved, thanks plus a new request: leave   304 Resolved, technician wrote after the thanks: leave
# 305 In Progress, thanks: not watched       306 Waiting, thanks above quoted email history: close
function New-TycWorld {
    param([string]$Psa)
    Reset-World $Psa
    $w = $Waiting[$Psa]; $r = $Resolved[$Psa]
    $null = Add-WorldTicket 301 $r -Created 4 -Notes @(@{ d = 1; who = 'tech'; text = 'We replaced the toner. Let us know if it prints now.' }, @{ d = 0.1; who = 'client'; text = 'Thanks, that worked perfectly!' })
    $null = Add-WorldTicket 302 $w -Created 4 -Notes @(@{ d = 1; who = 'tech'; text = 'Please try printing again.' }, @{ d = 0.1; who = 'client'; text = 'Thanks! But the printer still jams on page 2.' })
    $null = Add-WorldTicket 303 $r -Created 4 -Notes @(@{ d = 0.1; who = 'client'; text = 'Thank you. Can you also reset the password for the front desk?' })
    $null = Add-WorldTicket 304 $r -Created 4 -Notes @(@{ d = 0.2; who = 'client'; text = 'Cheers, all good.' }, @{ d = 0.1; who = 'tech'; text = 'Glad to hear it, one last check tomorrow.' })
    $null = Add-WorldTicket 305 'In Progress' -Created 4 -Notes @(@{ d = 0.1; who = 'client'; text = 'Thanks!' })
    $null = Add-WorldTicket 306 $w -Created 4 -Notes @(@{ d = 1; who = 'tech'; text = 'The VPN profile was reset.' }, @{ d = 0.1; who = 'client'; text = "All sorted now, cheers.`n`nOn Tue, Example MSP Support wrote:`n> Is the VPN still down? Please let us know." })
}
function Get-Ids { param($List) return (@($List | ForEach-Object { [string]$_.ticketId } | Sort-Object) -join ',') }

# ---- 1. Preview on every PSA that marks client notes: the right tickets, nothing written ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'syncro', 'zendesk')) {
    New-TycWorld $psa
    $out = ConvertTo-RoundTrip (Invoke-Step 'node-close' ([pscustomobject]@{ preview = $true; statuses = "$($Waiting[$psa]),$($Resolved[$psa])" }))
    Check "$psa preview: would close 301 and 306 only" ((Get-Ids $out.closed) -eq '301,306') "$(Get-Ids $out.closed) :: $($out.message) $(@($out.warnings) -join ' | ')"
    Check "$psa preview: nothing written" (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
    $why = @{}; foreach ($s in @($out.skipped)) { $why[[string]$s.ticketId] = [string]$s.reason }
    Check "$psa preview: 302 left because of 'but'/'still'" ($why.Contains('302') -and $why['302'] -match "also says '(but|still)'") ($why | ConvertTo-Json -Compress)
    Check "$psa preview: 303 left because it asks for more" ($why.Contains('303') -and $why['303'] -match 'also says') ($why | ConvertTo-Json -Compress)
    Check "$psa preview: 304 and 305 untouched" (-not (@($out.closed | Where-Object { [string]$_.ticketId -in @('304', '305') }).Count)) ''
    Check "$psa preview: status pending_confirmation" ($out.status -eq 'pending_confirmation' -and $out.message -like 'Preview only*would close 2 ticket(s)*') $out.message
}

# ---- 2. Live on ConnectWise: closes and notes 301 and 306, then a rerun does nothing ----
New-TycWorld 'connectwise'
$out = ConvertTo-RoundTrip (Invoke-Step 'node-close' $null)
Check 'cw live: closed 301 and 306' ((Get-Ids $out.closed) -eq '301,306' -and @($out.closed | Where-Object { $_.result -eq 'closed' }).Count -eq 2) "$($out.message) $(@($out.warnings) -join ' | ')"
Check 'cw live: both tickets are now closed in the PSA' ((Get-WorldTicket 301).status -eq 'Closed' -and (Get-WorldTicket 306).status -eq 'Closed') "$((Get-WorldTicket 301).status) / $((Get-WorldTicket 306).status)"
$notes = @(Get-Writes 'POST */service/tickets/*/notes')
Check 'cw live: one internal, marked note per closed ticket, quoting the reply' ($notes.Count -eq 2 -and @($notes | Where-Object { $_.Body.internalAnalysisFlag -eq $true -and [string]$_.Body.text -match '\[thank-you-close \d+-\d+\]' -and [string]$_.Body.text -match 'They wrote: "' }).Count -eq 2) ($notes | ConvertTo-Json -Depth 4 -Compress)
Check 'cw live: quoted email history is not in the quote' (@($notes | Where-Object { [string]$_.Body.text -match 'All sorted now, cheers\.' -and [string]$_.Body.text -notmatch 'VPN still down' }).Count -eq 1) ''
Check 'cw live: nothing else touched' ((Get-WorldTicket 302).status -eq 'Waiting Customer' -and (Get-WorldTicket 303).status -eq 'Resolved' -and (Get-WorldTicket 305).status -eq 'In Progress') ''
Check 'cw live: status success' ($out.status -eq 'success' -and $out.message -like 'Closed 2 ticket(s) after a client thank-you.*') $out.message
$before = @(Get-Writes).Count
$out2 = ConvertTo-RoundTrip (Invoke-Step 'node-close' $null)
Check 'cw rerun: nothing more to close or write' (@($out2.closed).Count -eq 0 -and @(Get-Writes).Count -eq $before) $out2.message

# ---- 3. Settings and guards ----
New-TycWorld 'halopsa'
$out = ConvertTo-RoundTrip (Invoke-Step 'node-close' ([pscustomobject]@{ preview = $true; min_age_minutes = 600 }))
Check 'a reply younger than min_age_minutes waits' (@($out.closed).Count -eq 0 -and @($out.skipped | Where-Object { $_.reason -like 'the reply is under 600 minutes old' }).Count -ge 2) (@($out.skipped | ForEach-Object { $_.reason }) -join ' | ')
$out = ConvertTo-RoundTrip (Invoke-Step 'node-close' ([pscustomobject]@{ preview = $true; statuses = 'Resolved' }))
Check 'statuses narrows what is watched' ((Get-Ids $out.closed) -eq '301') (Get-Ids $out.closed)

New-TycWorld 'autotask'
$MockWorld.psa = 'kaseyabms'
Check 'kaseya: refused with a plain reason' ((Get-ThrowMessage { Invoke-Step 'node-close' $null }) -like 'Kaseya BMS notes don*') ''
New-TycWorld 'syncro'
Check 'bad setting fails early' ((Get-ThrowMessage { Invoke-Step 'node-close' ([pscustomobject]@{ max_age_days = 0 }) }) -like 'max_age_days must be a whole number from 1 to 90*')

Complete-Test
