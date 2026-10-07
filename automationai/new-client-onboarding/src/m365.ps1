# === NODE: Microsoft 365 baseline preview ===
# Read-only, in every run. Reads the client's Microsoft 365 tenant and works out the standard security
# groups and Conditional Access policies this MSP would apply, and which of them already exist.
# It never creates a group or a policy (applying them is the next version: see the README).
# Skipped with a note when Microsoft 365 isn't set up on this runner, when include_m365 is false, or when the
# app can't sign in to the client's tenant. A missing Graph permission stops the run with a plain sentence.
# Tenant: the tenant_id input, otherwise the tenant that owns primary_domain. Either way the tenant must
# list primary_domain as a verified domain, so one client's data never lands in another client's onboarding.
$ErrorActionPreference = 'Stop'
function Get-NcoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-NcoState {
    param([string[]]$Need)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-NcoProp $raw 'inputs') -and $null -ne (Get-NcoProp $raw 'output')) { $raw = Get-NcoProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw 'This step expects the output of the step before it. Run the workflow from the start.' } }
    return $st
}
function Get-NcoSecret { param([string[]]$Names) foreach ($n in $Names) { $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue } catch { }; if (-not [string]::IsNullOrWhiteSpace($v)) { return $v } }; return $null }
function Stop-NcoM365 {
    param([string]$Msg)
    $nco['status'] = 'error'; $nco['message'] = $Msg; $nco['internal_note'] = "New client onboarding stopped before changing anything: $Msg"
    Set-NodeOutput $nco
    throw $Msg
}
function Stop-NcoGraph {
    param([string]$What, [string]$Permission, $Err)
    if ($GraphState.LastStatus -eq 403) { Stop-NcoM365 "Can't read the client's $What. The app registration needs the $Permission application permission, with admin consent in the client's tenant (or set include_m365 to false). Nothing was changed." }
    Stop-NcoM365 "Couldn't read the client's $What from Microsoft 365: $($Err.Exception.Message) Nothing was changed."
}

$nco = Read-NcoState @('inputs', 'cloudradial', 'psa')
$opt = $nco['inputs']
$domain = [string](Get-NcoProp $opt 'primary_domain')
$tenantIn = [string](Get-NcoProp $opt 'tenant_id')

# The baseline this MSP applies. Admin roles are Microsoft's "Require MFA for administrators" template roles.
$adminRoles = @(
    @('62e90394-69f5-4237-9190-012177145e10', 'Global Administrator'), @('194ae4cb-b126-40b2-bd5b-6091b380977d', 'Security Administrator'),
    @('f28a1f50-f6e7-4571-818b-6a12f2af6b6c', 'SharePoint Administrator'), @('29232cdf-9323-42fd-ade2-1d097af3e4de', 'Exchange Administrator'),
    @('b1be1c3e-b65d-4f19-8427-f6fa0d97feb9', 'Conditional Access Administrator'), @('729827e3-9c14-49f7-bb1b-9608f156bbb8', 'Helpdesk Administrator'),
    @('b0f54661-2d74-4c50-afa3-1ec803f12efe', 'Billing Administrator'), @('fe930be7-5e62-47db-91af-98c3a49a38b1', 'User Administrator'),
    @('c4e39bd9-1100-46d3-8c65-fb160da0071f', 'Authentication Administrator'), @('9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', 'Application Administrator'),
    @('158c047a-c907-4556-b7ef-446551a6b5f7', 'Cloud Application Administrator'), @('966707d0-3269-4727-9be2-8c3a10f19b9d', 'Password Administrator'),
    @('7be44c8a-adaf-4e2a-84d6-ab2649e08a13', 'Privileged Authentication Administrator'), @('e8611ab8-c189-46e8-94e1-60213ab1f814', 'Privileged Role Administrator'))
$breakGlass = '<id of SG-Break Glass Exclusion>'
$baseGroups = @(
    [ordered]@{ name = 'SG-All Staff'; purpose = 'Every licensed staff member. Used to assign apps, licences and policies to everyone at once.' },
    [ordered]@{ name = 'SG-Admins'; purpose = 'People who hold admin roles. Used to target stricter admin policies and reviews.' },
    [ordered]@{ name = 'SG-Break Glass Exclusion'; purpose = 'Two cloud-only emergency admin accounts. Left out of every Conditional Access policy so nobody is ever locked out.' })
$basePolicies = @(
    [ordered]@{ key = 'admins-mfa'; name = 'CA001 - Require MFA for admins'; plain = 'Anyone holding an admin role must use multi-factor authentication, for every app.'
        definition = [ordered]@{ displayName = 'CA001 - Require MFA for admins'; state = 'enabledForReportingButNotEnforced'
            conditions = [ordered]@{ users = [ordered]@{ includeRoles = @($adminRoles | ForEach-Object { $_[0] }); excludeGroups = @($breakGlass) }; applications = [ordered]@{ includeApplications = @('All') }; clientAppTypes = @('all') }
            grantControls = [ordered]@{ operator = 'OR'; builtInControls = @('mfa') } } },
    [ordered]@{ key = 'all-mfa'; name = 'CA002 - Require MFA for all users'; plain = 'Every user must use multi-factor authentication, for every app.'
        definition = [ordered]@{ displayName = 'CA002 - Require MFA for all users'; state = 'enabledForReportingButNotEnforced'
            conditions = [ordered]@{ users = [ordered]@{ includeUsers = @('All'); excludeGroups = @($breakGlass) }; applications = [ordered]@{ includeApplications = @('All') }; clientAppTypes = @('all') }
            grantControls = [ordered]@{ operator = 'OR'; builtInControls = @('mfa') } } },
    [ordered]@{ key = 'legacy-block'; name = 'CA003 - Block legacy authentication'; plain = 'Old sign-in methods that cannot do multi-factor authentication (such as basic-auth email clients) are blocked.'
        definition = [ordered]@{ displayName = 'CA003 - Block legacy authentication'; state = 'enabledForReportingButNotEnforced'
            conditions = [ordered]@{ users = [ordered]@{ includeUsers = @('All'); excludeGroups = @($breakGlass) }; applications = [ordered]@{ includeApplications = @('All') }; clientAppTypes = @('exchangeActiveSync', 'other') }
            grantControls = [ordered]@{ operator = 'OR'; builtInControls = @('block') } } })

$m365 = [ordered]@{ status = 'skipped'; reason = ''; tenant_id = ''; tenant_name = ''; has_p1 = $null; security_defaults = $null; group_count = 0; policy_count = 0; groups = @(); policies = @(); summary = @(); next_steps = @() }

function Complete-NcoM365 {
    $nco['m365'] = $m365
    if ($m365.status -eq 'skipped') { $nco['warnings'] = @(@($nco['warnings']) + "Microsoft 365 baseline skipped: $($m365.reason)") }
    Set-NodeOutput $nco
}

if (-not [bool](Get-NcoProp $opt 'include_m365')) { $m365.reason = 'include_m365 was false.'; Complete-NcoM365; return }
$clientId = Get-NcoSecret @('M365-ClientId', 'M365-ClientID', 'Entra-ClientID', 'Graph-ClientId')
$clientSecret = Get-NcoSecret @('M365-ClientSecret', 'Entra-ClientSecret', 'Graph-ClientSecret')
if (-not $clientId -or -not $clientSecret) { $m365.reason = 'Microsoft 365 is not set up on this runner (add the M365-ClientId and M365-ClientSecret secrets for a multi-tenant app that the client has consented to).'; Complete-NcoM365; return }

$tenant = $(if ($tenantIn) { $tenantIn } else { $domain })
try { $null = Connect-Graph -TenantId $tenant -ClientId $clientId -ClientSecret $clientSecret }
catch { $m365.reason = "couldn't sign in to the Microsoft 365 tenant for $tenant. The client may not have consented to the app yet. $($_.Exception.Message)"; Complete-NcoM365; return }

# Tenant check: the tenant must own primary_domain.
$org = $null
try { $org = @(Get-NcoProp (Invoke-Graph GET "/organization?`$select=id,displayName,verifiedDomains" -Permission 'Organization.Read.All') 'value') | Select-Object -First 1 }
catch { Stop-NcoGraph 'Microsoft 365 organization details' 'Organization.Read.All' $_ }
$verified = @(@(Get-NcoProp $org 'verifiedDomains') | ForEach-Object { ([string](Get-NcoProp $_ 'name')).ToLowerInvariant() })
$m365.tenant_id = [string](Get-NcoProp $org 'id'); $m365.tenant_name = [string](Get-NcoProp $org 'displayName')
if ($verified -notcontains $domain) {
    $nco['status'] = 'rejected'
    $msg = "Microsoft 365 tenant $($m365.tenant_id) ($($m365.tenant_name)) does not own the domain $domain, so it may belong to a different client. Check tenant_id. Nothing was changed."
    $nco['message'] = $msg; $nco['internal_note'] = "New client onboarding stopped before changing anything: $msg"
    Set-NodeOutput $nco
    throw $msg
}

# Licence: Conditional Access needs Entra ID P1 (included in Microsoft 365 Business Premium, E3 and E5).
$skus = @()
try { $skus = @(Get-NcoProp (Invoke-Graph GET '/subscribedSkus' -Permission 'Organization.Read.All') 'value') }
catch { Stop-NcoGraph 'licences' 'Organization.Read.All' $_ }
$m365.has_p1 = @($skus | Where-Object { [string](Get-NcoProp $_ 'capabilityStatus') -in @('Enabled', 'Warning') } | ForEach-Object { @(Get-NcoProp $_ 'servicePlans') } | Where-Object { [string](Get-NcoProp $_ 'servicePlanName') -in @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -and [string](Get-NcoProp $_ 'provisioningStatus') -ne 'Disabled' }).Count -gt 0

# Security defaults.
try { $m365.security_defaults = [bool](Get-NcoProp (Invoke-Graph GET '/policies/identitySecurityDefaultsEnforcementPolicy' -Permission 'Policy.Read.All') 'isEnabled') }
catch { Stop-NcoGraph 'security defaults setting' 'Policy.Read.All' $_ }

# Groups.
$groups = @()
try { $groups = @(Get-GraphAll "/groups?`$filter=securityEnabled eq true&`$select=id,displayName,groupTypes,mailEnabled&`$top=999" -Permission 'Group.Read.All') }
catch { Stop-NcoGraph 'groups' 'Group.Read.All' $_ }
$m365.group_count = $groups.Count
$m365.groups = @(foreach ($bg in $baseGroups) {
        $hit = @($groups | Where-Object { ([string](Get-NcoProp $_ 'displayName')).Trim() -ieq $bg.name }) | Select-Object -First 1
        [ordered]@{ name = $bg.name; purpose = $bg.purpose; exists = ($null -ne $hit); id = $(if ($hit) { [string](Get-NcoProp $hit 'id') } else { '' }); action = $(if ($hit) { 'Already exists. Would be left as it is.' } else { 'Would be created as a cloud-only security group.' }) }
    })

# Conditional Access policies (only readable with Entra ID P1).
$cas = @()
if ($m365.has_p1) {
    try { $cas = @(Get-GraphAll '/identity/conditionalAccess/policies' -Permission 'Policy.Read.All') }
    catch {
        if ($_.Exception.Message -match '(?i)premium|licen[cs]e') { $m365.has_p1 = $false }
        else { Stop-NcoGraph 'Conditional Access policies' 'Policy.Read.All' $_ }
    }
}
$m365.policy_count = $cas.Count
function Get-NcoList { param($o, [string]$Path) foreach ($n in $Path -split '\.') { $o = Get-NcoProp $o $n; if ($null -eq $o) { return @() } }; return @($o | ForEach-Object { [string]$_ }) }
function Test-NcoCovers {
    param($p, [string]$Key)
    $grant = @(Get-NcoList $p 'grantControls.builtInControls')
    $apps = @(Get-NcoList $p 'conditions.applications.includeApplications')
    $users = @(Get-NcoList $p 'conditions.users.includeUsers')
    $roles = @(Get-NcoList $p 'conditions.users.includeRoles')
    $clients = @(Get-NcoList $p 'conditions.clientAppTypes')
    switch ($Key) {
        'admins-mfa' { return ($grant -contains 'mfa' -and $apps -contains 'All' -and ($users -contains 'All' -or $roles -contains '62e90394-69f5-4237-9190-012177145e10')) }
        'all-mfa' { return ($grant -contains 'mfa' -and $apps -contains 'All' -and $users -contains 'All') }
        'legacy-block' { return ($grant -contains 'block' -and $clients -contains 'other' -and $clients -contains 'exchangeActiveSync') }
    }
    return $false
}
$stateText = @{ enabled = 'on'; disabled = 'off'; enabledForReportingButNotEnforced = 'report-only' }
$m365.policies = @(foreach ($bp in $basePolicies) {
        $same = @($cas | Where-Object { ([string](Get-NcoProp $_ 'displayName')).Trim() -ieq $bp.name }) | Select-Object -First 1
        $cover = @($cas | Where-Object { [string](Get-NcoProp $_ 'state') -ne 'disabled' -and (Test-NcoCovers $_ $bp.key) }) | Select-Object -First 1
        $action = ''
        if (-not $m365.has_p1) { $action = 'Not possible: Conditional Access needs Entra ID P1 (Microsoft 365 Business Premium, E3 or E5).' }
        elseif ($null -ne $same) { $st = [string](Get-NcoProp $same 'state'); $action = "Already exists ($(if ($stateText.ContainsKey($st)) { $stateText[$st] } else { $st })). Would be left as it is." }
        elseif ($null -ne $cover) { $st = [string](Get-NcoProp $cover 'state'); $action = "Already covered by the existing policy '$(Get-NcoProp $cover 'displayName')' ($(if ($stateText.ContainsKey($st)) { $stateText[$st] } else { $st })). Would not be added." }
        else { $action = 'Would be created in report-only mode, excluding SG-Break Glass Exclusion.' }
        [ordered]@{ name = $bp.name; plain = $bp.plain; action = $action; would_create = ($action -like 'Would be created*'); definition = $bp.definition }
    })

# Plain-language summary and next steps.
$newGroups = @($m365.groups | Where-Object { -not $_.exists })
$newPolicies = @($m365.policies | Where-Object { $_.would_create })
$m365.status = 'read'
$sum = @("Microsoft 365 tenant: $($m365.tenant_name) ($($m365.tenant_id)). It has $($m365.group_count) security groups and $($m365.policy_count) Conditional Access policies.")
$sum += $(if ($m365.security_defaults) { 'Security defaults are on, so everyone is already asked for multi-factor authentication.' } else { 'Security defaults are off.' })
$sum += $(if ($m365.has_p1) { 'The tenant has Entra ID P1, so Conditional Access can be used.' } else { 'The tenant has no Entra ID P1 licence, so Conditional Access policies cannot be used.' })
$sum += "Security groups: $(if ($newGroups.Count) { "would create $(@($newGroups | ForEach-Object { $_.name }) -join ', ')" } else { 'all three standard groups already exist' })."
if ($m365.has_p1) { $sum += "Conditional Access: $(if ($newPolicies.Count) { "would create $(@($newPolicies | ForEach-Object { $_.name }) -join ', ') in report-only mode" } else { 'the standard policies are already in place or covered' })." }
$m365.summary = @($sum)
$next = @('Create two cloud-only break-glass admin accounts, store them in the password vault, and add them to SG-Break Glass Exclusion before any policy is switched on.')
if ($m365.has_p1) {
    $next += 'Leave the new policies in report-only mode for at least a week and check the sign-in logs for anyone who would be blocked.'
    if ($m365.security_defaults) { $next += 'Security defaults must be turned off at the moment the Conditional Access policies are switched on, because the two cannot run together.' }
}
elseif (-not $m365.security_defaults) { $next += 'Turn security defaults on, or move the client to Microsoft 365 Business Premium so Conditional Access can be used.' }
$next += 'This workflow does not create any of these yet. Applying the baseline is the next version.'
$m365.next_steps = @($next)
Complete-NcoM365
