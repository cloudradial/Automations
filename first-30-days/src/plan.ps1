# === STEP: Read the client ===
# Edit this file, then run: node first-30-days/src/build.js
# Checks the run input once, for every stage, and stops with every problem listed before anything runs.
# Its output feeds the stages:
#   - the portal setup step reads it directly (company_id plus domain, users, tokens, requestForms, menuTiles)
#   - Secure Score and License Reclamation take single fields through their step parameters
# Run input:
#   company         the AutomationAI company (name, external id or alias) whose Microsoft 365 and CloudRadial
#                   secrets the stages use. Required.
#   company_id      the client's CloudRadial company number. Required.
#   mode            "preview" (default) or "live". Preview plans the assessment and the card without writing them.
#                   Portal setup always waits in the Inbox for approval, and follows the agent's own dry-run setting.
#   days            inactivity threshold for licences, 14 to 365 (default 30)
#   client_visible  show the licence card to the client (default true)
#   domain, companyGroup, users, tokens, requestForms, menuTiles   what portal setup adds (at least one)
function Get-F3Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-F3Text { param($o, [string]$n) $v = Get-F3Prop $o $n; if ($null -eq $v) { return '' }; if (($v -isnot [string]) -and (-not $v.GetType().IsValueType)) { return '' }; $s = ([string]$v).Trim(); if ($s.StartsWith('@')) { return '' }; return $s }
function Stop-F3 {
    param([string]$Why)
    Set-NodeOutput ([ordered]@{ status = 'rejected'; message = $Why; public_note = ''; internal_note = $Why; ticket_id = ''; actions = @(); warnings = @() })
    throw $Why
}

$in = Get-NodeInput
$t = Get-F3Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) {
    $s = $in.Trim()
    if (-not $s) { $in = $null } else { try { $in = $s | ConvertFrom-Json -ErrorAction Stop } catch { Stop-F3 'The run input is not valid JSON. Send an object such as {"company": "Contoso Ltd", "company_id": 7, "users": [...]}.' } }
}
if ($null -eq $in) { Stop-F3 'No run input. Send at least {"company": "Contoso Ltd", "company_id": 7} and something for portal setup, such as users.' }

$problems = New-Object System.Collections.ArrayList
$company = Get-F3Text $in 'company'
if (-not $company) { $null = $problems.Add('company is required: the AutomationAI company whose Microsoft 365 and CloudRadial connection to use.') }

$companyId = 0
$idText = Get-F3Text $in 'company_id'; if (-not $idText) { $idText = Get-F3Text $in 'companyId' }
if (-not $idText) { $null = $problems.Add('company_id is required: the client''s CloudRadial company number.') }
elseif (-not [int]::TryParse($idText, [ref]$companyId) -or $companyId -le 0) { $null = $problems.Add("company_id must be a CloudRadial company number, such as 7 (got '$idText').") }

$mode = (Get-F3Text $in 'mode').ToLowerInvariant(); if (-not $mode) { $mode = 'preview' }
if ($mode -notin @('preview', 'live')) { $null = $problems.Add("mode must be preview or live (got '$mode').") }

$days = 30
$dText = Get-F3Text $in 'days'
if ($dText) { $n = 0; if (-not [int]::TryParse($dText, [ref]$n) -or $n -lt 14 -or $n -gt 365) { $null = $problems.Add("days must be a whole number from 14 to 365 (got '$dText').") } else { $days = $n } }

$clientVisible = $true
$cvText = Get-F3Text $in 'client_visible'; if (-not $cvText) { $cvText = Get-F3Text $in 'clientVisible' }
if ($cvText) {
    if ($cvText -match '^(?i)(true|yes|1)$') { $clientVisible = $true } elseif ($cvText -match '^(?i)(false|no|0)$') { $clientVisible = $false }
    else { $null = $problems.Add("client_visible must be true or false (got '$cvText').") }
}

# Portal setup: pass the fields through as they came; the setup step checks each one in detail.
$setupKeys = @('domain', 'companyGroup', 'users', 'tokens', 'requestForms', 'menuTiles')
$setup = [ordered]@{}
foreach ($k in $setupKeys) {
    $v = Get-F3Prop $in $k
    if ($null -eq $v) { continue }
    if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
    elseif (-not $v.GetType().IsValueType -and @($v).Count -eq 0) { continue }
    $setup[$k] = $v
}
if (-not $setup.Count) { $null = $problems.Add('Portal setup needs at least one of domain, companyGroup, users, tokens, requestForms or menuTiles.') }
foreach ($k in @('companyName', 'accountManager', 'territory', 'psaIdentifier', 'psaKey')) {
    if (Get-F3Text $in $k) { $null = $problems.Add("$k isn't used here: this workflow adds to the existing company company_id and never creates or changes the company itself.") }
}

if ($problems.Count) { Stop-F3 ("First 30 Days wasn't started: " + ($problems -join ' ')) }

$live = ($mode -eq 'live')
$what = @($setup.Keys) -join ', '
$message = "Ready for $company (CloudRadial company $companyId), $(if ($live) { 'live' } else { 'preview' }): portal setup ($what), the Secure Score assessment$(if ($live) { '' } else { ' (plan only)' }), and the licence card$(if ($clientVisible) { ' for the client' } else { ' (internal)' })$(if ($live) { '' } else { ' (preview only)' }), with a $days-day threshold."

$out = [ordered]@{
    status         = 'ok'
    message        = $message
    company        = $company
    company_id     = $companyId
    mode           = $mode
    scoreMode      = $(if ($live) { 'apply' } else { 'plan' })
    preview        = (-not $live)
    days           = $days
    client_visible = $clientVisible
}
foreach ($k in $setup.Keys) { $out[$k] = $setup[$k] }
Set-NodeOutput $out
