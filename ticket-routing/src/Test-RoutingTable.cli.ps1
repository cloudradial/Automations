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
#>
[CmdletBinding()]
param(
    [string]$SkillsPath,
    [string]$EngineersPath,
    [string]$SettingsPath,
    [string[]]$ArticleHtmlPath,
    [ValidateSet('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk', '')]
    [string]$Psa = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#@@ROUTING_TABLE@@

# ---------- load ----------

$skillLines = @(); $engLines = @(); $setLines = @()
if ($ArticleHtmlPath) {
    foreach ($p in $ArticleHtmlPath) {
        $sec = Split-RoutingSections (ConvertFrom-ArticleBody (Get-Content -Raw -LiteralPath $p))
        if (@(Select-FromHeader @($sec.Skills) 'Skill').Count) { $skillLines += $sec.Skills }
        $engLines += $sec.Engineers; $setLines += $sec.Settings
    }
}
$readCsv = { param($p) @(Get-Content -LiteralPath $p | ForEach-Object { $_ -replace [char]0xFEFF, '' } | Where-Object { $_.Trim() }) }
if ($SkillsPath) { $skillLines = & $readCsv $SkillsPath }
if ($EngineersPath) { $engLines = & $readCsv $EngineersPath }
if ($SettingsPath) { $setLines = & $readCsv $SettingsPath }
$t = Read-RoutingTable $skillLines $engLines $setLines
$check = Test-RoutingData $t $Psa

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
