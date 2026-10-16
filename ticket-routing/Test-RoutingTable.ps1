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

# ---------- routing table: parse and check (shared by the workflow and Test-RoutingTable.ps1) ----------

# Turns a KB article body into plain text lines. Handles text pasted as
# paragraphs, line breaks, a code block, or an HTML table.
function ConvertFrom-ArticleBody {
    param([string]$Html)
    $t = $Html -replace '\r', ''
    # A cell pasted from Excel can span blank neighbours (colspan="3"): count it as that many columns.
    $t = [regex]::Replace($t, '(?is)<t([dh])([^>]*)\bcolspan\s*=\s*"?(\d+)"?([^>]*)>(.*?)</t[dh]>', [System.Text.RegularExpressions.MatchEvaluator]{
        param($m) "<t$($m.Groups[1].Value)$($m.Groups[2].Value)$($m.Groups[4].Value)>$($m.Groups[5].Value)</t$($m.Groups[1].Value)>" + ('<td></td>' * ([Math]::Max(1, [int]$m.Groups[3].Value) - 1)) })
    # A line break or paragraph inside a cell (an empty pasted cell holds <br>) must not split the row.
    $t = [regex]::Replace($t, '(?is)(<t[dh][^>]*>)(.*?)(</t[dh]>)', [System.Text.RegularExpressions.MatchEvaluator]{
        param($m) $m.Groups[1].Value + (($m.Groups[2].Value -replace '(?i)<br\s*/?>|</(p|div)>', ' ').Trim()) + $m.Groups[3].Value })
    $t = $t -replace '(?i)<br\s*/?>', "`n"
    $t = $t -replace '(?i)</(p|div|tr|li|h[1-6]|pre)>', "`n"
    # Table cells become quoted CSV fields so commas inside a cell survive.
    $t = $t -replace '(?is)<t[dh][^>]*>(.*?)</t[dh]>', '"$1",'
    $t = $t -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace [char]0x00A0, ' ' -replace [char]0xFEFF, ''
    # Smart quotes from the editor break CSV quoting.
    $t = $t -replace "[$([char]0x201C)$([char]0x201D)]", '"' -replace "[$([char]0x2018)$([char]0x2019)]", "'"
    # A table row ends with the trailing comma added above; drop it.
    $t = $t -replace '(?m)",\s*$', '"'
    return @($t -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# Splits lines into [Settings], [Engineers] and [Skills] sections. Lines before
# any marker count as [Skills], so a plain skills CSV works on its own.
# Without markers (a table pasted straight from Excel), a header row starting
# Engineer or Skill starts that section, and a known setting line is a setting.
function Split-RoutingSections {
    param([string[]]$Lines)
    $s = @{ Settings = @(); Engineers = @(); Skills = @() }
    $cur = 'Skills'; $marked = $false
    foreach ($l in $Lines) {
        if ($l -match '^"?\[(Settings|Engineers|Skills)\]"?,?$') { $cur = (Get-Culture).TextInfo.ToTitleCase($Matches[1].ToLowerInvariant()); $marked = $true; continue }
        if (-not $marked) {
            if (Test-SkillBlockLine $l) { $s.Skills += $l; continue }
            if ($l -match '^\s*"?Engineer"?\s*,') { $cur = 'Engineers' }
            elseif ($l -match '^\s*"?Skill"?\s*,') { $cur = 'Skills' }
            elseif ($l -match '^\s*"?(tieBreak|respectMaxOpen|noMatch|fallbackEngineer|minConfidence|liveAssign)"?\s*[:=]') { $s.Settings += $l; continue }
        }
        $s[$cur] += $l
    }
    return $s
}

# Drops titles and notes above a table: the table starts at its header row.
function Select-FromHeader {
    param([string[]]$Lines, [string]$FirstColumn)
    $i = 0
    foreach ($l in $Lines) { if ($l -match ('^\s*"?' + [regex]::Escape($FirstColumn) + '"?\s*,')) { return @($Lines | Select-Object -Skip $i) }; $i++ }
    return @()
}

# The compact skills format (one block per skill, as ConvertTo-SkillDocuments writes it):
#   Skill: <name> / Covers: <description> / Roles: ... / Engineers for <name> / <role>: <name>; <name>
# About a third of the size of the CSV, so a large table fits in KB articles.
function Test-SkillBlockLine { param([string]$l) return ($l -match '^\s*(#\s|Skill:|Covers:|Roles:|Engineers for\s)') }
# True when lines hold a skills table in either form: a CSV with its header, or compact blocks.
function Test-HasSkills { param([string[]]$Lines) return ([bool]@(Select-FromHeader @($Lines) 'Skill').Count -or [bool]@(@($Lines) | Where-Object { $_ -match '^\s*Engineers for\s' }).Count) }
function ConvertFrom-SkillBlocks {
    param([string[]]$Lines)
    $rows = @(); $skill = ''; $desc = ''
    foreach ($l in $Lines) {
        $x = $l.Trim()
        if ($x -match '^Skill:\s*(.+)$') { $skill = $Matches[1].Trim(); $desc = ''; continue }
        if ($x -match '^Covers:\s*(.*)$') { $desc = $Matches[1].Trim(); continue }
        if ($x -notmatch '^Engineers for\s') { continue }
        # Role names can contain " / " (Documentation / Knowledge Base), so take the skill from its Skill: line.
        $rest = $null
        if ($skill -and $x.StartsWith("Engineers for $skill / ")) { $rest = $x.Substring("Engineers for $skill / ".Length) }
        elseif ($x -match '^Engineers for (.+?) / (.+)$') { $skill = $Matches[1].Trim(); $rest = $Matches[2] }
        if ($null -eq $rest) { continue }
        $i = $rest.IndexOf(':'); if ($i -lt 0) { continue }
        $role = $rest.Substring(0, $i).Trim()
        foreach ($n in @($rest.Substring($i + 1) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            $rows += [pscustomobject]@{ Skill = $skill; Role = $role; Engineer = $n; Description = $desc }
        }
    }
    return $rows
}

function Read-RoutingTable {
    param([string[]]$SkillLines, [string[]]$EngineerLines, [string[]]$SettingLines)
    $blockRows = @(ConvertFrom-SkillBlocks @(@($SkillLines) | Where-Object { Test-SkillBlockLine $_ }))
    $SkillLines = @(Select-FromHeader @(@($SkillLines) | Where-Object { -not (Test-SkillBlockLine $_) }) 'Skill')
    $EngineerLines = @(Select-FromHeader @($EngineerLines) 'Engineer')
    $clean = { param($v) $x = ([string]$v).Trim(); if ($x -eq '#N/A') { '' } else { $x } }
    # Names are matched across the two tables, so tidy spacing: "Rivera , Sam" -> "Rivera, Sam".
    $name = { param($v) ((& $clean $v) -replace '\s+,', ',' -replace ',(?=\S)', ', ' -replace '\s{2,}', ' ') }
    $col = { param($r, $n) if ($r.PSObject.Properties[$n]) { & $clean $r.$n } else { '' } }
    $skills = @()
    if ($SkillLines.Count) {
        foreach ($r in @($SkillLines | ConvertFrom-Csv)) {
            $skills += [pscustomobject]@{
                Skill = & $col $r 'Skill'; Role = & $col $r 'Role'; Engineer = & $name (& $col $r 'Engineer'); Description = & $col $r 'Skill Description'
            }
        }
    }
    foreach ($r in $blockRows) { $skills += [pscustomobject]@{ Skill = & $clean $r.Skill; Role = & $clean $r.Role; Engineer = & $name $r.Engineer; Description = & $clean $r.Description } }
    $engineers = @()
    if ($EngineerLines.Count) {
        foreach ($r in @($EngineerLines | ConvertFrom-Csv)) {
            $engineers += [pscustomobject]@{
                Engineer = & $name (& $col $r 'Engineer'); Email = & $col $r 'Email'; PsaUserId = & $col $r 'PSA User Id'; PsaRoleId = & $col $r 'PSA Role Id'
                Active = ((& $col $r 'Active') -notmatch '^(?i)(no|false|0)$'); MaxOpen = & $col $r 'Max Open Tickets'
            }
        }
    }
    $settings = [ordered]@{ tieBreak = 'least-open-tickets'; respectMaxOpen = 'yes'; noMatch = 'leave-unassigned'; fallbackEngineer = ''; minConfidence = '0.7'; liveAssign = 'no' }
    foreach ($l in @($SettingLines)) { if ($l -match '^\s*"?([A-Za-z]+)\s*[:=]\s*(.*?)"?,?$') { $settings[$Matches[1]] = $Matches[2].Trim() } }
    return [pscustomobject]@{ Skills = $skills; Engineers = $engineers; Settings = $settings }
}

# Everything the workflow would trip on. Errors stop the workflow; warnings don't.
function Test-RoutingData {
    param($Table, [string]$Psa = '', [switch]$NoSkills)   # NoSkills: the skills table lives in AutomationAI Knowledge, not here
    $errors = @(); $warnings = @()
    $t = $Table
    if (-not $NoSkills -and -not $t.Skills.Count) { $errors += 'No skills rows were found. The first line must be the header: Skill,Role,Engineer,Skill Description' }
    $missingCols = @($t.Skills | Where-Object { -not $_.Skill -or -not $_.Role -or -not $_.Engineer })
    if ($missingCols.Count) { $errors += "$($missingCols.Count) skills rows are missing a Skill, Role or Engineer." }
    $dupes = @($t.Skills | Group-Object { "$($_.Skill)|$($_.Role)|$($_.Engineer)" } | Where-Object Count -gt 1)
    if ($dupes.Count) { $warnings += "$($dupes.Count) skills rows are duplicated (same skill, role and engineer)." }
    $roleOnly = @($t.Skills | Where-Object { $_.Skill -eq 'Role only' })
    if ($roleOnly.Count) { $warnings += "$($roleOnly.Count) 'Role only' rows have no skill. They are never matched to a ticket; they're kept for reference." }
    $descs = @($t.Skills | Where-Object { $_.Skill -and $_.Skill -ne 'Role only' } | Group-Object Skill | Where-Object { @($_.Group.Description | Where-Object { $_ } | Select-Object -Unique).Count -ne 1 })
    if ($descs.Count) { $warnings += "$($descs.Count) skills have no description, or different descriptions on different rows. The classifier reads one description per skill: $(@($descs.Name | Select-Object -First 5) -join '; ')" }

    $named = @($t.Skills | Where-Object { $_.Engineer } | ForEach-Object { $_.Engineer } | Select-Object -Unique)
    if ($t.Engineers.Count) {
        $known = @($t.Engineers | ForEach-Object { $_.Engineer })
        $unknown = @($named | Where-Object { $known -notcontains $_ })
        if ($unknown.Count) { $errors += "$($unknown.Count) engineers in the skills table aren't in the engineers table, so they can't be assigned: $(@($unknown | Select-Object -First 8) -join '; ')" }
        $noId = @($t.Engineers | Where-Object { -not $_.PsaUserId })
        if ($noId.Count) { $errors += "$($noId.Count) engineers have no PSA User Id: $(@($noId | ForEach-Object { $_.Engineer } | Select-Object -First 8) -join '; ')" }
        if ($Psa -eq 'autotask') { $noRole = @($t.Engineers | Where-Object { -not $_.PsaRoleId }); if ($noRole.Count) { $errors += "Autotask needs a PSA Role Id for each engineer. Missing for $($noRole.Count): $(@($noRole | ForEach-Object { $_.Engineer } | Select-Object -First 8) -join '; ')" } }
        $badMax = @($t.Engineers | Where-Object { $_.MaxOpen -and $_.MaxOpen -notmatch '^\d+$' })
        if ($badMax.Count) { $errors += "Max Open Tickets must be a whole number or blank: $(@($badMax | ForEach-Object { $_.Engineer }) -join '; ')" }
        $dupEng = @($t.Engineers | Group-Object Engineer | Where-Object Count -gt 1)
        if ($dupEng.Count) { $errors += "Engineers listed more than once: $(@($dupEng.Name) -join '; ')" }
    } else { $errors += 'No engineers table was found. Add an [Engineers] section with the header Engineer,Email,PSA User Id,PSA Role Id,Active,Max Open Tickets' }

    $s = $t.Settings
    if (@('least-open-tickets', 'least-recently-assigned', 'listed-order', 'random') -notcontains $s.tieBreak) { $errors += "tieBreak '$($s.tieBreak)' isn't one of: least-open-tickets, least-recently-assigned, listed-order, random." }
    if (@('leave-unassigned', 'assign-fallback', 'recommend-only') -notcontains $s.noMatch) { $errors += "noMatch '$($s.noMatch)' isn't one of: leave-unassigned, assign-fallback, recommend-only." }
    if ($s.noMatch -eq 'assign-fallback') {
        if (-not $s.fallbackEngineer) { $errors += 'noMatch is assign-fallback but fallbackEngineer is empty.' }
        elseif ($t.Engineers.Count -and @($t.Engineers | ForEach-Object { $_.Engineer }) -notcontains (($s.fallbackEngineer -replace '\s+,', ',' -replace ',(?=\S)', ', ').Trim())) { $errors += "fallbackEngineer '$($s.fallbackEngineer)' isn't in the engineers table." }
    }
    if ($s.respectMaxOpen -notmatch '^(?i)(yes|no)$') { $errors += 'respectMaxOpen must be yes or no.' }
    if ($s.liveAssign -notmatch '^(?i)(yes|no)$') { $errors += 'liveAssign must be yes or no.' }
    [double]$mc = 0; if (-not [double]::TryParse([string]$s.minConfidence, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$mc) -or $mc -lt 0 -or $mc -gt 1) { $errors += 'minConfidence must be a number from 0 to 1.' }
    return [pscustomobject]@{ Errors = $errors; Warnings = $warnings }
}

# For TableSource 'knowledge': one small Markdown document per skill, so a single Knowledge search
# hit returns the whole skill (description, roles and every engineer per role) in one chunk.
# Returns an ordered dictionary of file name -> document text, in the table's order.
function ConvertTo-SkillDocuments {
    param($Table)
    $docs = [ordered]@{}
    $used = @{}
    foreach ($g in @($Table.Skills | Where-Object { $_.Skill -and $_.Skill -ne 'Role only' } | Group-Object Skill)) {
        $d = @($g.Group | ForEach-Object { $_.Description } | Where-Object { $_ } | Select-Object -First 1)
        $roles = @($g.Group | ForEach-Object { $_.Role } | Where-Object { $_ } | Select-Object -Unique)
        $lines = @("# $($g.Name)", '', "Skill: $($g.Name)")
        if ($d.Count) { $lines += "Covers: $($d[0])" }
        $lines += "Roles: $($roles -join ', ')"
        $lines += ''
        foreach ($r in $roles) {
            $names = @($g.Group | Where-Object { $_.Role -eq $r -and $_.Engineer } | ForEach-Object { $_.Engineer } | Select-Object -Unique)
            $lines += "Engineers for $($g.Name) / $($r): $($names -join '; ')"
        }
        $base = (($g.Name -replace '[^A-Za-z0-9]+', '-').Trim('-')).ToLowerInvariant()
        if (-not $base) { $base = 'skill' }
        $name = $base; $n = 2; while ($used.ContainsKey($name)) { $name = "$base-$n"; $n++ }
        $used[$name] = $true
        $docs["$name.md"] = ($lines -join "`n") + "`n"
    }
    return $docs
}

# The only part of the table the AI sees: one line per skill with its description and roles.
function Get-ClassifierSkillList {
    param($Table)
    $matchable = @($Table.Skills | Where-Object { $_.Skill -and $_.Skill -ne 'Role only' })
    return (@($matchable | Group-Object Skill | ForEach-Object {
        $d = @($_.Group | ForEach-Object { $_.Description } | Where-Object { $_ } | Select-Object -First 1)
        $roles = @($_.Group | ForEach-Object { $_.Role } | Where-Object { $_ } | Select-Object -Unique)
        "$($_.Name): $(if ($d.Count) { $d[0] } else { '(no description)' }) [roles: $($roles -join ', ')]"
    }) -join "`n")
}

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
