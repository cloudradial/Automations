# === NODE: Read the setup ===
# Checks the run input and turns it into one request for the CloudRadial UCP Assistant. Fails closed:
# a missing company name, a bad email or domain, or more than the per-run limits stops the run before
# the agent starts, so nothing is half created. Run input (companyName or company_id is required):
#   companyName, domain, companyGroup, accountManager, territory, psaIdentifier, psaKey,
#   company_id   an existing CloudRadial company to add the rest to (for example one New Client
#                Onboarding just created). The company itself is then never created or changed,
#                so accountManager, territory, psaIdentifier and psaKey can't be sent with it.
#   users        [{"firstName","lastName","email"}]          up to 5
#   tokens       [{"token","value"}] or {"Token":"value"}   up to 5
#   requestForms [{"subject","category","description"}]     up to 3
#   menuTiles    [{"name","url","category"}]                 up to 3
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-Text { param($o, $n) $v = Get-Prop $o $n; if ($null -eq $v) { return '' }; return ([string]$v).Trim() }
function Get-Pairs { param($o) if ($o -is [System.Collections.IDictionary]) { return @($o.Keys | ForEach-Object { @{ Name = [string]$_; Value = $o[$_] } }) }; return @($o.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } }) }
function Stop-Setup { param([string]$Msg) Set-NodeOutput ([ordered]@{ status = 'rejected'; message = $Msg; request = ''; companyName = '' }); throw $Msg }

$in = Get-NodeInput
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $s = $in.Trim(); $in = $(if ($s.StartsWith('{')) { $s | ConvertFrom-Json } else { $null }) }
if ($null -eq $in) { Stop-Setup 'No run input. Send at least {"companyName": "Contoso Ltd"}.' }

$limits = @{ users = 5; tokens = 5; requestForms = 3; menuTiles = 3 }
$problems = New-Object System.Collections.ArrayList
$existingId = 0
$idText = Get-Text $in 'company_id'; if (-not $idText) { $idText = Get-Text $in 'companyId' }
if ($idText) { $n = 0; if ([int]::TryParse($idText, [ref]$n) -and $n -gt 0) { $existingId = $n } else { $null = $problems.Add("company_id must be a CloudRadial company number, such as 23 (got '$idText').") } }
$company = [ordered]@{ name = (Get-Text $in 'companyName') }
if (-not $company.name -and -not $idText) { $null = $problems.Add('companyName is required (or company_id, for a company that already exists).') }
elseif ($company.name.Length -gt 100) { $null = $problems.Add('companyName is longer than 100 characters.') }
foreach ($k in @('accountManager', 'territory', 'psaIdentifier')) { $v = Get-Text $in $k; if ($v) { $company[$k] = $v } }
$psaKeyText = Get-Text $in 'psaKey'
if ($psaKeyText) { $pk = [long]0; if ([long]::TryParse($psaKeyText, [ref]$pk) -and $pk -gt 0) { $company.psaKey = $pk } else { $null = $problems.Add("psaKey must be a whole number (got '$psaKeyText').") } }
if ($idText) {
    $fields = @(@('accountManager', 'territory', 'psaIdentifier', 'psaKey') | Where-Object { Get-Text $in $_ })
    if ($fields.Count) { $null = $problems.Add("$($fields -join ', ') only apply when this run creates the company. Leave them out with company_id; this run never changes an existing company.") }
}
$domain = (Get-Text $in 'domain').ToLowerInvariant()
if ($domain -and $domain -notmatch '^(?=.{4,253}$)([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,}$') { $null = $problems.Add("domain '$domain' isn't a domain name (for example contoso.com).") }
$group = Get-Text $in 'companyGroup'

$users = @(); foreach ($u in @(Get-Prop $in 'users')) {
    if ($null -eq $u) { continue }
    $row = [ordered]@{ firstName = (Get-Text $u 'firstName'); lastName = (Get-Text $u 'lastName'); email = (Get-Text $u 'email').ToLowerInvariant() }
    if (-not $row.firstName -or -not $row.lastName -or $row.email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $null = $problems.Add("Each user needs firstName, lastName and a valid email (got '$($row.firstName) $($row.lastName) <$($row.email)>').") }
    else { $users += $row }
}
# Tokens come as a list of {"token","value"} or as one {"TokenName":"value"} map. (A one-item list arrives
# unwrapped, so tell them apart by the "token" property, not by type.)
$tokens = @()
foreach ($x in @(Get-Prop $in 'tokens')) {
    if ($null -eq $x -or $x -is [string]) { continue }
    if ($null -ne (Get-Prop $x 'token')) { $tokens += [ordered]@{ token = (Get-Text $x 'token'); value = (Get-Text $x 'value') } }
    else { foreach ($p in (Get-Pairs $x)) { $tokens += [ordered]@{ token = $p.Name; value = ([string]$p.Value).Trim() } } }
}
foreach ($x in $tokens) {
    $x.token = $x.token.TrimStart('@')
    if ($x.token -notmatch '^[A-Za-z][A-Za-z0-9_]*$' -or -not $x.value) { $null = $problems.Add("Each token needs a name (letters, digits, underscore) and a value (got '$($x.token)').") }
}
$forms = @(); foreach ($f in @(Get-Prop $in 'requestForms')) {
    if ($null -eq $f) { continue }
    $row = [ordered]@{ subject = (Get-Text $f 'subject'); category = (Get-Text $f 'category'); description = (Get-Text $f 'description') }
    if (-not $row.subject -or -not $row.category) { $null = $problems.Add("Each request form needs a subject and a category (got '$($row.subject)').") } else { $forms += $row }
}
$menus = @(); foreach ($m in @(Get-Prop $in 'menuTiles')) {
    if ($null -eq $m) { continue }
    $row = [ordered]@{ name = (Get-Text $m 'name'); url = (Get-Text $m 'url'); category = (Get-Text $m 'category') }
    if (-not $row.name -or $row.url -notmatch '^https?://\S+$' -or -not $row.category) { $null = $problems.Add("Each menu tile needs a name, a category and an http(s) url (got '$($row.name)').") } else { $menus += $row }
}
$counts = [ordered]@{ users = $users.Count; tokens = $tokens.Count; requestForms = $forms.Count; menuTiles = $menus.Count }
foreach ($k in @($limits.Keys)) { if ($counts[$k] -gt $limits[$k]) { $null = $problems.Add("$($counts[$k]) $k is more than the $($limits[$k]) one run can create. Add the rest afterwards with the bulk workflows (Onboard Many Portal Users at Once, Load Your Request Forms into Any Portal).") } }
if ($problems.Count) { Stop-Setup ("The setup wasn't started: " + ($problems -join ' ')) }

$plan = [ordered]@{ company = $company; existingCompanyId = $existingId; domain = $domain; companyGroup = $group; users = @($users); tokens = @($tokens); requestForms = @($forms); menuTiles = @($menus) }
$planJson = ConvertTo-Json -InputObject $plan -Depth 6 -Compress
$label = if ($existingId) { "existing company $existingId" + $(if ($company.name) { " ('$($company.name)')" } else { '' }) } else { "the company '$($company.name)'" }
$parts = @()
if (-not $existingId) { $parts += $label }
if ($domain) { $parts += "default domain $domain" }
if ($group) { $parts += "membership of the company group '$group'" }
foreach ($k in @('users', 'tokens', 'requestForms', 'menuTiles')) { if ($counts[$k]) { $parts += "$($counts[$k]) $k" } }
if ($existingId) {
    if (-not $parts.Count) { Stop-Setup "Nothing to add to company $existingId. Send at least one of domain, companyGroup, users, tokens, requestForms or menuTiles." }
    $request = "Add to the existing CloudRadial company $existingId from this plan. Follow SETTING UP A NEW COMPANY in your instructions with existingCompanyId: never create or change the company itself, create only what the plan lists, and leave out any empty field. Plan (JSON): $planJson"
    $message = "Ready to add to $label" + ': ' + ($parts -join ', ') + '.'
} else {
    $request = "Set up a new CloudRadial company from this plan. Follow SETTING UP A NEW COMPANY in your instructions, create only what the plan lists, and leave out any empty field. Plan (JSON): $planJson"
    $message = "Ready to set up " + ($parts -join ', ') + '.'
}
Set-NodeOutput ([ordered]@{
    status = 'ok'; companyName = $company.name; companyId = $existingId; request = $request; plan = $plan; counts = $counts
    message = $message
})
