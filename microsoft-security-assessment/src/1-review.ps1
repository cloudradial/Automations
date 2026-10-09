# === NODE: Review Microsoft 365 security ===
# Reads the run input, resolves the CloudRadial company, reads the tenant's security settings
# from Microsoft Graph and turns each check into one assessment question (import-file columns,
# support KB 360052746791). No AI: every answer comes from a fixed rule.
#   Run input (JSON):
#     companyId        - CloudRadial companyId (or companyName)
#     companyName      - CloudRadial company name, exact or a unique partial match
#     tenantId         - Entra tenant to review (default: the M365-TenantID secret)
#     assessmentTitle  - the assessment's name, default "Microsoft 365 Security Assessment". Each run
#                        is titled "<name> - M/d/yy", the portal's own run naming.
#     runTitle         - overrides the run's title (for example a second run on the same day)
#     portalUrl        - the partner portal, e.g. https://contoso.us.cloudradial.com, used to create the
#                        run (default: the CloudRadial-PortalUrl secret; without either, no run is made)
#     mode             - apply (default) creates the assessment; plan only previews the questions
#     assessmentType   - omit to upload the type 20 assessment (once) and then the type 30 run, like
#                        the portal's own pairs. Send 20 or 30 to upload only that one. The type codes
#                        are undocumented; from live data 10 = template, 20 = assessment, 30 = run.
#   Secrets (runner Key Vault): M365-ClientID, M365-ClientSecret, M365-TenantID (optional when
#   tenantId is sent), CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey.
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n, $d = $null) if ($null -eq $o) { return $d }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $d }; $p = $o.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { return $p.Value }; return $d }
function Stop-Run { param([string]$m) Set-NodeOutput @{ status = 'error'; message = $m }; throw $m }

# ---- run input ----
$in = $null; try { $in = Get-NodeInput } catch { }
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $in = $(if ($in.Trim().StartsWith('{')) { $in | ConvertFrom-Json } else { $null }) }
$companyId = 0; [int]::TryParse([string](Get-Prop $in 'companyId' ''), [ref]$companyId) | Out-Null
$companyName = ([string](Get-Prop $in 'companyName' '')).Trim()
$tenantId = ([string](Get-Prop $in 'tenantId' '')).Trim()
$runDate = (Get-Date).ToUniversalTime()
$title = ([string](Get-Prop $in 'assessmentTitle' '')).Trim()
if (-not $title) { $title = 'Microsoft 365 Security Assessment' }
$runTitle = ([string](Get-Prop $in 'runTitle' '')).Trim()
if (-not $runTitle) { $runTitle = $title + ' - ' + $runDate.ToString('M/d/yy', [System.Globalization.CultureInfo]::InvariantCulture) }
$mode = ([string](Get-Prop $in 'mode' '')).Trim().ToLowerInvariant(); if ($mode -ne 'plan') { $mode = 'apply' }
$uploads = 'both'; $t = ([string](Get-Prop $in 'assessmentType' '')).Trim(); if ($t -in @('20', '30')) { $uploads = $t }
if ($companyId -le 0 -and -not $companyName) { Stop-Run 'Send companyId or companyName in the run input, for example {"companyName":"Contoso","mode":"plan"}.' }

# ---- secrets ----
function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
$s = [ordered]@{}
foreach ($n in @('M365-ClientID', 'M365-ClientSecret', 'M365-TenantID', 'CloudRadial-BaseUrl', 'CloudRadial-PublicKey', 'CloudRadial-PrivateKey')) { $s[$n] = Get-Secret $n }
if (-not $tenantId) { $tenantId = [string]$s['M365-TenantID'] }
$missing = @($s.Keys | Where-Object { [string]::IsNullOrWhiteSpace([string]$s[$_]) -and -not ($_ -eq 'M365-TenantID' -and $tenantId) })
if ($missing.Count) { Stop-Run "Please add these secrets to your runner Key Vault and run again: $($missing -join ', ')" }

# ---- CloudRadial company ----
$crBase = ([string]$s['CloudRadial-BaseUrl']).TrimEnd('/')
$crHeaders = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($s['CloudRadial-PublicKey']):$($s['CloudRadial-PrivateKey'])")); Accept = 'application/json' }
function Get-CrRows { param([string]$Path) @(Get-Prop (Invoke-RestMethod -Method Get -Uri "$crBase$Path" -Headers $crHeaders) 'value' @()) }
try {
    if ($companyId -gt 0) { $hits = @(Get-CrRows "/v2/odata/company?`$filter=companyId eq $companyId") }
    else {
        $q = $companyName.Replace("'", "''")
        $hits = @(Get-CrRows ("/v2/odata/company?`$filter=" + [uri]::EscapeDataString("name eq '$q'")))
        if ($hits.Count -eq 0) { $hits = @(Get-CrRows ("/v2/odata/company?`$filter=" + [uri]::EscapeDataString("contains(tolower(name),'$($q.ToLowerInvariant())')"))) }
    }
}
catch { Stop-Run "Couldn't look up the CloudRadial company. Check CloudRadial-BaseUrl and the API keys. $($_.Exception.Message)" }
if ($hits.Count -eq 0) { Stop-Run "No CloudRadial company matches $(if ($companyId -gt 0) { "companyId $companyId" } else { "'$companyName'" })." }
if ($hits.Count -gt 1) { Stop-Run "'$companyName' matches $($hits.Count) companies: $((@($hits | Select-Object -First 10 | ForEach-Object { "$(Get-Prop $_ 'name') ($(Get-Prop $_ 'companyId'))" })) -join '; '). Send companyId instead." }
$companyId = [int](Get-Prop $hits[0] 'companyId'); $companyName = [string](Get-Prop $hits[0] 'name' '')

# ---- Microsoft Graph ----
try {
    $tok = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded' -Body @{
        client_id = $s['M365-ClientID']; client_secret = $s['M365-ClientSecret']; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
}
catch { Stop-Run "Couldn't get a Microsoft Graph token for tenant $tenantId. Check M365-ClientID, M365-ClientSecret and that the app is consented in that tenant. $($_.Exception.Message)" }
$gHeaders = @{ Authorization = "Bearer $(Get-Prop $tok 'access_token')"; Accept = 'application/json'; ConsistencyLevel = 'eventual' }

function Invoke-Graph {
    # GET with 429/5xx retry. -All follows @odata.nextLink and returns the value rows.
    param([string]$Uri, [switch]$All)
    $rows = New-Object System.Collections.ArrayList
    $next = $Uri
    while ($next) {
        $attempt = 0
        while ($true) {
            try { $r = Invoke-RestMethod -Method Get -Uri $next -Headers $gHeaders; break }
            catch {
                $attempt++
                $code = 0; $resp = Get-Prop $_.Exception 'Response'; if ($resp) { try { $code = [int]$resp.StatusCode } catch { } }
                if (($code -eq 429 -or $code -ge 500) -and $attempt -lt 5) { Start-Sleep -Seconds ([math]::Min(30, [math]::Pow(2, $attempt))); continue }
                throw
            }
        }
        if (-not $All) { return $r }
        foreach ($v in @(Get-Prop $r 'value' @())) { $null = $rows.Add($v) }
        $next = [string](Get-Prop $r '@odata.nextLink' '')
    }
    return , $rows.ToArray()
}
$G = 'https://graph.microsoft.com/v1.0'
$unavailable = [ordered]@{}   # area -> reason (partner notes only)
function Read-Area { param([string]$Area, [scriptblock]$Call)
    try { return (& $Call) }
    catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { try { $msg = [string](Get-Prop (Get-Prop ($_.ErrorDetails.Message | ConvertFrom-Json) 'error') 'message' $msg) } catch { } }
        $unavailable[$Area] = $msg; Write-Information "Graph: couldn't read $Area. $msg"; return $null
    }
}

$org = Read-Area 'organization' { @(Get-Prop (Invoke-Graph "$G/organization?`$select=displayName") 'value' @()) | Select-Object -First 1 }
$tenantName = [string](Get-Prop $org 'displayName' $tenantId)
$secDefaults = Read-Area 'securityDefaults' { Invoke-Graph "$G/policies/identitySecurityDefaultsEnforcementPolicy" }
$caPolicies = Read-Area 'conditionalAccess' { Invoke-Graph "$G/identity/conditionalAccess/policies" -All }
$regRows = Read-Area 'mfaRegistration' { Invoke-Graph "$G/reports/authenticationMethods/userRegistrationDetails?`$top=999" -All }
$gaMembers = Read-Area 'globalAdmins' { Invoke-Graph "$G/directoryRoles(roleTemplateId='62e90394-69f5-4237-9190-012177145e10')/members?`$select=id,displayName,userPrincipalName" -All }
$riskyUsers = Read-Area 'riskyUsers' { Invoke-Graph "$G/identityProtection/riskyUsers?`$top=500" -All }
$since = $runDate.AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
$detections = Read-Area 'riskDetections' { Invoke-Graph "$G/identityProtection/riskDetections?`$filter=detectedDateTime ge $since&`$top=500" -All }
# Without Entra ID P2, riskDetections can come back empty instead of failing, so trust it only
# when riskyUsers (same licence) could be read.
$noP2 = $unavailable.Contains('riskyUsers') -and ([string]$unavailable['riskyUsers']) -match 'licen[cs]'
if ($noP2 -and -not $unavailable.Contains('riskDetections')) { $unavailable['riskDetections'] = [string]$unavailable['riskyUsers'] }
$score = Read-Area 'secureScore' { @(Get-Prop (Invoke-Graph "$G/security/secureScores?`$top=1") 'value' @()) | Select-Object -First 1 }

# ---- facts ----
function Test-Has { param($list, [string]$v) @(@($list) | Where-Object { [string]$_ -eq $v }).Count -gt 0 }
function Get-Pct { param([int]$n, [int]$d) if ($d -le 0) { return 0 }; [math]::Round(100.0 * $n / $d, 1) }
$sdOn = $null; if ($null -ne $secDefaults) { $sdOn = [bool](Get-Prop $secDefaults 'isEnabled' $false) }
$ca = @(@($caPolicies) | Where-Object { $null -ne $_ } | ForEach-Object {
        $c = Get-Prop $_ 'conditions'; $u = Get-Prop $c 'users'; $g = Get-Prop $_ 'grantControls'
        [pscustomobject]@{
            name = [string](Get-Prop $_ 'displayName' ''); state = [string](Get-Prop $_ 'state' '')
            allUsers = Test-Has (Get-Prop $u 'includeUsers' @()) 'All'
            roles = @(Get-Prop $u 'includeRoles' @()).Count
            allApps = Test-Has (Get-Prop (Get-Prop $c 'applications') 'includeApplications' @()) 'All'
            mfa = (Test-Has (Get-Prop $g 'builtInControls' @()) 'mfa') -or ($null -ne (Get-Prop $g 'authenticationStrength'))
            block = Test-Has (Get-Prop $g 'builtInControls' @()) 'block'
            legacy = (Test-Has (Get-Prop $c 'clientAppTypes' @()) 'exchangeActiveSync') -or (Test-Has (Get-Prop $c 'clientAppTypes' @()) 'other')
            risk = (@(Get-Prop $c 'userRiskLevels' @()).Count + @(Get-Prop $c 'signInRiskLevels' @()).Count) -gt 0
        } })
function Join-Names { param($list) (@(@($list) | ForEach-Object { $_.name }) -join ', ') }
function Find-Ca { param([scriptblock]$Where, [string]$State = 'enabled') , @($ca | Where-Object { $_.state -eq $State } | Where-Object $Where) }
$caNote = if ($unavailable.Contains('conditionalAccess')) { '' } else { "$(@($ca | Where-Object { $_.state -eq 'enabled' }).Count) of $($ca.Count) Conditional Access policies are on." }

$members = @(@($regRows) | Where-Object { $null -ne $_ -and ([string](Get-Prop $_ 'userType' 'member')) -eq 'member' })
$mfaReg = @($members | Where-Object { (Get-Prop $_ 'isMfaRegistered' $false) -eq $true }).Count
$ssprReg = @($members | Where-Object { (Get-Prop $_ 'isSsprRegistered' $false) -eq $true }).Count
$admins = @($members | Where-Object { (Get-Prop $_ 'isAdmin' $false) -eq $true })
$adminMfa = @($admins | Where-Object { (Get-Prop $_ 'isMfaRegistered' $false) -eq $true }).Count
$gaUsers = @(@($gaMembers) | Where-Object { $null -ne $_ -and ([string](Get-Prop $_ '@odata.type' '#microsoft.graph.user')) -eq '#microsoft.graph.user' })
$atRisk = @(@($riskyUsers) | Where-Object { $null -ne $_ -and (Test-Has @('atRisk', 'confirmedCompromised') ([string](Get-Prop $_ 'riskState' ''))) })
$highDet = @(@($detections) | Where-Object { $null -ne $_ -and ([string](Get-Prop $_ 'riskLevel' '')) -eq 'high' })
$ssCur = [double](Get-Prop $score 'currentScore' 0); $ssMax = [double](Get-Prop $score 'maxScore' 0); $ssPct = $(if ($ssMax -gt 0) { [math]::Round(100 * $ssCur / $ssMax, 1) } else { 0 })

# ---- questions ----
# Answer: 2 Compliant, 1 Partially Compliant, 0 N/A, -1 Missing (couldn't check), -2 Not compliant.
$questions = New-Object System.Collections.ArrayList
$PermHint = @{
    securityDefaults = 'Policy.Read.All'; conditionalAccess = 'Policy.Read.All'; mfaRegistration = 'AuditLog.Read.All (and Entra ID P1)'
    globalAdmins = 'RoleManagement.Read.Directory or Directory.Read.All'; riskyUsers = 'IdentityRiskyUser.Read.All (and Entra ID P2)'
    riskDetections = 'IdentityRiskEvent.Read.All (and Entra ID P2)'; secureScore = 'SecurityEvents.Read.All'
}
function Get-QuestionKey {
    # The import file's per-question Update Key, which CloudRadial uses to match a question on re-upload.
    # It is derived from the check's permanent id, so it never changes: keep a check's -Id when you
    # reword or move it, and give a new check a new id.
    param([string]$Id)
    $b = [System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("cloudradial/microsoft-security-assessment/$Id"))
    $b[7] = ($b[7] -band 0x0f) -bor 0x30; $b[8] = ($b[8] -band 0x3f) -bor 0x80
    return ([guid]::new([byte[]]$b)).ToString()
}
function Add-Q {
    param([string]$Category, [int]$Order, [string]$Question, [string]$Explanation, [string]$Evaluation, [int]$Answer, [string]$Notes,
        [string]$Summary, [string]$Remediation, [string]$Reference, [int]$ControlType = 10, [int]$Likelihood = 3, [int]$Risk = 4, [int]$Impact = 20, [string[]]$Areas = @(), [Parameter(Mandatory)][string]$Id)
    $gaps = @($Areas | Where-Object { $unavailable.Contains($_) })
    $partner = ''
    if ($gaps.Count) {
        $Answer = -1
        $Notes = "This couldn't be checked automatically. An administrator should review it in the Microsoft admin centers."
        $partner = (@($gaps | ForEach-Object { if (([string]$unavailable[$_]) -match 'licen[cs]') { "Graph couldn't read $_ because the tenant isn't licensed for it ($($unavailable[$_])). It needs Entra ID P2." } else { "Graph couldn't read $_ ($($unavailable[$_])). The app needs $($PermHint[$_])." } }) -join ' ')
    }
    $null = $questions.Add([ordered]@{
            category = $Category; order = $Order; question = $Question; explanation = $Explanation; evaluation = $Evaluation
            answer = $Answer; notes = $Notes; remediationSummary = $(if ($Answer -ge 2) { '' } else { $Summary }); remediation = $(if ($Answer -ge 2) { '' } else { $Remediation })
            reference = $Reference; controlType = $ControlType; likelihood = $Likelihood; risk = $Risk; riskImpact = $Impact; partnerNotes = $partner
            id = $Id; updateKey = Get-QuestionKey $Id
        })
}
$C1 = '1. Identity and MFA'; $C2 = '2. Privileged access'; $C3 = '3. Identity protection'; $C4 = '4. Security posture'

# 1. MFA enforced for everyone
$mfaAll = Find-Ca { $_.allUsers -and $_.allApps -and $_.mfa }
$mfaSome = Find-Ca { $_.mfa }
$mfaReport = Find-Ca { $_.mfa } -State 'enabledForReportingButNotEnforced'
$a = if ($sdOn -or $mfaAll.Count) { 2 } elseif ($mfaSome.Count -or $mfaReport.Count) { 1 } else { -2 }
$n = if ($sdOn) { 'Security defaults are on, so every user must use MFA.' } elseif ($mfaAll.Count) { "MFA is required for all users by: $(Join-Names $mfaAll). $caNote" } elseif ($mfaSome.Count) { "MFA is required only for some users or apps by: $(Join-Names $mfaSome). $caNote" } elseif ($mfaReport.Count) { "MFA policies exist but are in report-only mode: $(Join-Names $mfaReport). $caNote" } else { "Security defaults are off and no Conditional Access policy requires MFA. $caNote" }
Add-Q $C1 10 'Is multi-factor authentication (MFA) required for all users?' 'Most account takeovers start with a stolen password. MFA stops most of them.' 'Security defaults are on, or an enabled Conditional Access policy requires MFA for All users and All cloud apps.' $a $n.Trim() 'Require MFA for all users.' 'Turn on security defaults, or create a Conditional Access policy that requires MFA for All users and All cloud apps. Exclude only the emergency (break-glass) accounts.' 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-mfa-strength' -Likelihood 4 -Risk 5 -Impact 25 -Areas @('securityDefaults', 'conditionalAccess') -Id 'mfa-all-users'

# 2. Users registered for MFA
$p = Get-Pct $mfaReg $members.Count
$a = if ($members.Count -eq 0) { -1 } elseif ($p -ge 95) { 2 } elseif ($p -ge 80) { 1 } else { -2 }
Add-Q $C1 20 'Have users registered an MFA method?' "Users who haven't registered can't complete MFA, and an attacker with their password could register first." 'At least 95% of member accounts are MFA registered (80% or more is partial).' $a "$mfaReg of $($members.Count) member accounts ($p%) have registered an MFA method." 'Get the remaining users to register for MFA.' 'Turn on the registration campaign (Entra ID > Authentication methods > Registration campaign) and follow up with the users who are still not registered.' 'https://learn.microsoft.com/entra/identity/authentication/how-to-mfa-registration-campaign' -Likelihood 3 -Risk 4 -Impact 20 -Areas @('mfaRegistration') -Id 'mfa-registration'

# 3. SSPR registration
$p = Get-Pct $ssprReg $members.Count
$a = if ($members.Count -eq 0) { -1 } elseif ($p -ge 80) { 2 } elseif ($p -ge 50) { 1 } else { -2 }
Add-Q $C1 30 'Have users registered for self-service password reset?' 'Self-service password reset lets users recover their own accounts safely, which cuts help-desk calls and risky manual resets.' 'At least 80% of member accounts are registered for self-service password reset (50% or more is partial).' $a "$ssprReg of $($members.Count) member accounts ($p%) are registered for self-service password reset." 'Turn on and promote self-service password reset.' 'Turn on self-service password reset for all users and use combined registration so users set up MFA and password reset together.' 'https://learn.microsoft.com/entra/identity/authentication/tutorial-enable-sspr' -ControlType 20 -Likelihood 2 -Risk 2 -Impact 10 -Areas @('mfaRegistration') -Id 'sspr-registration'

# 4. Legacy authentication blocked
$legAll = Find-Ca { $_.legacy -and $_.block -and $_.allUsers }
$legSome = @((Find-Ca { $_.legacy -and $_.block }) + (Find-Ca { $_.legacy -and $_.block } -State 'enabledForReportingButNotEnforced'))
$a = if ($sdOn -or $legAll.Count) { 2 } elseif ($legSome.Count) { 1 } else { -2 }
$n = if ($sdOn) { 'Security defaults are on, which blocks legacy authentication.' } elseif ($legAll.Count) { "Legacy authentication is blocked for all users by: $(Join-Names $legAll)." } elseif ($legSome.Count) { "Legacy authentication is blocked only partly or in report-only mode: $(Join-Names $legSome)." } else { 'No policy blocks legacy authentication.' }
Add-Q $C1 40 'Is legacy authentication blocked?' "Older sign-in methods like IMAP, POP and basic SMTP can't do MFA, so attackers use them to get around it." 'Security defaults are on, or an enabled Conditional Access policy blocks Exchange ActiveSync and other clients for All users.' $a $n 'Block legacy authentication.' 'Create a Conditional Access policy that targets the Exchange ActiveSync and Other clients client apps for All users and blocks access.' 'https://learn.microsoft.com/entra/identity/conditional-access/policy-block-legacy-authentication' -Likelihood 4 -Risk 4 -Impact 20 -Areas @('securityDefaults', 'conditionalAccess') -Id 'legacy-auth-blocked'

# 5. Admins registered for MFA
$p = Get-Pct $adminMfa $admins.Count
$a = if ($admins.Count -eq 0) { -1 } elseif ($adminMfa -eq $admins.Count) { 2 } elseif ($p -ge 80) { 1 } else { -2 }
$n = if ($admins.Count -eq 0) { 'No admin accounts were found in the registration report.' } else { "$adminMfa of $($admins.Count) admin accounts ($p%) have registered an MFA method." }
$unreg = @($admins | Where-Object { (Get-Prop $_ 'isMfaRegistered' $false) -ne $true } | Select-Object -First 10 | ForEach-Object { [string](Get-Prop $_ 'userPrincipalName' '') })
if ($unreg.Count) { $n += " Not registered: $($unreg -join ', ')." }
Add-Q $C2 10 'Have all admin accounts registered an MFA method?' 'Admin accounts can change everything in the tenant, so each one must be protected by MFA.' 'Every account that holds an admin role is MFA registered (80% or more is partial).' $a $n 'Register MFA on every admin account.' 'Have every admin register a phishing-resistant method (FIDO2 key, Windows Hello or passkey). Then require it with an authentication-strength Conditional Access policy.' 'https://learn.microsoft.com/entra/identity/conditional-access/policy-admin-phish-resistant-mfa' -Likelihood 3 -Risk 5 -Impact 25 -Areas @('mfaRegistration') -Id 'admin-mfa-registration'

# 6. MFA required for admin roles
$admPol = Find-Ca { $_.mfa -and ($_.roles -gt 0 -or ($_.allUsers -and $_.allApps)) }
$admRep = Find-Ca { $_.mfa -and $_.roles -gt 0 } -State 'enabledForReportingButNotEnforced'
$a = if ($sdOn -or $admPol.Count) { 2 } elseif ($admRep.Count) { 1 } else { -2 }
$n = if ($sdOn) { 'Security defaults are on, so admins must use MFA.' } elseif ($admPol.Count) { "Admins must use MFA because of: $(Join-Names $admPol)." } elseif ($admRep.Count) { "An admin MFA policy exists but is report-only: $(Join-Names $admRep)." } else { 'No policy requires MFA for admin roles.' }
Add-Q $C2 20 'Does a policy require MFA for admin roles?' "Registering MFA isn't enough. A policy has to require it every time an admin signs in." 'Security defaults are on, or an enabled Conditional Access policy requires MFA for directory roles or for All users.' $a $n 'Require MFA for admin roles.' 'Create a Conditional Access policy that targets the admin directory roles and requires MFA, preferably phishing-resistant authentication strength.' 'https://learn.microsoft.com/entra/identity/conditional-access/policy-old-require-mfa-admin' -Likelihood 3 -Risk 5 -Impact 25 -Areas @('securityDefaults', 'conditionalAccess') -Id 'admin-mfa-policy'

# 7. Global Administrator count
$gc = $gaUsers.Count
$a = if ($gc -ge 2 -and $gc -le 4) { 2 } elseif ($gc -eq 1 -or ($gc -ge 5 -and $gc -le 6)) { 1 } else { -2 }
$names = @($gaUsers | Select-Object -First 10 | ForEach-Object { [string](Get-Prop $_ 'userPrincipalName' (Get-Prop $_ 'displayName' '')) })
Add-Q $C2 30 'Are there between 2 and 4 Global Administrators?' 'Too many Global Administrators widens the attack surface. Only one risks a lockout.' 'The Global Administrator role has 2 to 4 user members (1, 5 or 6 is partial).' $a "The Global Administrator role has $gc user member(s)$(if ($names.Count) { ': ' + ($names -join ', ') })$(if ($gc -gt $names.Count) { " and $($gc - $names.Count) more" })." 'Keep 2 to 4 Global Administrators.' 'Move day-to-day admins to least-privilege roles (for example User Administrator or Exchange Administrator). Keep 2 to 4 Global Administrators, including one emergency access account.' 'https://learn.microsoft.com/entra/identity/role-based-access-control/best-practices' -ControlType 10 -Likelihood 3 -Risk 4 -Impact 20 -Areas @('globalAdmins') -Id 'global-admin-count'

# 8. Risky users
$a = if ($atRisk.Count -eq 0) { 2 } else { -2 }
$n = if ($atRisk.Count -eq 0) { 'No users are currently flagged as at risk.' } else { "$($atRisk.Count) user(s) are flagged as at risk: $((@($atRisk | Select-Object -First 10 | ForEach-Object { [string](Get-Prop $_ 'userPrincipalName' '') })) -join ', ')." }
Add-Q $C3 10 'Are there no users flagged as at risk?' 'Microsoft Entra ID Protection flags accounts that show signs of compromise, such as leaked credentials.' 'No risky users with risk state At risk or Confirmed compromised.' $a $n 'Investigate and fix the users flagged as at risk.' 'For each risky user, confirm whether the account is compromised, reset the password, revoke sessions, then dismiss or confirm the risk in Entra ID Protection.' 'https://learn.microsoft.com/entra/id-protection/howto-identity-protection-investigate-risk' -ControlType 30 -Likelihood 4 -Risk 5 -Impact 25 -Areas @('riskyUsers') -Id 'risky-users'

# 9. High-risk detections, last 30 days
$a = if ($highDet.Count -eq 0) { 2 } else { -2 }
Add-Q $C3 20 'Were there no high-risk sign-in detections in the last 30 days?' 'High-risk detections, such as impossible travel or leaked credentials, often mean an attacker is trying to get in.' 'No risk detections with risk level High detected in the last 30 days.' $a "$($highDet.Count) high-risk detection(s) out of $(@($detections).Count) detection(s) in the last 30 days." 'Review the high-risk detections.' 'Review each high-risk detection in Entra ID Protection, fix the affected accounts, and add a sign-in risk policy so future detections are handled automatically.' 'https://learn.microsoft.com/entra/id-protection/concept-identity-protection-risks' -ControlType 30 -Likelihood 4 -Risk 4 -Impact 20 -Areas @('riskDetections') -Id 'high-risk-detections'

# 10. Risk-based Conditional Access
$rp = Find-Ca { $_.risk }; $rr = Find-Ca { $_.risk } -State 'enabledForReportingButNotEnforced'
$a = if ($rp.Count) { 2 } elseif ($rr.Count) { 1 } else { -2 }
$n = if ($rp.Count) { "Risk-based policies are on: $(Join-Names $rp)." } elseif ($rr.Count) { "Risk-based policies are report-only: $(Join-Names $rr)." } else { 'No Conditional Access policy responds to user or sign-in risk.' }
if ($noP2 -and -not $rp.Count) { $n += ' Risk-based policies need an Entra ID P2 licence, which this tenant does not have.' }
Add-Q $C3 30 'Do Conditional Access policies respond to user and sign-in risk?' 'Risk-based policies automatically require MFA or a password change when Microsoft sees a risky sign-in or user.' 'An enabled Conditional Access policy uses user risk or sign-in risk conditions (Entra ID P2).' $a $n 'Add user-risk and sign-in-risk policies.' 'With Entra ID P2, create Conditional Access policies that require a secure password change for high user risk and MFA for medium or high sign-in risk.' 'https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies' -ControlType 20 -Likelihood 3 -Risk 4 -Impact 15 -Areas @('conditionalAccess') -Id 'risk-based-ca'

# 11. Secure Score
$a = if ($ssMax -le 0) { -1 } elseif ($ssPct -ge 70) { 2 } elseif ($ssPct -ge 50) { 1 } else { -2 }
Add-Q $C4 10 'Is the Microsoft Secure Score at least 70%?' "Secure Score measures how many of Microsoft's recommended security settings the tenant has in place." 'The latest Secure Score is 70% or more of the maximum (50% or more is partial).' $a "Secure Score is $ssCur of $ssMax ($ssPct%)." 'Raise the Secure Score.' 'In Microsoft Defender > Exposure management > Secure Score, work through the recommended actions with the most points first.' 'https://learn.microsoft.com/defender-xdr/microsoft-secure-score' -ControlType 30 -Likelihood 3 -Risk 3 -Impact 15 -Areas @('secureScore') -Id 'secure-score'

# ---- summary ----
$qs = @($questions)
$cnt = [ordered]@{
    compliant = @($qs | Where-Object { $_.answer -eq 2 }).Count; partial = @($qs | Where-Object { $_.answer -eq 1 }).Count
    notCompliant = @($qs | Where-Object { $_.answer -eq -2 }).Count; notChecked = @($qs | Where-Object { $_.answer -eq -1 }).Count
}
$summary = "Automated Microsoft 365 security review of $tenantName on $($runDate.ToString('yyyy-MM-dd')): $($qs.Count) checks - $($cnt.compliant) compliant, $($cnt.partial) partially compliant, $($cnt.notCompliant) not compliant, $($cnt.notChecked) couldn't be checked."
Set-NodeOutput ([ordered]@{
        status = 'success'; mode = $mode; message = $summary
        companyId = $companyId; companyName = $companyName; tenantId = $tenantId; tenantName = $tenantName
        assessmentTitle = $title; runTitle = $runTitle; uploads = $uploads; portalUrl = ([string](Get-Prop $in 'portalUrl' '')).Trim(); summary = $summary; counts = $cnt; unavailable = $unavailable; questions = $qs
    })
