# ---------- routing table: parse and check (shared by the workflow and Test-RoutingTable.ps1) ----------

# Plain text from a fragment of HTML: tags stripped, entities decoded, smart quotes and
# non-breaking spaces made plain (smart quotes from the editor break CSV quoting).
function ConvertTo-PlainText {
    param([string]$Html)
    $t = [System.Net.WebUtility]::HtmlDecode(($Html -replace '<[^>]+>', ''))
    $t = $t -replace [char]0x00A0, ' ' -replace [char]0xFEFF, ''
    return ($t -replace "[$([char]0x201C)$([char]0x201D)]", '"' -replace "[$([char]0x2018)$([char]0x2019)]", "'")
}

# One HTML table as CSV lines. Cells merged across (colspan) or down (rowspan), as Excel pastes
# merged cells, are filled in so every row keeps its columns: a merged Skill cell repeats on
# each row it covers. A line break inside a cell becomes a space. Every field is quoted, with
# its own quotes doubled.
function ConvertFrom-HtmlTable {
    param([string]$TableHtml)
    $lines = @()
    $carry = @{}   # column -> @{ Text; Left } for cells still spanning down
    foreach ($tr in [regex]::Matches($TableHtml, '(?is)<tr\b[^>]*>(.*?)</tr>')) {
        $cells = @(); $col = 0
        foreach ($td in [regex]::Matches($tr.Groups[1].Value, '(?is)<t[dh]\b([^>]*)>(.*?)</t[dh]>')) {
            while ($carry.ContainsKey($col)) { $cells += $carry[$col].Text; $carry[$col].Left--; if ($carry[$col].Left -le 0) { $carry.Remove($col) }; $col++ }
            $attrs = $td.Groups[1].Value
            $text = (ConvertTo-PlainText ($td.Groups[2].Value -replace '(?i)<br\s*/?>|</(p|div|li)>', ' ')) -replace '\s+', ' '
            $text = $text.Trim()
            $across = 1; if ($attrs -match '(?i)\bcolspan\s*=\s*"?(\d+)') { $across = [Math]::Max(1, [int]$Matches[1]) }
            $down = 1; if ($attrs -match '(?i)\browspan\s*=\s*"?(\d+)') { $down = [Math]::Max(1, [int]$Matches[1]) }
            for ($k = 0; $k -lt $across; $k++) {
                # Merged across: Excel puts the text in the first column and leaves the rest blank.
                $v = if ($k -eq 0) { $text } else { '' }
                $cells += $v
                if ($down -gt 1) { $carry[$col] = @{ Text = $v; Left = $down - 1 } }
                $col++
            }
        }
        while ($carry.ContainsKey($col)) { $cells += $carry[$col].Text; $carry[$col].Left--; if ($carry[$col].Left -le 0) { $carry.Remove($col) }; $col++ }
        if (@($cells | Where-Object { $_ -ne '' }).Count) { $lines += (@($cells | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ',') }
    }
    return $lines
}

# Turns a KB article body into plain text lines. Handles text pasted as
# paragraphs, line breaks, a code block, or an HTML table.
function ConvertFrom-ArticleBody {
    param([string]$Html)
    $t = $Html -replace '\r', ''
    # Tables first, so merged cells and line breaks inside cells are handled per cell.
    # The CSV lines are HTML-encoded here and decoded with the rest of the text below.
    $t = [regex]::Replace($t, '(?is)<table\b.*?</table>', [System.Text.RegularExpressions.MatchEvaluator]{
        param($m) "`n" + ((@(ConvertFrom-HtmlTable $m.Value) | ForEach-Object { [System.Net.WebUtility]::HtmlEncode($_) }) -join "`n") + "`n" })
    $t = $t -replace '(?i)<br\s*/?>', "`n"
    $t = $t -replace '(?i)</(p|div|li|h[1-6]|pre)>', "`n"
    $t = ConvertTo-PlainText $t
    return @($t -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# CSV lines put back together where a quoted field held a line break (Alt+Enter in an Excel
# cell), so ConvertFrom-Csv sees one record per row. A record is complete when its quotes balance.
function Join-CsvRecords {
    param([string[]]$Lines)
    $out = @(); $buf = $null
    foreach ($l in @($Lines)) {
        $buf = if ($null -eq $buf) { $l } else { "$buf $l" }
        if ((([regex]::Matches($buf, '"')).Count % 2) -eq 0) { $out += $buf; $buf = $null }
    }
    if ($null -ne $buf) { $out += $buf }
    return $out
}

# Engineer names are matched across the tables and the classifier's answer, so tidy them one way
# everywhere: "Rivera , Sam" -> "Rivera, Sam"; "#N/A" (an Excel lookup miss) counts as empty.
function ConvertTo-EngineerName {
    param($Value)
    $x = ([string]$Value).Trim()
    if ($x -eq '#N/A') { return '' }
    return ($x -replace '\s+,', ',' -replace ',(?=\S)', ', ' -replace '\s{2,}', ' ')
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
    $SkillLines = @(Join-CsvRecords @(Select-FromHeader @(@($SkillLines) | Where-Object { -not (Test-SkillBlockLine $_) }) 'Skill'))
    $EngineerLines = @(Join-CsvRecords @(Select-FromHeader @($EngineerLines) 'Engineer'))
    $clean = { param($v) $x = ([string]$v).Trim(); if ($x -eq '#N/A') { '' } else { $x } }
    $name = { param($v) ConvertTo-EngineerName $v }
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
        elseif ($t.Engineers.Count -and @($t.Engineers | ForEach-Object { $_.Engineer }) -notcontains (ConvertTo-EngineerName $s.fallbackEngineer)) { $errors += "fallbackEngineer '$($s.fallbackEngineer)' isn't in the engineers table." }
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
