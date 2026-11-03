# Strict-mode harness for password-reset-triage.yml. Runs the four steps in order as the runner does
# (child scope via [scriptblock]::Create), passing each step's output to the next as JSON, with Key Vault
# and Graph mocked. A step that throws is a failed run; safety-gate outcomes must finish without one.
# Usage: pwsh -NoProfile -File password-reset-triage/src/test.ps1   (needs js-yaml on NODE_PATH)
param([string]$Yml = (Join-Path $PSScriptRoot '..\password-reset-triage.yml'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$js = "const y=require('js-yaml'),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));const o={};for(const a of w.definition.activities){if(a.properties&&a.properties.script){o[a.id]=a.properties.script}};process.stdout.write(JSON.stringify(o))"
$scripts = node -e $js (Resolve-Path $Yml).Path | ConvertFrom-Json
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

$global:Scenario = ''; $global:NodeIn = $null; $global:NodeOut = $null; $global:Calls = @()
function Get-NodeInput { $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction)
    if ($global:Scenario -eq 'nosecrets') { return $null }
    @{ 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'csec'; 'M365-TenantId' = '00000000-0000-0000-0000-000000000001' }[$Name] }
function Invoke-RestMethod { param($Method = 'Get', $Uri, $Headers, $ContentType, $Body, $ErrorAction)
    $global:Calls += , "$Method $Uri"
    if ($Uri -like '*oauth2/v2.0/token') { return [pscustomobject]@{ access_token = 'tok' } }
    if ($Uri -like '*/v1.0/users[?]*') {
        if ($global:Scenario -eq 'lookuperror') { throw 'Graph returned 500' }
        if ($global:Scenario -eq 'notfound') { return [pscustomobject]@{ value = @() } }
        $u = [pscustomobject]@{ id = 'u1'; displayName = 'Alex Wilber'; userPrincipalName = 'alex@contoso.example'; mail = 'alex@contoso.example'; accountEnabled = ($global:Scenario -ne 'disabled'); userType = $(if ($global:Scenario -eq 'guest') { 'Guest' } else { 'Member' }) }
        return [pscustomobject]@{ value = @($u) } }
    if ($Uri -like '*/memberOf*') {
        if ($global:Scenario -eq 'privileged') { return [pscustomobject]@{ value = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.directoryRole'; id = 'r1'; displayName = 'Global Administrator' }) } }
        return [pscustomobject]@{ value = @() } }
    if ($Method -in 'Patch', 'Post') { return [pscustomobject]@{} }
    throw "Unmocked $Method $Uri"
}

function Invoke-Run { param($Ticket)
    $global:Calls = @(); $global:NodeIn = $Ticket; $threw = $null
    foreach ($id in 'node-1', 'node-2', 'node-3', 'node-4') {
        $global:NodeOut = $null
        try { & ([scriptblock]::Create($scripts.$id)) } catch { $threw = "$id : $($_.Exception.Message)"; break }
        $global:NodeIn = $global:NodeOut | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    }
    [pscustomobject]@{ Threw = $threw; Out = $global:NodeIn; Patched = @($global:Calls | Where-Object { $_ -like 'Patch *' }).Count }
}
function Ticket { param($Target = 'alex@contoso.example', $By = 'alex@contoso.example')
    $t = [ordered]@{ id = 29410; ticketNumber = 'T20260614.0007'; contactID = 8841; contactEmail = $Target; companyTenantId = '' }
    if ($By) { $t['submittedByUPN'] = $By }
    [pscustomobject]$t }

$cases = @(
    @{ Name = 'self-request resets'; Scenario = 'self'; Ticket = (Ticket); Status = 'complete'; Patch = 1 }
    @{ Name = 'other requester held for confirmation'; Scenario = 'self'; Ticket = (Ticket -By 'megan@contoso.example'); Status = 'pending_confirmation'; Patch = 0 }
    @{ Name = 'target not found ends incomplete'; Scenario = 'notfound'; Ticket = (Ticket); Status = 'incomplete'; Patch = 0; Note = 'No Microsoft 365 account*' }
    @{ Name = 'guest ends incomplete'; Scenario = 'guest'; Ticket = (Ticket); Status = 'incomplete'; Patch = 0; Note = '*guest*' }
    @{ Name = 'disabled ends incomplete'; Scenario = 'disabled'; Ticket = (Ticket); Status = 'incomplete'; Patch = 0; Note = '*disabled*' }
    @{ Name = 'privileged role ends incomplete'; Scenario = 'privileged'; Ticket = (Ticket); Status = 'incomplete'; Patch = 0; Note = '*privileged role*' }
    @{ Name = 'no requester ends incomplete'; Scenario = 'self'; Ticket = (Ticket -By ''); Status = 'incomplete'; Patch = 0; Note = '*no authenticated requester*' }
)
foreach ($c in $cases) {
    $global:Scenario = $c.Scenario
    $r = Invoke-Run $c.Ticket
    $ok = (-not $r.Threw) -and $r.Out.status -eq $c.Status -and $r.Patched -eq $c.Patch
    if ($ok -and $c.Contains('Note')) { $ok = [string]$r.Out.internal_note -like $c.Note }
    $detail = if ($r.Threw) { "threw: $($r.Threw)" } else { "status=$($r.Out.status) patched=$($r.Patched) note=$($r.Out.internal_note)" }
    Check $c.Name $ok $detail
}

# Setup and API errors must still fail the run.
foreach ($s in 'nosecrets', 'lookuperror') {
    $global:Scenario = $s
    $r = Invoke-Run (Ticket)
    Check "$s fails the run" ([bool]$r.Threw -and $r.Patched -eq 0) "threw=$($r.Threw)"
}

if ($fail) { Write-Host "$fail check(s) failed"; exit 1 } else { Write-Host 'All checks passed' }
