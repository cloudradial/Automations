// Assembles scalepad-cloudradial-sync.yml from COMMON.ps1 + the step scripts.
// Shape: Start -> Resolve (match companies by name) -> For Each company (all data phases) -> Report -> End.
const fs = require('fs');
const y = require('js-yaml');
const dir = __dirname;
const read = (f) => fs.readFileSync(dir + '/' + f, 'utf8').replace(/\r\n/g, '\n').trimEnd();
const common = read('COMMON.ps1');
// Function-form replace: PowerShell text contains $' and $& which String.replace treats as patterns.
const withCommon = (raw) => raw.replace('#{{COMMON}}', () => common);

const dataSteps = [
  ['cleanup', 'Clean up duplicate software (opt-in)', '2c-cleanup.ps1'],
  ['devices', 'Devices (workstations, servers, VMs)', '2-devices.ps1'],
  ['assets', 'Other hardware to flexible assets', '2b-assets.ps1'],
  ['saas', 'SaaS subscriptions to flexible assets', '2d-saas.ps1'],
  ['software', 'Installed software', '3-software.ps1'],
  ['assessments', 'Assessments', '4-assessments.ps1'],
  ['roadmap', 'Roadmap and budget', '5-roadmap.ps1'],
  ['insights', 'Insights to Planner cards', '5b-insights.ps1'],
  ['archive', 'Deliverable PDFs to Report Archive', '6-archive.ps1'],
  ['meetings', 'Meeting notes to Report Archive', '6b-meetings.ps1'],
  ['followup', 'Manual follow-up (read-only)', '5c-followup.ps1'],
];
const header = (name) => `# =====================================================================
#  ScalePad to CloudRadial Sync - ${name}
#  Deterministic, paged API-to-API transfer. With no run input it migrates
#  every ScalePad client that matches a CloudRadial company by name; send
#  {"mode":"plan"} to preview, or companyId / companyIds to limit.
#  Secrets (runner Key Vault): ScalePad-ApiUrl, ScalePad-ApiKey,
#  CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey.
#  See the README first.
# =====================================================================
`;

// A data step never fails the company: an error becomes a warning and the context so far carries on.
const wrapStep = (id, raw) => withCommon(raw.replace('#{{COMMON}}', '#{{COMMON}}\ntry {') + `
}
catch {
    $stepErr = $_.Exception.Message
    $ph = $(if (Get-Variable -Name phase -ErrorAction SilentlyContinue) { [string]$phase } else { '${id}' })
    $res = ConvertTo-Dict (Get-P $ctx 'results')
    $res[$ph] = [ordered]@{ ran = $true; failed = $true; error = $stepErr; counts = [ordered]@{ errors = 1 } }
    $ctx.results = $res
    $ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings) + @("The $ph step failed and was skipped: $stepErr"))
    Set-NodeOutput @{ status = 'ok'; message = "The $ph step failed and was skipped: $stepErr"; ctx = $ctx }
}`);

// Embedded phases talk to the loop through their own functions, leaving the platform's untouched.
const embed = (t) => t.replace(/Get-NodeInput/g, 'Get-SyncInput').replace(/Set-NodeOutput/g, 'Set-SyncOutput');
const indent = (s, n) => s.split('\n').map((l) => (l ? ' '.repeat(n) + l : l)).join('\n');

// ---- For Each body: runs every data phase for one company, in order ----
const perCompany = `${header('Migrate one company (all phases)')}# Runs once per matched company (the For Each item, $item). Each phase below is the
# same script as a stand-alone step; a phase reads the context the previous one produced.
$ErrorActionPreference = 'Stop'
# The runner exposes the item as $item (KnowBe4 Training Sync pattern); fall back to the node input.
$SyncItem = $null
foreach ($SyncVar in @('item', 'target')) { $v = Get-Variable -Name $SyncVar -ValueOnly -ErrorAction SilentlyContinue; if ($null -ne $v) { $SyncItem = $v; break } }
if ($null -eq $SyncItem) {
    $SyncIn = $null; try { $SyncIn = Get-NodeInput } catch { }
    if ($SyncIn -is [string] -and $SyncIn.Trim().StartsWith('{')) { $SyncIn = $SyncIn | ConvertFrom-Json }
    foreach ($k in @('item', 'target')) { if ($null -eq $SyncItem -and $null -ne $SyncIn -and $SyncIn.PSObject.Properties[$k]) { $SyncItem = $SyncIn.$k } }
    if ($null -eq $SyncItem -and $null -ne $SyncIn -and $SyncIn.PSObject.Properties['companyId']) { $SyncItem = $SyncIn }
}
if ($SyncItem -is [string] -and $SyncItem.Trim().StartsWith('{')) { $SyncItem = $SyncItem | ConvertFrom-Json }
if ($null -eq $SyncItem) { throw 'The For Each step did not hand this iteration a company.' }
$global:SyncCtx = ($SyncItem | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$global:SyncLog = New-Object System.Collections.ArrayList
function Get-SyncInput { [pscustomobject]@{ ctx = $global:SyncCtx } }
function Set-SyncOutput { param($o) $global:SyncLast = $o }
$SyncPhases = [ordered]@{
${dataSteps.map(([id, name, file]) => `    '${id}' = {
        # ---------------- ${name} ----------------
${indent(embed(wrapStep(id, read(file))), 8)}
    }`).join('\n')}
}
# A phase that fails on a connection error (TLS, DNS, reset, timeout) is run again for this company,
# from the context it started with. Phases match what already exists, so a re-run never duplicates.
$SyncTransient = 'SSL connection could not be established|could not be established|No such host|Name or service not known|actively refused|forcibly closed|connection was closed|error occurred while sending the request|timed out|TaskCanceled|operation was canceled'
foreach ($SyncPhase in $SyncPhases.Keys) {
    if (@($global:SyncCtx.phases) -notcontains $SyncPhase) { continue }   # only the phases this run asked for
    $SyncBefore = ($global:SyncCtx | ConvertTo-Json -Depth 30)
    for ($SyncTry = 1; $SyncTry -le 3; $SyncTry++) {
        $global:SyncLast = $null
        $SyncErr = $null
        try { & $SyncPhases[$SyncPhase] } catch { $SyncErr = $_.Exception.Message }
        if (-not $SyncErr -and $global:SyncLast -is [System.Collections.IDictionary] -and $global:SyncLast.Contains('ctx') -and $global:SyncLast['ctx']) {
            $SyncLastCtx = $global:SyncLast['ctx']
            $r = $(if ($SyncLastCtx -is [System.Collections.IDictionary]) { if ($SyncLastCtx.Contains('results')) { $SyncLastCtx['results'] } } elseif ($SyncLastCtx.PSObject.Properties['results']) { $SyncLastCtx.results })
            # Read with property checks: the runner runs in strict mode, where a missing property throws.
            $pr = $null
            if ($r -is [System.Collections.IDictionary]) { if ($r.Contains($SyncPhase)) { $pr = $r[$SyncPhase] } }
            elseif ($null -ne $r -and $r.PSObject.Properties[$SyncPhase]) { $pr = $r.PSObject.Properties[$SyncPhase].Value }
            $prFailed = $false; $prError = ''
            if ($pr -is [System.Collections.IDictionary]) { if ($pr.Contains('failed')) { $prFailed = [bool]$pr['failed'] }; if ($pr.Contains('error')) { $prError = [string]$pr['error'] } }
            elseif ($null -ne $pr) { if ($pr.PSObject.Properties['failed']) { $prFailed = [bool]$pr.failed }; if ($pr.PSObject.Properties['error']) { $prError = [string]$pr.error } }
            if ($prFailed) { $SyncErr = $prError }
        }
        if (-not $SyncErr -or $SyncErr -notmatch $SyncTransient -or $SyncTry -eq 3) { break }
        $null = $global:SyncLog.Add("The $SyncPhase step hit a connection error ($SyncErr) - running it again for this company (attempt $($SyncTry + 1) of 3).")
        $global:SyncCtx = ($SyncBefore | ConvertFrom-Json)
        Start-Sleep -Seconds (15 * $SyncTry)
    }
    if ($null -eq $global:SyncLast) { $null = $global:SyncLog.Add("$SyncPhase failed: $SyncErr"); continue }
    if ($null -ne $global:SyncLast) {
        if ($global:SyncLast.ctx) { $global:SyncCtx = ($global:SyncLast.ctx | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
        if ($global:SyncLast.message) { $null = $global:SyncLog.Add([string]$global:SyncLast.message) }
    }
}
Set-NodeOutput @{ status = 'ok'; companyId = $global:SyncCtx.companyId; companyName = $global:SyncCtx.companyName; messages = @($global:SyncLog); ctx = $global:SyncCtx }
`;

// ---- Report: one migration report per company (written into its portal in apply), plus a roll-up ----
const report = `${header('Migration report')}$ErrorActionPreference = 'Stop'
function ConvertFrom-MaybeJson { param($v) if ($v -is [string] -and $v.Trim() -match '^[\\[{]') { return ($v | ConvertFrom-Json) }; return $v }
function Get-Field { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-ReportParam { param([string]$n)
    # Parameters may arrive as a variable, as a property of the node input, or via Get-NodeInput -Name
    # (which can also return the whole input bag) - try each and unwrap.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-MaybeJson (Get-NodeInput) } catch { }; $v = Get-Field $all $n }
    if ($null -eq $v) { try { $v = ConvertFrom-MaybeJson (Get-NodeInput -Name $n) } catch { }; $inner = Get-Field $v $n; if ($null -ne $inner) { $v = $inner } }
    return (ConvertFrom-MaybeJson $v)
}
$ReportSync = Get-ReportParam 'sync'
$ReportResolve = Get-ReportParam 'resolve'
# The For Each output carries each iteration's result under results[] and items[] (items[i].output).
$ReportItems = @()
foreach ($k in @('results', 'items')) {
    foreach ($x in @(Get-Field $ReportSync $k)) {
        $x = ConvertFrom-MaybeJson $x
        if ($null -eq $x) { continue }
        $o = Get-Field $x 'output'; if ($null -ne $o) { $x = ConvertFrom-MaybeJson $o }
        if ($null -ne (Get-Field $x 'ctx')) { $ReportItems += $x }
    }
}
if ($ReportItems.Count -eq 0 -and $ReportSync -is [array]) { $ReportItems = @($ReportSync | Where-Object { $null -ne (Get-Field $_ 'ctx') }) }
# the same company can appear under both results[] and items[] - keep one
$seenCompanies = @{}
$ReportItems = @($ReportItems | Where-Object { $cid = [string](Get-Field (Get-Field $_ 'ctx') 'companyId') + '|' + [string](Get-Field (Get-Field $_ 'ctx') 'scalePadClientId'); if ($seenCompanies.ContainsKey($cid)) { $false } else { $seenCompanies[$cid] = $true; $true } })
$failedIterations = @(@(Get-Field $ReportSync 'items') | Where-Object { $e = Get-Field $_ 'error'; $e -and [string]$e -ne '' } | ForEach-Object { [string](Get-Field $_ 'error') })
$global:ReportCtx = $null
function Get-SyncInput { [pscustomobject]@{ ctx = $global:ReportCtx } }
function Set-SyncOutput { param($o) $global:ReportLast = $o }
$ReportCompanies = New-Object System.Collections.ArrayList
foreach ($ReportItem in $ReportItems) {
    $it = $ReportItem
    $global:ReportCtx = $it.ctx
    $global:ReportLast = $null
    try {
        & {
${indent(embed(withCommon(read('7-summary.ps1'))), 12)}
        }
        $null = $ReportCompanies.Add([ordered]@{ companyId = $it.ctx.companyId; companyName = $it.ctx.companyName; status = $global:ReportLast.status; summary = $global:ReportLast.summary; reportLocation = $global:ReportLast.reportLocation; warnings = $global:ReportLast.warnings; notMigrated = $global:ReportLast.notMigrated; checklistItems = @($global:ReportLast.checklist).Count })
    }
    catch { $null = $ReportCompanies.Add([ordered]@{ companyId = $it.ctx.companyId; companyName = $it.ctx.companyName; status = 'report_failed'; summary = "Report failed: $($_.Exception.Message)" }) }
}
$mode = [string](Get-Field $ReportResolve 'mode')
$unmatched = @(Get-Field $ReportResolve 'unmatched' | Where-Object { $_ })
$targets = @(Get-Field $ReportResolve 'targets')
$expected = $targets.Count
# A For Each iteration that threw has no output, so name its company from the resolve step's targets (same order).
$failedCompanies = New-Object System.Collections.ArrayList
$syncItems = @(Get-Field $ReportSync 'items')
for ($i = 0; $i -lt $syncItems.Count; $i++) {
    $si = ConvertFrom-MaybeJson $syncItems[$i]
    $err = [string](Get-Field $si 'error')
    if (-not $err -and [string](Get-Field $si 'status') -ne 'failed') { continue }
    $idx = Get-Field $si 'index'; if ($null -eq $idx) { $idx = $i }
    $t = $(if ([int]$idx -ge 0 -and [int]$idx -lt $expected) { $targets[[int]$idx] } else { $null })
    $null = $failedCompanies.Add([ordered]@{ companyId = Get-Field $t 'companyId'; companyName = [string](Get-Field $t 'companyName'); scalePadClientName = [string](Get-Field $t 'scalePadClientName'); error = $(if ($err) { ($err -split "\`r?\`n")[0].Trim() -replace '^[\\w.]+Exception:\\s*', '' } else { 'failed with no error message' }) })
}
$failedText = (@($failedCompanies | Select-Object -First 10 | ForEach-Object { "$($_.companyName) ($($_.companyId)): $(([string]$_.error).TrimEnd('.'))" })) -join '; '
$retryIds = (@($failedCompanies | ForEach-Object { $_.companyId } | Where-Object { $_ })) -join ','
$allFailed = ($expected -gt 0 -and $ReportCompanies.Count -eq 0)
$msg = if ($allFailed) {
    "None of the $expected matched compan$(if ($expected -eq 1) { 'y was' } else { 'ies were' }) migrated - $(if ($expected -eq 1) { 'it' } else { 'every one' }) failed. $(if ($failedCompanies.Count) { 'First error: ' + $failedCompanies[0].error } elseif ($failedIterations.Count) { 'Error: ' + (($failedIterations[0] -split "\`r?\`n")[0].Trim() -replace '^[\\w.]+Exception:\\s*', '') })"
} elseif ($ReportCompanies.Count -eq 0) {
    "No ScalePad client matched a CloudRadial company by name, so nothing was migrated. $($unmatched.Count) ScalePad clients checked. Rename to match, or send {""companyId"": <id>, ""scalePadClientId"": ""<id>""} to pair one."
} else {
    "$(if ($mode -eq 'plan') { 'Previewed' } else { 'Migrated' }) $($ReportCompanies.Count) compan$(if ($ReportCompanies.Count -eq 1) { 'y' } else { 'ies' }): " + ((@($ReportCompanies | ForEach-Object { "$($_.companyName) - $($_.reportLocation)" })) -join '; ') + $(if ($unmatched.Count) { ". $($unmatched.Count) ScalePad clients had no CloudRadial company with the same name." } else { '.' }) +
        $(if ($failedCompanies.Count) { " $($failedCompanies.Count) compan$(if ($failedCompanies.Count -eq 1) { 'y' } else { 'ies' }) failed and $(if ($failedCompanies.Count -eq 1) { 'was' } else { 'were' }) not migrated: $failedText$(if ($failedCompanies.Count -gt 10) { '; ...' }). Re-run with {""companyIds"": ""$retryIds""} to retry $(if ($failedCompanies.Count -eq 1) { 'it' } else { 'them' })." } else { '' })
}
$status = if ($allFailed) { 'failed' } elseif ($failedCompanies.Count -or @($ReportCompanies | Where-Object { $_.status -ne 'ok' }).Count) { 'completed_with_errors' } else { 'ok' }
Set-NodeOutput @{
    status = $status
    mode = $mode
    message = $msg
    summary = $msg
    companies = @($ReportCompanies)
    failedCompanies = @($failedCompanies)
    unmatchedScalePadClients = $unmatched
    # Areas of ScalePad that have no CloudRadial API (the same for every company), not companies.
    notMigrated = @(@($ReportCompanies | Select-Object -First 1 | ForEach-Object { $_.notMigrated }) | Where-Object { $_ })
}
# Every matched company failed: fail the run too, so History doesn't show it as Succeeded.
if ($allFailed) { throw $msg }
`;

const resolveScript = header('Resolve companies and options') + withCommon(read('1-resolve.ps1')) + '\n';
const activities = [
  { id: 'start', name: 'Start', type: 'start', position: { x: 80, y: 120 }, properties: { webhookEnabled: false } },
  {
    id: 'node-resolve', name: 'Match companies by name', type: 'powershell-script', position: { x: 280, y: 120 },
    // No parameter binding on purpose: an unbound first step receives the run's Trigger input (empty is fine).
    properties: { script: resolveScript, timeoutSeconds: 300, retryCount: 0, parameters: [], aiExtensions: [], testInput: JSON.stringify({ mode: 'plan', companyId: 123 }, null, 2) },
  },
  {
    id: 'node-sync', name: 'Migrate each company', type: 'foreach', position: { x: 500, y: 120 },
    properties: {
      collectionExpression: '{{ nodes.node-resolve.output.targets }}', itemVariableName: 'item', bodyLanguage: 'powershell',
      script: perCompany, mode: 'sequential', maxItems: 500, failurePolicy: 'continue', timeoutSeconds: 1800, parameters: [], aiExtensions: [],
    },
  },
  {
    id: 'node-summary', name: 'Migration report', type: 'powershell-script', position: { x: 720, y: 120 },
    properties: {
      script: report, timeoutSeconds: 600, retryCount: 0, aiExtensions: [],
      parameters: [{ name: 'sync', expression: '{{ nodes.node-sync.output }}' }, { name: 'resolve', expression: '{{ nodes.node-resolve.output }}' }],
    },
  },
  { id: 'end', name: 'End', type: 'end', position: { x: 940, y: 120 } },
];
const ids = ['start', 'node-resolve', 'node-sync', 'node-summary', 'end'];
const connections = ids.slice(1).map((t, i) => ({ source: ids[i], target: t, sourceHandle: null }));

const wf = {
  automationsWorkflow: 1,
  name: 'ScalePad to CloudRadial Sync',
  description: 'Migrates ScalePad Lifecycle Manager data into CloudRadial for every ScalePad client that matches a CloudRadial company by name - no input needed. Per company: devices (workstations, servers, VMs - enrich or create, warranty to expirationDate, purchase date to manufacturedDate), other hardware to flexible assets, installed software, assessments (Excel import built in memory), initiatives and contracts to Planner cards, and deliverable PDFs to the report archive, then a migration report in each portal. Send {"mode":"plan"} to preview without writing, or companyId / companyIds to limit. Re-runs update rather than duplicate. READ THE README BEFORE IMPORTING.',
  definition: { schemaVersion: 1, activities, connections, startActivityId: 'start' },
};
const out = '# CloudRadial AutomationAI - workflow export. Import on Workflows -> Import.\n# The webhook ships disabled; enable it in-portal only if something other than a manual run or Routine triggers it.\n' + y.dump(wf, { lineWidth: -1, noRefs: true });
// Writes ../scalepad-cloudradial-sync.yml (the published export). Pass another folder to write there instead.
const target = process.argv[2] || (dir + '/..');
fs.mkdirSync(target, { recursive: true });
fs.writeFileSync(target + '/scalepad-cloudradial-sync.yml', out);
const back = y.load(out);
const scripted = back.definition.activities.filter((a) => a.properties && a.properties.script);
if (scripted.some((a) => !a.properties.script.includes('function Get-SpAll'))) throw new Error('common block missing');
if ((back.definition.activities[2].properties.script.match(/function Get-SpAll/g) || []).length !== dataSteps.length) throw new Error('per-company body should hold one copy of the helpers per phase');
if (JSON.stringify(back).match(/webhookSecret/)) throw new Error('secret');
for (const a of scripted) fs.writeFileSync(dir + '/built-' + a.id + '.ps1', a.properties.script);
console.log('workflow ok:', scripted.map((a) => a.id).join(', '), '|', out.length, 'bytes');
