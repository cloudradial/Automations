# Strict-mode tests for _shared/psa.ps1: ConnectWise notes in the API's real shape (a JSON array that
# Invoke-RestMethod hands over as ONE object, _info links, the note flags, text with line breaks, more than one
# page), the duplicate-note marker on a rerun, API URL clean-up, list replies, and redirect handling
# (a write is never sent twice; a GET follows only a safe https redirect).
# Placeholder data only (Contoso, Example MSP).
. (Join-Path $PSScriptRoot 'mock.ps1')

$CwSecrets = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://staging.cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
$CW = 'https://staging.cw.example.com/v4_6_release/apis/3.0'
$CANON = 'https://automation.cw.example.com/v4_6_release/apis/3.0'
function O { param([hashtable]$h) [pscustomobject]$h }
function Write-Calls { return @($Mock.Calls | Where-Object { $_.Method -in @('POST', 'PUT', 'PATCH', 'DELETE') }) }

# ---- a ConnectWise ticket whose notes live in $Store, served the way the API serves them ----
$Store = New-Object System.Collections.ArrayList
function Reset-Store {
    param([int]$Filler = 0, [string]$InfoHost = 'staging.cw.example.com')
    $Store.Clear()
    for ($k = 1; $k -le $Filler; $k++) { $null = $Store.Add((New-CwNote ($Store.Count + 1) "Routine check $k.`nNothing to report." $InfoHost)) }
}
function New-CwNote {
    param([int]$Id, [string]$Text, [string]$InfoHost = 'staging.cw.example.com', [bool]$Internal = $true)
    $api = "https://$InfoHost/v4_6_release/apis/3.0/"   # ConnectWise's own links carry a doubled slash after 3.0
    O @{ id = 130000 + $Id; ticketId = 29000; text = $Text; detailDescriptionFlag = (-not $Internal); internalAnalysisFlag = $Internal; resolutionFlag = $false
        issueFlag = $false; member = (O @{ id = 186; identifier = 'APIMember'; name = 'API Member'; _info = (O @{ member_href = "$api/system/members/186" }) })
        dateCreated = '2026-10-09T13:40:02Z'; createdBy = 'APIMember'; internalFlag = $Internal; externalFlag = $false
        _info = (O @{ lastUpdated = '2026-10-09T13:40:02Z'; updatedBy = 'APIMember'; ticket_href = "$api/service/tickets/29000" }) }
}
# GET notes: orderBy id asc, pageSize and page from the query; the reply is one [object[]] like Invoke-RestMethod's.
$NotesGet = {
    param($c, $n)
    $size = 25; $page = 1
    if ($c.Uri -match '[?&]pageSize=(\d+)') { $size = [int]$Matches[1] }
    if ($c.Uri -match '[?&]page=(\d+)') { $page = [int]$Matches[1] }
    $slice = @($Store | Select-Object -Skip (($page - 1) * $size) -First $size)
    return , $slice
}
$NotesPost = { param($c, $n) $b = $c.Body | ConvertFrom-Json; $note = New-CwNote ($Store.Count + 1) $b.text 'staging.cw.example.com' ([bool]$b.internalAnalysisFlag); $null = $Store.Add($note); return $note }
function Use-Cw { param([scriptblock]$Handler, [hashtable]$Extra = @{}) $s = $CwSecrets.Clone(); foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }; Reset-Mock $s $Handler }

# ======== 1. The missed marker: ConnectWise notes in the real reply shape ========
# Before the fix, Invoke-Psa returned Invoke-RestMethod's output as is, so "@(Invoke-PsaRead ... | Where-Object)"
# saw ONE record (the whole array): no text, no marker, and a second identical write went through.
Reset-Store -Filler 3
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like "$CW/service/tickets/29000/notes[?]*") { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CW/service/tickets/29000/notes") { return (& $NotesPost $c $n) }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $notes = @(Get-PsaTicketNotes -Id 29000)
    Check 'connectwise: an array reply is read as its notes, not one record' ($notes.Count -eq 3 -and $notes[0].text -eq "Routine check 1.`nNothing to report." -and $notes[0].internal -and $notes[0].author -eq 'APIMember') (($notes | ForEach-Object { "$($_.id):$($_.text)" }) -join ' | ')
    $mk = 'role-change-mover: preview 0a1b2c3d 2026-10-09'
    $r1 = Add-PsaNote -Id 29000 -Text "Role change plan (preview).`nMove to Finance." -Title 'Role change plan (preview)' -Marker $mk
    $r2 = Add-PsaNote -Id 29000 -Text "Role change plan (preview).`nMove to Finance." -Title 'Role change plan (preview)' -Marker $mk
    $posts = @(Get-Calls 'POST' "$CW/service/tickets/29000/notes")
    Check 'connectwise: a second identical write is skipped (rerun writes nothing twice)' ($r1 -eq 'written' -and $r2 -eq 'already-present' -and $posts.Count -eq 1 -and $Store.Count -eq 4) "$r1 / $r2 / posts=$($posts.Count) / $(Show-Calls)"
    Check 'connectwise: the marker is the internal note''s last line, after a line break' ($Store[3].text -match "Move to Finance\.\n\[role-change-mover: preview 0a1b2c3d 2026-10-09\]$" -and $Store[3].internalAnalysisFlag) $Store[3].text
    Check 'connectwise: the read-back marker check is case-insensitive and needs the brackets' ((Test-PsaNoteMarker -Id 29000 -Marker '[ROLE-CHANGE-MOVER: PREVIEW 0A1B2C3D 2026-10-09]') -and -not (Test-PsaNoteMarker -Id 29000 -Marker 'role-change-mover: preview 0a1b2c3d 2026-10-10')) ''
    $t = Get-PsaTicket '29000'
    Check 'connectwise: Get-PsaTicket reads the first note from a one-item array reply' ($t.description -eq "Routine check 1.`nNothing to report.") $t.description
}

# More notes than one page: the marker is on page 2 and is still found.
Reset-Store -Filler 130
$null = $Store.Add((New-CwNote 131 "Earlier run.`n[aai-test: paged 1]"))
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like "$CW/service/tickets/29000/notes[?]*") { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST') { return (& $NotesPost $c $n) }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $notes = @(Get-PsaTicketNotes -Id 29000)
    $pages = @(Get-Calls 'GET' "$CW/service/tickets/29000/notes?*")
    Check 'connectwise: notes page by 100 until a short page' ($notes.Count -eq 131 -and $pages.Count -eq 2 -and $pages[0].Uri -like '*orderBy=id%20asc&pageSize=100&page=1' -and $pages[1].Uri -like '*&page=2') "$($notes.Count) / $(Show-Calls)"
    $res = Add-PsaNote -Id 29000 -Text 'Earlier run.' -Marker 'aai-test: paged 1'
    Check 'connectwise: a marker on page 2 stops the write' ($res -eq 'already-present' -and @(Write-Calls).Count -eq 0) "$res $(Show-Calls)"
}

# ======== 2. List replies after the change (one-item lists, holders) ========
Use-Cw { param($c, $n)
    if ($c.Uri -like "$CW/company/companies*") { return , @((O @{ id = 42; name = 'Contoso' })) }
    if ($c.Uri -like "$CW/service/priorities*") { return , @((O @{ id = 1; name = 'Priority 1 - Emergency Response' }), (O @{ id = 3; name = 'Priority 3 - Normal Response' })) }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CW/service/tickets") { return (O @{ id = 501 }) }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $co = @(Find-PsaCompany 'Contoso')
    Check 'connectwise: a one-item company list is one company' ($co.Count -eq 1 -and $co[0].id -eq '42' -and $co[0].exact) ($co | ConvertTo-Json -Compress -Depth 2 -WarningAction SilentlyContinue)
    $t = New-PsaTicket -CompanyId 42 -Summary 'Printer offline' -Priority critical
    Check 'connectwise: the priority list reply is matched by name' ((Read-Body (Get-LastCall)).priority.id -eq 1 -and $t.id -eq '501') ((Get-LastCall).Body)
    Check 'Get-PsaListReply: bare one-item list, holder with items, holder with none, $null' (
        @(Get-PsaListReply (O @{ id = 7; name = 'Contoso' }) @('clients')).Count -eq 1 -and
        @(Get-PsaListReply (O @{ clients = @((O @{ id = 1 }), (O @{ id = 2 })) }) @('clients')).Count -eq 2 -and
        @(Get-PsaListReply (O @{ clients = @() }) @('clients')).Count -eq 0 -and
        @(Get-PsaListReply (O @{ contracts = @(); clientcontracts = @((O @{ id = 3 })) }) @('contracts', 'clientcontracts'))[0].id -eq 3 -and
        @(Get-PsaListReply $null @('x')).Count -eq 0) ''
}
Reset-Mock @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' } { param($c, $n)
    if ($c.Uri -like '*/auth/token') { return (O @{ access_token = 'halo-token' }) }
    if ($c.Uri -like '*/api/Client?*') { return , @((O @{ id = 42; name = 'Contoso' })) }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $co = @(Find-PsaCompany 'Contoso')
    Check 'halopsa: a bare one-item client list (no clients holder) is still read' ($co.Count -eq 1 -and $co[0].id -eq '42') (Show-Calls)
}

# ======== 3. API URL clean-up ========
Use-Cw { param($c, $n) return , @() } @{ 'CW-ApiUrl' = "  https://staging.cw.example.com//v4_6_release//apis/3.0/  " }
Invoke-WithLib @('psa.ps1') {
    $c = Connect-Psa
    $null = @(Get-PsaTicketNotes -Id 29000)
    Check 'CW-ApiUrl: spaces trimmed, doubled slashes collapsed, trailing slash dropped' ($c.Base -ceq $CW -and (Get-LastCall).Uri -like "$CW/service/tickets/29000/notes?*") "$($c.Base) / $(Show-Calls)"
    Check 'ConvertTo-PsaBaseUrl keeps the scheme and port' ((ConvertTo-PsaBaseUrl 'https://cw.example.com:8443//a//b/') -ceq 'https://cw.example.com:8443/a/b' -and (ConvertTo-PsaBaseUrl 'https://cw.example.com') -ceq 'https://cw.example.com') ''
}

# ======== 4. A write answered with a redirect (the note was saved first) ========
# What staging did: the POST is saved, then a 302 to the canonical host over http.
Reset-Store -Filler 1
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/29000/notes[?]*') { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/service/tickets/29000/notes') {
        $null = & $NotesPost $c $n
        if ($c.MaxRedirect -ne 0) { throw 'the write did not ask for no redirects' }
        New-HttpError 302 '' '' 'http://automation.cw.example.com/v4_6_release/apis/3.0/service/tickets/29000/notes/130002'
    }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $res = Add-PsaNote -Id 29000 -Text "Role change plan (preview).`nMove to Finance." -Marker 'aai-test: redirect 1'
    $posts = @(Write-Calls)
    Check 'redirect after a POST: sent once, read back, marker found, returns written' ($res -eq 'written' -and $posts.Count -eq 1 -and $Store.Count -eq 2) "$res / $(Show-Calls)"
    $reread = @(Get-Calls 'GET' '*/service/tickets/29000/notes?*')[-1]
    Check 'redirect after a POST: later calls go to the https host it named' ($PsaState.Conn.Base -ceq $CANON -and $reread.Uri -like "$CANON/*") "$($PsaState.Conn.Base) / $(Show-Calls)"
    Check 'redirect after a POST: a warning says to fix the API URL secret' (@($PsaState.Warnings | Where-Object { $_ -match 'redirected calls for staging\.cw\.example\.com to automation\.cw\.example\.com' }).Count -eq 1 -and @($PsaState.Warnings | Where-Object { $_ -match 'reading the ticket back showed the note was saved' }).Count -eq 1) (@($PsaState.Warnings) -join ' | ')
    $res2 = Add-PsaNote -Id 29000 -Text "Role change plan (preview).`nMove to Finance." -Marker 'aai-test: redirect 1'
    Check 'redirect after a POST: a rerun writes nothing' ($res2 -eq 'already-present' -and @(Write-Calls).Count -eq 1 -and $Store.Count -eq 2) "$res2 / $(Show-Calls)"
}

# A redirect after a POST that was NOT saved: one POST, then a plain failure.
Reset-Store -Filler 1
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/29000/notes[?]*') { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST') { New-HttpError 302 '' '' 'https://automation.cw.example.com/v4_6_release/apis/3.0/service/tickets/29000/notes' }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { Add-PsaNote -Id 29000 -Text 'Checked the printer.' -Marker 'aai-test: redirect 2' }
    Check 'redirect after a POST that was not saved: not resent, says so' ($m -match 'answered with a redirect \(HTTP 302\)' -and $m -match 'It was not sent again' -and $m -match 'found no such note' -and @(Write-Calls).Count -eq 1) "$m / $(Show-Calls)"
    $m = Get-ThrowMessage { Add-PsaNote -Id 29000 -Text 'No marker here.' }
    Check 'redirect after a POST without a marker, not saved: not resent, says so' ($m -match 'found no such note' -and @(Write-Calls).Count -eq 2) "$m / $(Show-Calls)"
}

# Without a marker, the text itself is looked for (line breaks and spaces ignored).
Reset-Store -Filler 1
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/29000/notes[?]*') { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST') { $null = & $NotesPost $c $n; New-HttpError 301 '' '' 'http://automation.cw.example.com/v4_6_release/apis/3.0/x' }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $res = Add-PsaNote -Id 29000 -Text "Checked the printer.`r`nAll good."
    Check 'redirect after a POST without a marker: the saved text is found, nothing thrown or resent' ($null -eq $res -and @(Write-Calls).Count -eq 1) "$res / $(Show-Calls)"
}

# Invoke-RestMethod refusing an https-to-http redirect itself (no status code, as the live error read).
Reset-Store -Filler 1 -InfoHost 'automation.cw.example.com'
Use-Cw { param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/29000/notes[?]*') { return (& $NotesGet $c $n) }
    if ($c.Method -eq 'POST') { $null = & $NotesPost $c $n; throw [System.InvalidOperationException]::new('Cannot follow an insecure redirection by default. Reissue the command specifying the -AllowInsecureRedirect switch.') }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $res = Add-PsaNote -Id 29000 -Text 'Checked the printer.' -Marker 'aai-test: insecure 1'
    Check 'an "insecure redirection" error after a POST is treated as a redirect and read back' ($res -eq 'written' -and @(Write-Calls).Count -eq 1) "$res / $(Show-Calls)"
    Check 'with no Location, the host named in ConnectWise''s _info links is used next' ($PsaState.Conn.Base -ceq $CANON -and (@(Get-Calls 'GET' '*/notes?*')[-1]).Uri -like "$CANON/*") "$($PsaState.Conn.Base) / $(Show-Calls)"
}

# Other writes are never resent either.
Use-Cw { param($c, $n) if ($c.Method -eq 'PATCH') { New-HttpError 307 '' '' 'https://automation.cw.example.com/v4_6_release/apis/3.0/service/tickets/29000' }; return $null }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { Set-PsaAssignee -Id 29000 -UserId 'jlee' }
    Check 'a redirected PATCH is sent once and reported' ($m -match '^ConnectWise PATCH /service/tickets/29000 was answered with a redirect \(HTTP 307\)' -and @(Write-Calls).Count -eq 1 -and $PsaState.LastWriteRedirect.Code -eq 307 -and (Get-LastCall).MaxRedirect -eq 0) "$m / $(Show-Calls)"
}

# ======== 5. GET redirects ========
Use-Cw { param($c, $n)
    if ($c.Uri -like "$CW/service/tickets/29000") { New-HttpError 301 '' '' 'https://automation.cw.example.com/v4_6_release/apis/3.0/service/tickets/29000' }
    if ($c.Uri -like "$CANON/service/tickets/29000") { return (O @{ id = 29000; summary = 'Printer offline'; company = (O @{ id = 42 }) }) }
    return , @()
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $t = Get-PsaTicket '29000'
    Check 'GET redirect to a sibling https host: followed once, and the run moves there' ($t.summary -eq 'Printer offline' -and $PsaState.Conn.Base -ceq $CANON -and (Get-LastCall).Uri -like "$CANON/*" -and (Get-LastCall).MaxRedirect -eq 0) (Show-Calls)
}
Use-Cw { param($c, $n)
    if ($c.Uri -like "$CW/service/tickets/29000") { New-HttpError 302 '' '' 'http://automation.cw.example.com/v4_6_release/apis/3.0/service/tickets/29000' }
    if ($c.Uri -like "$CANON/service/tickets/29000") { return (O @{ id = 29000; summary = 'Printer offline' }) }
    if ($c.Uri -like 'http://*') { throw 'credentials sent over http' }
    return , @()
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $t = Get-PsaTicket '29000'
    Check 'GET redirect to http: upgraded to https, never sent over http' ($t.summary -eq 'Printer offline' -and @($Mock.Calls | Where-Object { $_.Uri -like 'http://*' }).Count -eq 0) (Show-Calls)
}
Use-Cw { param($c, $n)
    if ($c.Uri -like "$CW/service/tickets/29000") { New-HttpError 302 '' '' 'https://login.other.example.net/steal' }
    return , @()
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { $null = Get-PsaTicket '29000' }
    Check 'GET redirect to another domain: not followed, plain message' ($m -match 'was redirected \(HTTP 302\) to https://login\.other\.example\.net, which isn''t followed' -and @($Mock.Calls | Where-Object { $_.Uri -like '*other.example.net*' }).Count -eq 0 -and $PsaState.Conn.Base -ceq $CW) "$m / $(Show-Calls)"
}
Use-Cw { param($c, $n) New-HttpError 302 '' '' $c.Uri.Replace('https://', 'http://') }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { $null = Get-PsaTicket '29000' }
    Check 'GET redirect loop: stops after 3 hops' ($m -match 'was redirected' -and @(Get-Calls 'GET' '*/service/tickets/29000').Count -eq 4) "$m / $(Show-Calls)"
}
Invoke-WithLib @('psa.ps1') {
    Check 'Get-PsaRedirectTarget: sibling, same host, http upgrade, other domain, bare domains' (
        (Get-PsaRedirectTarget 'https://staging.cw.example.com/a' 'http://automation.cw.example.com/a?b=1') -ceq 'https://automation.cw.example.com/a?b=1' -and
        (Get-PsaRedirectTarget 'https://cw.example.com/a' 'https://cw.example.com/b') -ceq 'https://cw.example.com/b' -and
        $null -eq (Get-PsaRedirectTarget 'https://cw.example.com/a' 'https://cw.example.org/a') -and
        $null -eq (Get-PsaRedirectTarget 'https://example.com/a' 'https://other.com/a') -and
        $null -eq (Get-PsaRedirectTarget 'https://cw.example.com/a' 'ftp://cw.example.com/a') -and
        $null -eq (Get-PsaRedirectTarget 'https://cw.example.com/a' $null)) ''
}

Complete-Test
