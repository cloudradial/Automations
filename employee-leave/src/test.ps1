# Local test harness for leave.ps1: mocks AutomationAI, the Key Vault, Microsoft Graph, CloudRadial and ConnectWise.
# Run: pwsh -NoProfile -File employee-leave/src/test.ps1
$ErrorActionPreference = 'Stop'
$script:Script = Get-Content -Raw (Join-Path $PSScriptRoot 'leave.ps1')
$script:fail = 0
function Check { param([string]$Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "  ok   $Name" } else { $script:fail++; Write-Host "  FAIL $Name :: $(ConvertTo-Json $Detail -Depth 6 -Compress)" } }

function Invoke-Leave { param($Trigger, [hashtable]$Users, $Tokens)
    $state = @{ users = $Users; tokens = $Tokens; calls = New-Object System.Collections.Generic.List[string]; out = $null; input = $Trigger }
    $sb = [scriptblock]::Create(@'
param($state)
function Get-NodeInput { return @{ trigger = ($state.input | ConvertTo-Json -Depth 10) } }
function Set-NodeOutput { param($o) $state.out = $o }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) if ($Name -match '^(M365-ClientId|M365-ClientSecret|CloudRadial-BaseUrl|CloudRadial-PublicKey|CloudRadial-PrivateKey|CW-ApiUrl|CW-CompanyID|CW-PublicKey|CW-PrivateKey|CW-ClientId)$') { if ($Name -eq 'CloudRadial-BaseUrl') { return 'https://cr.test' }; return 'x' }; return $null }
function Invoke-WebRequest { param($Method, $Uri, $Headers, $ContentType, $Body, $MaximumRedirection, [switch]$SkipHttpErrorCheck) $state.calls.Add("CW $Method $Uri"); return [pscustomobject]@{ Content = '' } }
function Invoke-RestMethod { param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $ErrorAction)
    $state.calls.Add("$Method $Uri")
    if ($Uri -match 'login\.microsoftonline') { return [pscustomobject]@{ access_token = 't' } }
    if ($Uri -match 'graph\.microsoft\.com/v1\.0/users/([^?/]+)\?') { $k = [uri]::UnescapeDataString($Matches[1]).ToLower(); if (-not $state.users.ContainsKey($k)) { throw 'not found' }; return $state.users[$k] }
    if ($Uri -match 'graph\.microsoft\.com/v1\.0/users/([^/]+)$' -and $Method -eq 'PATCH') { $id = $Matches[1]; $b = $Body | ConvertFrom-Json; foreach ($u in $state.users.Values) { if ($u.id -eq $id) { $u.accountEnabled = $b.accountEnabled } }; return $null }
    if ($Uri -match 'revokeSignInSessions') { return $null }
    if ($Uri -match '/v2/odata/token') { $f = [uri]::UnescapeDataString(($Uri -split 'filter=')[1]); $vals = @(); foreach ($k in $state.tokens.Keys) { $cid = [int]$k; if ($f -match 'companyId eq (\d+)' -and [int]$Matches[1] -ne $cid) { continue }; $vals += [pscustomobject]@{ companyId = $cid; name = 'EmployeeLeaveSchedule'; value = $state.tokens[$k] } }; return [pscustomobject]@{ value = $vals } }
    if ($Uri -match '/v2/token$') { $b = $Body | ConvertFrom-Json; $state.tokens["$($b.companyId)"] = $b.value; return $null }
    if ($Uri -match '/v2/signalmessage') { return $null }
    throw "unmocked $Method $Uri"
}
'@ + "`n" + $script:Script)
    & $sb $state
    return $state
}
function NewUsers { @{ 'adele@contoso.com' = [pscustomobject]@{ id = 'u1'; displayName = 'Adele Vance'; userPrincipalName = 'adele@contoso.com'; accountEnabled = $true }; 'megan@contoso.com' = [pscustomobject]@{ id = 'u2'; displayName = 'Megan Bowen'; userPrincipalName = 'megan@contoso.com'; accountEnabled = $true } } }
$co = @{ id = 1; name = 'Contoso Ltd'; tenantId = 'tid-1' }
$tz = [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York'); $today = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
$d = { param($n) $today.AddDays($n).ToString('yyyy-MM-dd') }

Write-Host 'Self, future start, with return: schedules both, changes nothing now'
$u = NewUsers; $tok = @{}
$s = Invoke-Leave @{ leaveUser = 'adele@contoso.com'; leaveType = 'Parental leave'; leaveStart = (& $d 3); returnDate = (& $d 10); ticket = @{ id = 500 }; company = $co; user = @{ id = 'req1'; name = 'Adele Vance'; email = 'adele@contoso.com' } } $u $tok
Check 'status success' ($s.out.status -eq 'success') $s.out
Check 'for themselves' ($s.out.forThemselves -eq $true) $s.out
Check 'still enabled' ($u['adele@contoso.com'].accountEnabled -eq $true) $null
$e = @($tok['1'] | ConvertFrom-Json)
Check 'two entries saved' ($e.Count -eq 2 -and $e[0].a -eq 'start' -and $e[1].a -eq 'return' -and $e[0].t -eq '500') $e
Check 'no PATCH' (-not ($s.calls | Where-Object { $_ -match '^PATCH' })) $s.calls
Check 'note + signal' ($s.out.ticketNoted -and $s.out.signalSent) $s.out

Write-Host 'Scheduled run before start: nothing due'
$s2 = Invoke-Leave @{ mode = 'scheduled' } $u $tok
Check 'nothing applied' ($s2.out.applied.Count -eq 0 -and $s2.out.stillScheduled -eq 2) $s2.out

Write-Host 'Scheduled run on start day: pauses, keeps return'
$e = @($tok['1'] | ConvertFrom-Json); $e[0].d = (& $d 0); $tok['1'] = ($e | ConvertTo-Json -Compress -AsArray)
$s3 = Invoke-Leave @{ mode = 'scheduled' } $u $tok
Check 'one applied' ($s3.out.applied.Count -eq 1 -and $s3.out.applied[0].action -eq 'start') $s3.out
Check 'disabled' ($u['adele@contoso.com'].accountEnabled -eq $false) $null
$e = @($tok['1'] | ConvertFrom-Json); Check 'return kept' ($e.Count -eq 1 -and $e[0].a -eq 'return') $e
Check 'note on original ticket' ([bool]($s3.calls | Where-Object { $_ -match 'tickets/500/notes' })) $s3.calls

Write-Host 'Scheduled preview on return day: no change'
$e[0].d = (& $d 0); $tok['1'] = (@($e) | ConvertTo-Json -Compress -AsArray)
$s4 = Invoke-Leave @{ mode = 'scheduled'; confirm = $false } $u $tok
Check 'preview, still disabled' ($s4.out.applied.Count -eq 1 -and $u['adele@contoso.com'].accountEnabled -eq $false) $s4.out
$s5 = Invoke-Leave @{ mode = 'scheduled' } $u $tok
Check 'turned back on' ($u['adele@contoso.com'].accountEnabled -eq $true -and $s5.out.status -eq 'success') $s5.out
Check 'schedule empty' (@($tok['1'] | ConvertFrom-Json).Count -eq 0) $tok

Write-Host 'Manager, no start date, with return: pauses now, schedules return'
$s6 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Leave of absence'; returnDate = (& $d 5); ticket = @{ id = 501 }; company = $co; user = @{ id = 'req2'; name = 'Pat Manager'; email = 'pat@contoso.com' } } $u $tok
Check 'disabled now' ($u['megan@contoso.com'].accountEnabled -eq $false -and $s6.out.status -eq 'success') $s6.out
$e = @($tok['1'] | ConvertFrom-Json); Check 'return scheduled' ($e.Count -eq 1 -and $e[0].a -eq 'return' -and $e[0].u -eq 'megan@contoso.com') $e

Write-Host 'Returning from leave: turns on and cancels the schedule'
$s7 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Returning from leave'; ticket = @{ id = 502 }; company = $co; user = @{ id = 'req2'; name = 'Pat Manager'; email = 'pat@contoso.com' } } $u $tok
Check 'enabled' ($u['megan@contoso.com'].accountEnabled -eq $true) $s7.out
Check 'cancelled' (@($tok['1'] | ConvertFrom-Json).Count -eq 0 -and ($s7.out.done -contains 'scheduled leave cancelled')) $s7.out

Write-Host 'Self, no dates (old behaviour, now allowed): pauses now'
$s8 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Leave of absence'; ticket = @{ id = 503 }; company = $co; user = @{ id = 'req3'; name = 'Megan Bowen'; email = 'megan@contoso.com' } } $u $tok
Check 'self allowed, disabled' ($s8.out.status -eq 'success' -and $u['megan@contoso.com'].accountEnabled -eq $false) $s8.out
Check 'no token write' (-not ($s8.calls | Where-Object { $_ -match 'POST https://cr.test/v2/token$' })) $s8.calls

Write-Host 'Preview and bad input'
$u['megan@contoso.com'].accountEnabled = $true
$s9 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Sabbatical'; leaveStart = (& $d 2); confirm = $false; company = $co } $u $tok
Check 'preview, nothing saved' ($s9.out.status -eq 'preview' -and @($tok['1'] | ConvertFrom-Json).Count -eq 0) $s9.out
$s10 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Sabbatical'; leaveStart = (& $d 5); returnDate = (& $d 2); company = $co } $u $tok
Check 'return before start refused' ($s10.out.status -eq 'error' -and $s10.out.message -match 'after the start') $s10.out
$s11 = Invoke-Leave @{ leaveUser = 'nobody@contoso.com'; leaveType = 'Sabbatical'; company = $co } $u $tok
Check 'unknown user' ($s11.out.status -eq 'error' -and $s11.out.message -match 'no Microsoft 365 user') $s11.out
$s12 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Sabbatical'; leaveStart = ((& $d 4) + 'T05:00:00.000Z'); company = $co } $u $tok
Check 'ISO date with time parsed' ($s12.out.leaveStart -eq $today.AddDays(4).ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)) $s12.out
$s13 = Invoke-Leave @{ leaveUser = 'megan@contoso.com'; leaveType = 'Sabbatical'; leaveStart = $today.AddDays(6).ToString('MM/dd/yyyy'); company = $co } $u $tok
Check 'US date parsed, replaces earlier entry' ($s13.out.status -eq 'success' -and @($tok['1'] | ConvertFrom-Json).Count -eq 1) @($tok['1'])

if ($script:fail) { Write-Host "$($script:fail) failed"; exit 1 } else { Write-Host 'All passed' }
