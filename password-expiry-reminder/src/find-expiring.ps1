# === NODE: Find passwords that expire soon (read-only) ===
# Reads each verified domain's password lifetime (passwordValidityPeriodInDays; 2147483647 or empty means the
# passwords never expire, which is Microsoft's default for new tenants) and every user. Works out each
# remaining user's expiry date as lastPasswordChangeDateTime plus the lifetime of their sign-in domain.
# Skips: disabled accounts, guests, accounts synced from on-premises Active Directory (their expiry is set
# there, which this workflow can't read, so they are listed in warnings and never emailed), accounts with
# DisablePasswordExpiration, and accounts without an email address.
# Reminder rule: a person is due when the number of whole days left (in timeZone) is one of daysBeforeExpiry.
# With catchUpDays N above 1, a person is also due when a reminder day fell in the last N-1 days (a missed
# run); each person gets at most one email per run, for the nearest reminder day. Expired passwords get no email.
# Changes nothing and sends nothing. Needs User.Read.All and Domain.Read.All.
$ErrorActionPreference = 'Stop'
$st = Read-PeState
$opt = $st['inputs']
$thr = @(@(Get-PeProp $opt 'daysBeforeExpiry') | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Sort-Object)
$catchUp = [int](Get-PeProp $opt 'catchUpDays'); if ($catchUp -lt 1) { $catchUp = 1 }
$only = @(@(Get-PeProp $opt 'onlyUsers') | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
$tzId = [string](Get-PeProp $opt 'timeZone'); if (-not $tzId) { $tzId = 'UTC' }
$tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzId)
$counts = $st['counts']

try { $conn = Connect-Graph } catch { Stop-PeRun $st 'error' "Couldn't sign in to Microsoft 365: $($_.Exception.Message) No email was sent." }
$st['tenant_id'] = [string]$conn.TenantId
$tenantWanted = [string](Get-PeProp $opt 'company_tenant_id')
if ($tenantWanted -and $tenantWanted -ne ([string]$conn.TenantId).ToLowerInvariant()) {
    Stop-PeRun $st 'rejected' "The run asked for Microsoft 365 tenant $tenantWanted, but this runner is set up for a different tenant (the M365-TenantId secret), so nothing was read and no email was sent."
}

# 1. Password lifetime per verified domain. 0 here means the passwords never expire.
$domains = @()
try { $domains = @(Get-GraphAll -Path '/v1.0/domains' -Permission 'Domain.Read.All') }
catch {
    $m = [string]$_.Exception.Message
    if ($m -match '\(403 Forbidden\)') { Stop-PeRun $st 'error' "Can't read the tenant's password expiry settings. The app registration needs the Domain.Read.All application permission, with admin consent. No email was sent." }
    Stop-PeRun $st 'error' "Couldn't read the Microsoft 365 domains: $m No email was sent."
}
$life = @{}
$expiring = @()
foreach ($d in $domains) {
    if ((Get-GraphProp $d 'isVerified') -ne $true) { continue }
    $name = ([string](Get-GraphProp $d 'id')).ToLowerInvariant()
    if (-not $name) { continue }
    $v = Get-GraphProp $d 'passwordValidityPeriodInDays'
    $days = 0
    if ($null -ne $v -and [string]$v -match '^\d+$' -and [int64]$v -gt 0 -and [int64]$v -lt 2147483647) { $days = [int]$v; $expiring += "$name ($days days)" }
    $life[$name] = $days
}
$nowUtc = (Get-Date).ToUniversalTime()
$st['checked_at'] = $nowUtc.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
if (-not $expiring.Count) {
    $st['done'] = $true
    $st['status'] = 'success'
    $st['message'] = 'Passwords in this Microsoft 365 tenant are set to never expire, so nobody needs a reminder. No email was sent.'
    $st['actions'] = @(@($st['actions']) + "Checked $(Get-PePlural $life.Count 'verified domain' 'verified domains'): none has a password expiry policy.")
    Set-NodeOutput $st
    return
}

# 2. Every user.
$sel = 'id,displayName,givenName,userPrincipalName,mail,accountEnabled,userType,passwordPolicies,lastPasswordChangeDateTime,onPremisesSyncEnabled'
$users = @()
try { $users = @(Get-GraphAll -Path "/v1.0/users?`$select=$sel&`$top=999" -Permission 'User.Read.All') }
catch {
    $m = [string]$_.Exception.Message
    if ($m -match '\(403 Forbidden\)') { Stop-PeRun $st 'error' "Can't read the Microsoft 365 user list. The app registration needs the User.Read.All application permission, with admin consent. No email was sent." }
    Stop-PeRun $st 'error' "Couldn't read the Microsoft 365 user list: $m No email was sent."
}

# 3. Sort every user into skipped, not due yet, or due today.
$todayLocal = [TimeZoneInfo]::ConvertTimeFromUtc($nowUtc, $tz).Date
$maxThr = [int]($thr | Measure-Object -Maximum).Maximum
$found = @{}
$synced = @()
$due = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
foreach ($u in $users) {
    if ($null -eq $u) { continue }
    $id = ([string](Get-GraphProp $u 'id')).ToLowerInvariant()
    $upn = [string](Get-GraphProp $u 'userPrincipalName')
    $mail = [string](Get-GraphProp $u 'mail')
    if ($only.Count) {
        $hits = @($only | Where-Object { $_ -eq $id -or $_ -eq $upn.ToLowerInvariant() -or ($mail -and $_ -eq $mail.ToLowerInvariant()) })
        if (-not $hits.Count) { continue }
        foreach ($h in $hits) { $found[$h] = $true }
    }
    $counts.checked++
    if ((Get-GraphProp $u 'accountEnabled') -eq $false) { $counts.skippedDisabled++; continue }
    if (([string](Get-GraphProp $u 'userType')) -ieq 'Guest') { $counts.skippedGuests++; continue }
    if ((Get-GraphProp $u 'onPremisesSyncEnabled') -eq $true) { $counts.skippedSynced++; $synced += $upn; continue }
    $domain = ($upn.ToLowerInvariant() -split '@')[-1]
    if ([string](Get-GraphProp $u 'passwordPolicies') -match '(?i)DisablePasswordExpiration') { $counts.skippedNeverExpires++; continue }
    if (-not $life.ContainsKey($domain)) { $counts.skippedOther++; $null = $skipped.Add([ordered]@{ upn = $upn; reason = "Its sign-in domain ($domain) isn't a verified domain in this tenant, so its password expiry isn't known." }); continue }
    if ($life[$domain] -eq 0) { $counts.skippedNeverExpires++; continue }
    if (-not $mail) { $counts.skippedNoMail++; $null = $skipped.Add([ordered]@{ upn = $upn; reason = 'No email address (no mailbox), so there is nowhere to send a reminder.' }); continue }
    $changed = ConvertTo-PeDate (Get-GraphProp $u 'lastPasswordChangeDateTime')
    if ($null -eq $changed) { $counts.skippedOther++; $null = $skipped.Add([ordered]@{ upn = $upn; reason = 'Microsoft 365 has no last password change date for this account.' }); continue }

    $expUtc = $changed.AddDays($life[$domain])
    $expLocal = [TimeZoneInfo]::ConvertTimeFromUtc($expUtc, $tz)
    $daysLeft = [int]($expLocal.Date - $todayLocal).TotalDays
    $expText = $expLocal.ToString('dddd d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture) + ' at ' + $expLocal.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) + " ($tzId)"
    if ($expUtc -le $nowUtc) {
        $counts.alreadyExpired++
        $null = $skipped.Add([ordered]@{ upn = $upn; reason = "Password already expired on $expText. They will be asked to change it at their next sign-in, so no reminder was sent." })
        continue
    }
    if ($daysLeft -le $maxThr) { $counts.expiringSoon++ }
    # The nearest reminder day from today back to catchUpDays - 1 days ago.
    $hitT = @($thr | Where-Object { $_ -ge $daysLeft -and $_ -le ($daysLeft + $catchUp - 1) } | Select-Object -First 1)
    if (-not $hitT.Count) { continue }
    $first = [string](Get-GraphProp $u 'givenName')
    if (-not $first.Trim()) { $first = ([string](Get-GraphProp $u 'displayName') -split '\s+' | Where-Object { $_ } | Select-Object -First 1) }
    $null = $due.Add([ordered]@{
            id          = [string](Get-GraphProp $u 'id')
            upn         = $upn
            mail        = $mail
            name        = [string](Get-GraphProp $u 'displayName')
            firstName   = $(if ($first) { [string]$first } else { '' })
            daysLeft    = $daysLeft
            reminderDay = [int]$hitT[0]
            expires     = $expUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
            expiresText = $expText
            result      = 'due'
        })
}
$counts.due = $due.Count

$warn = @($st['warnings'])
foreach ($o in $only) { if (-not $found.ContainsKey($o)) { $warn += "onlyUsers: no Microsoft 365 account matches '$o'." } }
if ($synced.Count) { $warn += "$(Get-PePlural $synced.Count 'account is' 'accounts are') synced from on-premises Active Directory and $(if ($synced.Count -eq 1) { 'was' } else { 'were' }) not emailed: their password expiry is set by Active Directory, which this workflow can't read, so it won't guess a date. Remind them from Active Directory instead: $(Join-PeNames $synced)." }
if ($counts.skippedOther -or $counts.skippedNoMail) { $warn += "$(Get-PePlural ($counts.skippedOther + $counts.skippedNoMail) 'account was' 'accounts were') skipped for another reason; see skipped." }

$st['due'] = @($due)
$st['skipped'] = @($skipped)
$st['warnings'] = @($warn)
$st['actions'] = @(@($st['actions']) + "Checked $(Get-PePlural $counts.checked 'Microsoft 365 account' 'Microsoft 365 accounts') against the password expiry policy ($($expiring -join ', ')): $($counts.expiringSoon) expire within $maxThr days and $($due.Count) $(if ($due.Count -eq 1) { 'is' } else { 'are' }) on a reminder day today.")
Set-NodeOutput $st
