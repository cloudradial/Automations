# === STEP: Week-one summary ===
# Edit this file, then run: node first-30-days/src/build.js
# Pulls the stages' results into one plain summary: what was set up, the score, the licence savings,
# and the manual steps left. Reads only the step parameters below and writes nothing anywhere.
#   plan   the Read the client output        setup  the Add portal content output
#   score  the Secure Score step's output    card   the licence card step's output
function Get-F3Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-F3Text { param($o, [string]$n) $v = Get-F3Prop $o $n; if ($null -eq $v) { return '' }; return ([string]$v).Trim() }
function ConvertTo-F3Object {
    param($v)
    if ($v -is [string]) { $s = $v.Trim(); if ($s.StartsWith('{')) { try { return ($s | ConvertFrom-Json -ErrorAction Stop) } catch { } }; return $null }
    return $v
}
function Get-F3List { param($o, [string]$n) return @(@(Get-F3Prop $o $n) | Where-Object { $null -ne $_ -and ([string]$_).Trim() } | ForEach-Object { ([string]$_).Trim() }) }

# The agent step can come back as {"result": "<a sentence> {json}"}. Take the JSON out of the text; if there's
# none, keep the text as the answer.
function Get-F3AgentOutput {
    param($v)
    $o = ConvertTo-F3Object $v
    $r = Get-F3Prop $o 'result'
    if ($null -ne $o -and $r -is [string] -and $null -eq (Get-F3Prop $o 'answer')) {
        $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}')
        if ($a -ge 0 -and $b -gt $a) { try { return ($r.Substring($a, $b - $a + 1) | ConvertFrom-Json -ErrorAction Stop) } catch { } }
        return [pscustomobject]@{ answer = $r.Trim() }
    }
    return $o
}
# Possessive that reads right for names ending in s.
function Get-F3Of { param([string]$n) if ($n -match 's$') { return "$n'" }; return "$n's" }

$in = Get-NodeInput
$plan = ConvertTo-F3Object (Get-F3Prop $in 'plan')
$setup = Get-F3AgentOutput (Get-F3Prop $in 'setup')
$score = ConvertTo-F3Object (Get-F3Prop $in 'score')
$card = ConvertTo-F3Object (Get-F3Prop $in 'card')

$company = Get-F3Text $plan 'company'; if (-not $company) { $company = 'the client' }
$companyId = Get-F3Text $plan 'company_id'
$live = ((Get-F3Text $plan 'mode') -eq 'live')
$warnings = New-Object System.Collections.ArrayList
$manual = New-Object System.Collections.ArrayList
$lines = New-Object System.Collections.ArrayList

# ---- 1. portal setup ----
# The agent sometimes lists what it skipped among its actions; count those as skipped.
$setupAll = @(Get-F3List $setup 'actions')
# No actions list: use the answer's one-line-per-record lines ("created user: ...", "skipped domain: ...").
if (-not $setupAll.Count) {
    $setupAll = @(([string](Get-F3Text $setup 'answer')) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^(?i)(created|would create|skipped|failed|not created)\b' })
}
$setupActions = @($setupAll | Where-Object { $_ -notmatch '^(?i)skip' })
$setupSkipped = @(@(Get-F3List $setup 'skipped') + @($setupAll | Where-Object { $_ -match '^(?i)skip' }))
$setupFailed = @(Get-F3List $setup 'failed')
if ($null -eq $setup) { $null = $warnings.Add('Portal setup returned nothing.'); $null = $lines.Add('Portal setup: no result.') }
else {
    # One line, then one bullet per change. The step's full answer stays in setupAnswer, not the summary.
    $preview = (@($setupActions | Where-Object { $_ -match '^(?i)would ' }).Count -gt 0)
    $count = if (-not $setupActions.Count) { 'no changes' } elseif ($preview) { "$($setupActions.Count) change(s) to make (preview)" } else { "$($setupActions.Count) change(s)" }
    $line = "Portal setup: $count$(if ($setupSkipped.Count) { ", $($setupSkipped.Count) already there" })$(if ($setupFailed.Count) { ", $($setupFailed.Count) failed" })."
    foreach ($a in $setupActions) { $line += "`n    - $a" }
    foreach ($a in $setupFailed) { $line += "`n    - Failed $a" }
    if ($setupFailed.Count) { $null = $warnings.Add("$($setupFailed.Count) portal record(s) couldn't be added. See Portal setup.") }
    foreach ($w in @(Get-F3List $setup 'warnings')) { $null = $warnings.Add($w) }
    $null = $lines.Add($line)
    foreach ($m in @(Get-F3List $setup 'manualSteps')) { if (-not $manual.Contains($m)) { $null = $manual.Add($m) } }
    $setupId = Get-F3Text $setup 'companyId'
    if ($setupId -and $companyId -and $setupId -match '^\d+$' -and $setupId -ne $companyId) { $null = $warnings.Add("Portal setup reported company $setupId, but this run is for company $companyId. Check the setup's actions.") }
}

# ---- 2. Secure Score ----
$scoreStatus = Get-F3Text $score 'status'
$tenantScore = Get-F3Text $score 'tenantScore'
$assessmentId = Get-F3Text $score 'assessmentId'
switch ($scoreStatus) {
    'created' {
        $runId = Get-F3Text $score 'runId'
        $null = $lines.Add("Security: Microsoft Secure Score $tenantScore, in the portal as assessment $assessmentId ($(Get-F3Text $score 'compliant') of $(Get-F3Text $score 'controls') controls compliant)$(if ($runId) { ", with today's run $runId" }).")
        # Older Secure Score steps (before the JSON assessment API) created the assessment without a run.
        if (-not $runId) { $null = $manual.Add("In the portal, open $(Get-F3Of $company) Assessments and choose Run on the new Microsoft Secure Score assessment, so the client sees their score.") }
    }
    'skipped' { $null = $lines.Add("Security: Microsoft Secure Score $tenantScore. Today's run already exists, so nothing was added again.") }
    'plan' { $null = $lines.Add("Security (preview): Microsoft Secure Score $tenantScore. The assessment would be added or refreshed with $(Get-F3Text $score 'controls') controls, plus today's run, $(Get-F3Text $score 'compliant') compliant.") }
    default { $null = $lines.Add("Security: no result$(if ($scoreStatus) { " ($scoreStatus)" }). $(Get-F3Text $score 'message')".Trim()); $null = $warnings.Add('The Secure Score step did not finish with a result.') }
}

# ---- 3. licences ----
$cardStatus = Get-F3Text $card 'status'
$saving = 0.0; $null = [double]::TryParse((Get-F3Text $card 'monthlySaving'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$saving)
$licences = Get-F3Text $card 'licenceCount'; if (-not $licences) { $licences = '0' }
if ($cardStatus -in @('success', 'pending_confirmation')) {
    $null = $lines.Add("Licences: $(Get-F3Text $card 'message')")
    if ([int]$licences -gt 0) { $null = $manual.Add("Review the 'Reclaim unused Microsoft 365 licences' card with $company before removing anything. Nothing was removed.") }
}
else { $null = $lines.Add("Licences: no result$(if ($cardStatus) { " ($cardStatus)" }). $(Get-F3Text $card 'message')".Trim()); $null = $warnings.Add('The licence card step did not finish with a result.') }

$money = '$' + $saving.ToString('N2', [System.Globalization.CultureInfo]::InvariantCulture)
$headline = if ($live) { "Week one for $company is done" } else { "Week one for $company, previewed" }
$headline += ": score $(if ($tenantScore) { $tenantScore } else { 'not read' }), $licences unused licence(s) worth about $money a month."
if ($warnings.Count) { $headline += " $($warnings.Count) thing(s) need a look." }
$text = $headline + "`n`n" + ((@($lines) | ForEach-Object { "- $_" }) -join "`n") + $(if ($manual.Count) { "`n`nStill to do by hand:`n" + ((@($manual) | ForEach-Object { "- $_" }) -join "`n") } else { '' })

Set-NodeOutput ([ordered]@{
        status        = $(if ($warnings.Count) { 'incomplete' } elseif ($live) { 'success' } else { 'pending_confirmation' })
        message       = $headline
        summary       = $text
        public_note   = ''
        internal_note = $text
        ticket_id     = ''
        actions       = @($setupActions + @($(if ($scoreStatus -eq 'created') { "Added Secure Score assessment $assessmentId" })) + @($(if ($cardStatus -eq 'success') { "Planner card $(Get-F3Text $card 'cardAction')" })) | Where-Object { $_ })
        warnings      = @($warnings)
        manualSteps   = @($manual)
        company       = $company
        companyId     = $companyId
        secureScore   = $tenantScore
        assessmentId  = $assessmentId
        licenceCount  = [int]$licences
        monthlySaving = $saving
        setupAnswer   = (Get-F3Text $setup 'answer')
    })
