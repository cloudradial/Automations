# Strict-mode tests for _shared/graph.ps1: sign-in and secret fallbacks, 429/503 retry with Retry-After,
# paging, 403 permission messages, 401 refresh, and the request shape of each helper.
. (Join-Path $PSScriptRoot 'mock.ps1')

$G = 'https://graph.microsoft.com'
$Sec = @{ 'M365-TenantId' = 'contoso.onmicrosoft.com'; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret' }
$Token = { param($c, $n) if ($c.Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = "tok$n"; expires_in = 3599 } }; return $null }

# --- sign-in ---
Reset-Mock @{ 'Entra-TenantID' = 'contoso.onmicrosoft.com'; 'Graph-ClientId' = 'app-id'; 'Entra-ClientSecret' = 'not-a-real-secret' } $Token
Invoke-WithLib @('graph.ps1') {
    $r = Connect-Graph
    $c = Get-LastCall
    Check 'Connect-Graph: falls back to Entra-* and Graph-* secret names' ($r.TenantId -eq 'contoso.onmicrosoft.com' -and $c.Uri -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token' -and $c.BodyObj.client_id -eq 'app-id' -and $c.BodyObj.grant_type -eq 'client_credentials' -and $c.BodyObj.scope -eq 'https://graph.microsoft.com/.default') (Show-Calls)
    Check 'Connect-Graph: bearer header kept in $GraphState' ($GraphState.Headers.Authorization -eq 'Bearer tok1') $GraphState.Headers.Authorization
}
Reset-Mock @{ 'M365-TenantID' = 'contoso.onmicrosoft.com' } $Token
Invoke-WithLib @('graph.ps1') {
    $m = Get-ThrowMessage { Connect-Graph }
    Check 'Connect-Graph: missing secrets are named' ($m -match 'M365-ClientId' -and $m -match 'M365-ClientSecret' -and $m -notmatch 'M365-TenantId') $m
    $m = Get-ThrowMessage { Invoke-Graph GET '/v1.0/users' }
    Check 'calls before Connect-Graph say so' ($m -match 'Connect-Graph') $m
}
Reset-Mock $Sec.Clone() { param($c, $n) New-HttpError 401 '{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}' }
Invoke-WithLib @('graph.ps1') {
    $m = Get-ThrowMessage { Connect-Graph }
    Check 'Connect-Graph: a bad secret is a plain error' ($m -match 'Invalid client secret' -and $m -match 'M365-ClientSecret') $m
}

# --- retry ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    if ($c.Uri -like '*/users/sam*' -and $n -eq 1) { New-HttpError 429 '{"error":{"code":"TooManyRequests","message":"Too many requests"}}' '7' }
    if ($c.Uri -like '*/users/sam*' -and $n -eq 2) { New-HttpError 503 }
    if ($c.Uri -like '*/users/busy*') { New-HttpError 429 '{"error":{"code":"TooManyRequests","message":"Too many requests"}}' '1' }
    return [pscustomobject]@{ id = 'u1'; userPrincipalName = 'sam@contoso.com' }
}
Invoke-WithLib @('graph.ps1') {
    $null = Connect-Graph
    $u = Get-GraphUser 'sam@contoso.com'
    Check 'Invoke-Graph: 429 waits Retry-After, 503 backs off, then succeeds' ($u.id -eq 'u1' -and @(Get-Calls 'GET' '*/users/sam*').Count -eq 3 -and (@($Mock.Sleeps) -join ',') -eq '7,4') "$(Show-Calls) sleeps=$(@($Mock.Sleeps) -join ',')"
    Check 'Get-GraphUser: UPN is URL-encoded and $select sent' ((Get-LastCall).Uri -like "$G/v1.0/users/sam%40contoso.com?`$select=id,userPrincipalName*") (Get-LastCall).Uri
    $Mock.Sleeps.Clear()
    $m = Get-ThrowMessage { Invoke-Graph GET '/v1.0/users/busy' }
    Check 'Invoke-Graph: gives up after MaxAttempts with the status' ($m -match 'HTTP 429' -and $m -match 'Too many requests' -and @(Get-Calls 'GET' '*/users/busy').Count -eq 5 -and @($Mock.Sleeps).Count -eq 4) "$m / sleeps=$(@($Mock.Sleeps).Count)"
    $null = Invoke-Graph GET 'organization'
    Check 'Invoke-Graph: a path without a version gets /v1.0' ((Get-LastCall).Uri -eq "$G/v1.0/organization") (Get-LastCall).Uri
}

# --- 401 refresh ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    if ($n -eq 1) { New-HttpError 401 '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired"}}' }
    return [pscustomobject]@{ id = 'u1' }
}
Invoke-WithLib @('graph.ps1') {
    $null = Connect-Graph
    $null = Invoke-Graph GET '/v1.0/users/u1'
    Check 'Invoke-Graph: 401 gets a new token and retries once' (@(Get-Calls 'POST' 'https://login.microsoftonline.com/*').Count -eq 2 -and (Get-LastCall).Headers.Authorization -eq 'Bearer tok2') (Show-Calls)
}

# --- paging ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    if ($c.Uri -eq "$G/v1.0/groups?`$select=id") { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g1' }, [pscustomobject]@{ id = 'g2' }); '@odata.nextLink' = "$G/v1.0/groups?`$select=id&`$skiptoken=A" } }
    if ($c.Uri -eq "$G/v1.0/groups?`$select=id&`$skiptoken=A") { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g3' }); '@odata.nextLink' = "$G/v1.0/groups?`$select=id&`$skiptoken=B" } }
    if ($c.Uri -eq "$G/v1.0/groups?`$select=id&`$skiptoken=B") { return [pscustomobject]@{ value = @() } }
    if ($c.Uri -like '*/authentication/methods') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'm1'; '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod' }) } }
    return [pscustomobject]@{ value = @() }
}
Invoke-WithLib @('graph.ps1') {
    $null = Connect-Graph
    $all = @(Get-GraphAll "/v1.0/groups?`$select=id")
    Check 'Get-GraphAll: follows @odata.nextLink to the end' ($all.Count -eq 3 -and $all[2].id -eq 'g3' -and @(Get-Calls 'GET' "$G/v1.0/groups*").Count -eq 3) "$($all.Count) / $(Show-Calls)"
    $m = @(Get-GraphAuthMethods 'u1')
    Check 'Get-GraphAuthMethods: a single method stays a list' ($m.Count -eq 1 -and $m[0].id -eq 'm1') "$($m.Count)"
    $none = @(Get-GraphRiskyUsers -AtRiskOnly)
    Check 'Get-GraphRiskyUsers: empty list, atRisk filter sent' ($none.Count -eq 0 -and (Get-LastCall).Uri -like "*riskyUsers?`$filter=riskState%20eq%20%27atRisk%27") (Get-LastCall).Uri
    $null = @(Get-GraphSignInActivity)
    Check 'Get-GraphSignInActivity: all users with signInActivity, page size 120' ((Get-LastCall).Uri -like "*/v1.0/users?`$select=*signInActivity&`$top=120") (Get-LastCall).Uri
}

# --- 403 names the permission ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'
}
Invoke-WithLib @('graph.ps1') {
    $null = Connect-Graph
    $cases = @(
        @('Get-GraphSignInActivity', { Get-GraphSignInActivity 'u1' }, 'AuditLog.Read.All'),
        @('Remove-GraphAuthMethod', { Remove-GraphAuthMethod 'u1' -MethodId 'm1' -MethodType '#microsoft.graph.phoneAuthenticationMethod' }, 'UserAuthenticationMethod.ReadWrite.All'),
        @('Get-GraphAuthMethods', { Get-GraphAuthMethods 'u1' }, 'UserAuthenticationMethod.Read.All'),
        @('Get-GraphRiskyUsers', { Get-GraphRiskyUsers }, 'IdentityRiskyUser.Read.All'),
        @('Add-GraphGroupMember', { Add-GraphGroupMember 'g1' 'u1' }, 'GroupMember.ReadWrite.All'),
        @('Set-GraphLicense', { Set-GraphLicense 'u1' -Add @('sku-1') }, 'LicenseAssignment.ReadWrite.All'),
        @('Revoke-GraphSessions', { Revoke-GraphSessions 'u1' }, 'User.RevokeSessions.All'),
        @('Set-GraphAccountEnabled', { Set-GraphAccountEnabled 'u1' $false }, 'User.EnableDisableAccount.All'),
        @('Set-GraphManager', { Set-GraphManager 'u1' 'u2' }, 'User.ReadWrite.All'),
        @('Get-GraphUser', { Get-GraphUser 'u1' }, 'User.Read.All')
    )
    foreach ($case in $cases) {
        $m = Get-ThrowMessage $case[1]
        Check "403 from $($case[0]) names $($case[2])" ($m -match '403' -and $m.Contains($case[2]) -and $m -match 'admin consent' -and $m -match 'Insufficient privileges') $m
    }
    Check 'no retry on 403' (@($Mock.Sleeps).Count -eq 0) "sleeps=$(@($Mock.Sleeps).Count)"
}

# --- request shapes ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    if ($c.Uri -like '*/users/ghost*' -or $c.Uri -like '*/groups/g9/members/*') { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
    if ($c.Uri -like '*/groups/g2/members/$ref') { New-HttpError 400 '{"error":{"code":"Request_BadRequest","message":"One or more added object references already exist for the following modified properties: ''members''."}}' }
    if ($c.Uri -like '*/users/nolocation/assignLicense') { New-HttpError 400 '{"error":{"code":"Request_BadRequest","message":"License assignment failed because user nolocation has an invalid usage location."}}' }
    return $null
}
Invoke-WithLib @('graph.ps1') {
    $null = Connect-Graph
    Check 'Get-GraphUser: 404 returns $null' ($null -eq (Get-GraphUser 'ghost@contoso.com')) (Show-Calls)
    $r = Add-GraphGroupMember 'g1' 'u1'; $c = Get-LastCall; $b = Read-Body $c
    Check 'Add-GraphGroupMember: POST members/$ref with directoryObjects id' ($r -eq 'added' -and $c.Method -eq 'POST' -and $c.Uri -eq "$G/v1.0/groups/g1/members/`$ref" -and $b.'@odata.id' -eq "$G/v1.0/directoryObjects/u1") "$($c.Uri) $($c.Body)"
    Check 'Add-GraphGroupMember: already a member is not an error' ((Add-GraphGroupMember 'g2' 'u1') -eq 'already-member') (Show-Calls)
    $r = Remove-GraphGroupMember 'g1' 'u1'; $c = Get-LastCall
    Check 'Remove-GraphGroupMember: DELETE members/{id}/$ref' ($r -eq 'removed' -and $c.Method -eq 'DELETE' -and $c.Uri -eq "$G/v1.0/groups/g1/members/u1/`$ref") $c.Uri
    Check 'Remove-GraphGroupMember: 404 means not a member' ((Remove-GraphGroupMember 'g9' 'u1') -eq 'not-member') (Show-Calls)
    Set-GraphManager 'u1' 'u2'; $c = Get-LastCall
    Check 'Set-GraphManager: PUT manager/$ref' ($c.Method -eq 'PUT' -and $c.Uri -eq "$G/v1.0/users/u1/manager/`$ref" -and (Read-Body $c).'@odata.id' -eq "$G/v1.0/users/u2") "$($c.Uri) $($c.Body)"
    Revoke-GraphSessions 'u1'; $c = Get-LastCall
    Check 'Revoke-GraphSessions: POST revokeSignInSessions' ($c.Method -eq 'POST' -and $c.Uri -eq "$G/v1.0/users/u1/revokeSignInSessions") $c.Uri
    Set-GraphAccountEnabled 'u1' $false; $c = Get-LastCall
    Check 'Set-GraphAccountEnabled: PATCH accountEnabled false' ($c.Method -eq 'PATCH' -and (Read-Body $c).accountEnabled -eq $false) $c.Body
    Set-GraphLicense 'u1' -Add @('sku-a') -Remove @('sku-b'); $c = Get-LastCall; $b = Read-Body $c
    Check 'Set-GraphLicense: one add and one remove stay arrays' ($c.Uri -eq "$G/v1.0/users/u1/assignLicense" -and $c.Body -match '"addLicenses":\[\{' -and $c.Body -match '"removeLicenses":\["sku-b"\]' -and $b.addLicenses[0].skuId -eq 'sku-a') $c.Body
    $before = $Mock.Calls.Count; Set-GraphLicense 'u1'
    Check 'Set-GraphLicense: nothing to do makes no call' ($Mock.Calls.Count -eq $before) ''
    $m = Get-ThrowMessage { Set-GraphLicense 'nolocation' -Add @('sku-a') }
    Check 'Set-GraphLicense: missing usage location is explained' ($m -match 'no usage location') $m
    Remove-GraphAuthMethod 'u1' -Method ([pscustomobject]@{ id = 'm1'; '@odata.type' = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' }); $c = Get-LastCall
    Check 'Remove-GraphAuthMethod: maps the type to its collection' ($c.Method -eq 'DELETE' -and $c.Uri -eq "$G/v1.0/users/u1/authentication/microsoftAuthenticatorMethods/m1") $c.Uri
    $m = Get-ThrowMessage { Remove-GraphAuthMethod 'u1' -MethodId 'p1' -MethodType '#microsoft.graph.passwordAuthenticationMethod' }
    Check 'Remove-GraphAuthMethod: password method refused' ($m -match "can't be removed") $m
    Check 'Get-GraphRiskyUsers -UserId: 404 is not risky' ($null -eq (Get-GraphRiskyUsers -UserId 'ghost')) (Show-Calls)
}

# --- temporary password ---
Invoke-WithLib @('graph.ps1') {
    $p1 = New-GraphTempPassword; $p2 = New-GraphTempPassword 20
    Check 'New-GraphTempPassword: length and every character class' ($p1.Length -eq 16 -and $p2.Length -eq 20 -and $p1 -cmatch '[A-Z]' -and $p1 -cmatch '[a-z]' -and $p1 -match '\d' -and $p1 -match '[^A-Za-z0-9]' -and $p1 -ne $p2) 'shape'
    Check 'New-GraphTempPassword: no look-alike characters' (-not ((1..50 | ForEach-Object { New-GraphTempPassword }) -join '' -cmatch '[O0Il1]')) ''
}

Complete-Test
