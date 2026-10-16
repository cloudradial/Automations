<#
.SYNOPSIS
  Checks a ticket routing table before you publish it as UCP KB articles.

.DESCRIPTION
  Reads the routing table the same way the Ticket Routing workflow does: from
  plain CSV files, or from a saved KB article body (the HTML the CloudRadial
  editor stores). Reports anything the workflow would trip on.

  The parsing and checking functions below are generated from the workflow's
  own source (src/routing-table.ps1), so this script and the workflow can't drift.

.EXAMPLE
  ./Test-RoutingTable.ps1 -SkillsPath skills.csv -EngineersPath engineers.csv -Psa autotask

.EXAMPLE
  ./Test-RoutingTable.ps1 -ArticleHtmlPath engineers.html,skills.html -Psa autotask

.EXAMPLE
  ./Test-RoutingTable.ps1 -SkillsPath skills.csv -EngineersPath engineers.csv -ExportKnowledgeDir .\knowledge-skills
  Writes one Markdown file per skill for TableSource 'knowledge': upload the folder's
  files to one AutomationAI Knowledge folder and ground the "Pick the skill" node on it.

.EXAMPLE
  ./Test-RoutingTable.ps1 -SkillsPath skills.csv -ExportKnowledgeDir .\test-skills -Placeholders
  The same, with every engineer renamed "Engineer 01", "Engineer 02", ... so real staff
  names never reach a test tenant. Also writes engineers-placeholder.csv to paste into
  the Routing table step (fill in the PSA ids).
#>
[CmdletBinding()]
param(
    [string]$SkillsPath,
    [string]$EngineersPath,
    [string]$SettingsPath,
    [string[]]$ArticleHtmlPath,
    [ValidateSet('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk', '')]
    [string]$Psa = '',
    [string]$ExportKnowledgeDir,
    [string]$ExportArticleDir,
    [int]$MaxArticleChars = 90000,   # KB articles hold about 100,000 characters; this leaves room for editor markup
    [switch]$Placeholders
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#@@ROUTING_TABLE@@

# ---------- load ----------

$skillLines = @(); $engLines = @(); $setLines = @()
if ($ArticleHtmlPath) {
    foreach ($p in $ArticleHtmlPath) {
        $sec = Split-RoutingSections (ConvertFrom-ArticleBody (Get-Content -Raw -LiteralPath $p))
        if (Test-HasSkills @($sec.Skills)) { $skillLines += $sec.Skills }
        $engLines += $sec.Engineers; $setLines += $sec.Settings
    }
}
$readCsv = { param($p) @(Get-Content -LiteralPath $p | ForEach-Object { $_ -replace [char]0xFEFF, '' } | Where-Object { $_.Trim() }) }
if ($SkillsPath) { $skillLines = & $readCsv $SkillsPath }
if ($EngineersPath) { $engLines = & $readCsv $EngineersPath }
if ($SettingsPath) { $setLines = & $readCsv $SettingsPath }
$t = Read-RoutingTable $skillLines $engLines $setLines
if ($Placeholders) {
    # Rename every engineer, in order of first appearance, across both tables.
    $map = [ordered]@{}
    foreach ($n in @(@($t.Skills | ForEach-Object { $_.Engineer }) + @($t.Engineers | ForEach-Object { $_.Engineer }) | Where-Object { $_ })) {
        if (-not $map.Contains($n)) { $map[$n] = 'Engineer {0:D2}' -f ($map.Count + 1) }
    }
    foreach ($r in $t.Skills) { if ($r.Engineer) { $r.Engineer = $map[$r.Engineer] } }
    $t.Engineers = @($map.Keys | ForEach-Object {
        $old = $_; $e = @($t.Engineers | Where-Object { $_.Engineer -eq $old }) | Select-Object -First 1
        $num = ($map[$old] -replace '\D', '')
        [pscustomobject]@{ Engineer = $map[$old]; Email = "engineer$num@example.com"; PsaUserId = ''; PsaRoleId = ''; Active = $(if ($e) { $e.Active } else { $true }); MaxOpen = $(if ($e) { $e.MaxOpen } else { '' }) }
    })
}
$check = Test-RoutingData $t $Psa
if ($ExportKnowledgeDir) {
    $docs = ConvertTo-SkillDocuments $t
    New-Item -ItemType Directory -Force -Path $ExportKnowledgeDir | Out-Null
    foreach ($k in $docs.Keys) { [IO.File]::WriteAllText((Join-Path $ExportKnowledgeDir $k), $docs[$k], [Text.UTF8Encoding]::new($false)) }
    if ($Placeholders) {
        $csv = @('Engineer,Email,PSA User Id,PSA Role Id,Active,Max Open Tickets') + @($t.Engineers | ForEach-Object { "`"$($_.Engineer)`",$($_.Email),,,$(if ($_.Active) { 'Yes' } else { 'No' }),$($_.MaxOpen)" })
        [IO.File]::WriteAllText((Join-Path $ExportKnowledgeDir 'engineers-placeholder.csv'), ($csv -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    }
    "Exported $($docs.Count) skill documents to $ExportKnowledgeDir$(if ($Placeholders) { ', plus engineers-placeholder.csv (not for Knowledge: paste it into the Routing table step)' })."
    ''
}
if ($ExportArticleDir) {
    # The skills in the compact block format, split into numbered KB articles that each stay under
    # MaxArticleChars once the editor wraps every line in <p></p> (counted as 7 extra characters a line).
    $docs = ConvertTo-SkillDocuments $t
    New-Item -ItemType Directory -Force -Path $ExportArticleDir | Out-Null
    $parts = New-Object System.Collections.ArrayList; $cur = New-Object System.Collections.ArrayList; $size = 0
    foreach ($k in $docs.Keys) {
        $lines = @($docs[$k] -split "`n" | Where-Object { $_ -and $_ -notmatch '^#\s' })
        $cost = ($lines | Measure-Object -Property Length -Sum).Sum + 7 * $lines.Count
        if ($cost -gt $MaxArticleChars) { "WARNING: skill '$($lines[0])' alone is $cost characters, over MaxArticleChars." }
        if ($cur.Count -and $size + $cost -gt $MaxArticleChars) { $null = $parts.Add(@($cur)); $cur = New-Object System.Collections.ArrayList; $size = 0 }
        foreach ($l in $lines) { $null = $cur.Add($l) }; $null = $cur.Add(''); $size += $cost
    }
    if ($cur.Count) { $null = $parts.Add(@($cur)) }
    $i = 0
    foreach ($p in $parts) {
        $i++
        [IO.File]::WriteAllText((Join-Path $ExportArticleDir "Ticket Routing - Skills $i.txt"), ((@($p) -join "`n").TrimEnd() + "`n"), [Text.UTF8Encoding]::new($false))
    }
    $eng = @('[Settings]') + @($t.Settings.Keys | ForEach-Object { "$($_): $($t.Settings[$_])" }) + @('', '[Engineers]', 'Engineer,Email,PSA User Id,PSA Role Id,Active,Max Open Tickets') +
        @($t.Engineers | ForEach-Object { "`"$($_.Engineer)`",$($_.Email),$($_.PsaUserId),$($_.PsaRoleId),$(if ($_.Active) { 'Yes' } else { 'No' }),$($_.MaxOpen)" })
    [IO.File]::WriteAllText((Join-Path $ExportArticleDir 'Ticket Routing - Engineers and Settings.txt'), ($eng -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    "Exported $i skills article$(if ($i -ne 1) { 's' }) (each under $MaxArticleChars characters) and the engineers and settings article to $ExportArticleDir."
    "Create each as a KB article titled as its file name, with ':' after 'Ticket Routing' (for example 'Ticket Routing: Skills 1'), and paste the text in."
    ''
}

# ---------- report ----------

$matchable = @($t.Skills | Where-Object { $_.Skill -and $_.Skill -ne 'Role only' })
$roleOnly = @($t.Skills | Where-Object { $_.Skill -eq 'Role only' })
$named = @($t.Skills | Where-Object { $_.Engineer } | ForEach-Object { $_.Engineer } | Select-Object -Unique)
$perSkill = @($matchable | Group-Object Skill | ForEach-Object { $_.Count } | Sort-Object)
$classifierList = Get-ClassifierSkillList $t
$s = $t.Settings
"Skills rows:     $($t.Skills.Count) ($($matchable.Count) matchable, $($roleOnly.Count) role only)"
"Skills:          $(@($matchable | ForEach-Object { $_.Skill } | Select-Object -Unique).Count)"
"Roles:           $(@($t.Skills | ForEach-Object { $_.Role } | Where-Object { $_ } | Select-Object -Unique).Count)"
"Engineers named: $($named.Count)$(if ($t.Engineers.Count) { "; engineers table: $($t.Engineers.Count)" })"
if ($perSkill.Count) { "Engineers per skill: min $($perSkill[0]), median $($perSkill[[int]($perSkill.Count / 2)]), max $($perSkill[-1])" }
"Classifier list: $($classifierList.Length) characters (about $([int]($classifierList.Length / 4)) tokens) sent to the AI per ticket"
"Settings:        $(($s.Keys | ForEach-Object { "$_=$($s[$_])" }) -join '  ')"
''
if ($check.Errors.Count) { 'ERRORS (the workflow would stop and assign nothing):'; $check.Errors | ForEach-Object { " - $_" } } else { 'No errors.' }
if ($check.Warnings.Count) { 'Warnings:'; $check.Warnings | ForEach-Object { " - $_" } }
if ($check.Errors.Count) { exit 1 }
