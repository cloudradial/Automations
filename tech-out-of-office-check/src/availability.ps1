# ---------- src/availability.ps1: is a ConnectWise member out right now? ----------
# Reads the two places a dispatcher marks a technician as out in ConnectWise PSA:
#   1. The In/Out Board (GET /system/inOutBoards). An entry whose Date Back is still ahead, and whose In/Out type
#      isn't one of the "in" types (OOO-InTypes), means the member is out until then.
#   2. Schedule entries (GET /schedule/entries). An entry for the member that covers right now, whose schedule type
#      or entry name matches one of the out-of-office names (OOO-ScheduleTypes), means the member is out until it ends.
# Unverified against a live ConnectWise: whether an "In Office" board record keeps a future Date Back (the type check
# covers it either way), and the schedule type name each Partner uses for out-of-office time (a setting).
# Needs _shared/psa.ps1 (Invoke-Psa, Get-PsaFirst, ConvertTo-PsaDate, Format-PsaDate, ConvertTo-PsaQuery).

$OooDefaults = @{
    InTypes       = 'In Office, In'
    ScheduleTypes = 'Out of Office, PTO, Vacation, Holiday, Sick, Wellness'
}

# A setting: the input value when it's sent, else the runner secret, else the default.
function Get-OooSetting { param([string]$InputValue, [string]$Secret, [string]$Default = '') if ($InputValue) { return $InputValue }; $s = [string](Get-PsaSecret $Secret); if ($s.Trim()) { return $s.Trim() }; return $Default }

# The list of names, lowercased and trimmed.
function Get-OooNames { param([string]$Value) return @(($Value -split '[,;\r\n]+') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) }

# A UTC time shown in the dispatcher's time zone, for example "Thu 10/15 12:00 AM Central Daylight Time".
# $TimeZone is an IANA (America/Chicago) or Windows (Central Standard Time) id; blank or unknown shows UTC.
function Format-OooTime {
    param($When, [string]$TimeZone = '', [switch]$Short)
    $d = ConvertTo-PsaDate $When
    if ($null -eq $d) { return 'an unknown time' }
    $tz = $null
    if ($TimeZone) { try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone.Trim()) } catch { $tz = $null } }
    $ci = [Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $tz) { return $d.ToString('ddd M/d h:mm tt', $ci) + ' UTC' }
    $local = [TimeZoneInfo]::ConvertTimeFromUtc($d, $tz)
    $label = if ($tz.IsDaylightSavingTime($local)) { $tz.DaylightName } else { $tz.StandardName }
    # -Short: US zones as PDT, CST and so on; other zones keep their full name.
    if ($Short -and $label -match '^(Pacific|Mountain|Central|Eastern|Alaskan|Hawaiian)( Daylight| Standard) Time$') { $label = ($label -split ' ' | ForEach-Object { $_.Substring(0, 1) }) -join '' }
    return $local.ToString('ddd M/d h:mm tt', $ci) + " $label"
}
# $true when the time zone id is one this runner knows.
function Test-OooTimeZone { param([string]$TimeZone) if (-not $TimeZone) { return $true }; try { $null = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone.Trim()); return $true } catch { return $false } }

# ConnectWise conditions date literal: [2026-10-13T21:00:00Z]
function Format-OooCwDate { param([datetime]$When) return '[' + $When.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) + ']' }

# The identifier for a member record id (Member #). Throws a plain sentence when there is no such member.
function Resolve-OooMemberId {
    param([string]$Id)
    $m = $null
    try { $m = Invoke-Psa GET "/system/members/$Id" } catch { if ([string]$_.Exception.Message -match '\(HTTP 404\)') { throw "ConnectWise has no member #$Id." }; throw }
    $ident = [string](Get-PsaProp $m 'identifier')
    if (-not $ident) { throw "ConnectWise member #$Id has no identifier." }
    return $ident
}

# Members named on the ticket: the owner, the resources list, and any extra identifiers passed in.
# Returns identifiers (lowercase-insensitive unique, original spelling kept).
function Get-OooTicketMembers {
    param($Ticket, [string[]]$Extra = @())
    $list = New-Object System.Collections.ArrayList
    $seen = @{}
    # A number is a ConnectWise member record id (Member #), which is looked up and turned into its identifier.
    $addOne = { param([string]$m) $m = ([string]$m).Trim(); if (-not $m) { return }; if ($m -match '^\d+$') { $m = Resolve-OooMemberId $m }; if (-not $m) { return }; $k = $m.ToLowerInvariant(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $null = $list.Add($m) } }
    & $addOne ([string](Get-PsaPath $Ticket 'owner.identifier'))
    foreach ($r in @(([string](Get-PsaProp $Ticket 'resources')) -split '[,;\s]+')) { & $addOne $r }
    foreach ($e in @($Extra)) { foreach ($r in @(([string]$e) -split '[,;\s]+')) { & $addOne $r } }
    return @($list)
}

# Whether one member is out at $Now. Returns @{ identifier; out; reasons; back } where back is the latest
# time any matching record says they return ('' when unknown).
function Get-OooMemberStatus {
    param([string]$Identifier, [datetime]$Now, [string[]]$InTypes, [string[]]$ScheduleTypes, [string]$TimeZone = '')
    $reasons = New-Object System.Collections.ArrayList
    $items = New-Object System.Collections.ArrayList   # @{ what; where; until } for the dispatcher email
    $seen = New-Object System.Collections.ArrayList   # every record read and why it counted or not, for the run output
    $back = $null
    $who = 'member/identifier="' + $Identifier.Replace('"', '') + '"'

    # 1. In/Out Board
    $boardQ = ConvertTo-PsaQuery $who
    $board = @(Invoke-Psa GET "/system/inOutBoards?conditions=$boardQ&orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=25" | Where-Object { $null -ne $_ })
    foreach ($b in $board) {
        $type = [string](Get-PsaFirst $b @('inOutType.name', 'inOutType.description'))
        $rawBack = [string](Get-PsaProp $b 'dateBack')
        $db = ConvertTo-PsaDate (Get-PsaProp $b 'dateBack')
        $desc = "In/Out Board record $(Get-PsaProp $b 'id'): type '$type', dateBack '$rawBack'"
        if ($type -and ($InTypes -contains $type.Trim().ToLowerInvariant())) { $null = $seen.Add("$desc. Counted as in: '$type' is an in type."); continue }
        if ($null -eq $db) { $null = $seen.Add("$desc. Not counted: no Date Back."); continue }
        if ($db -le $Now) { $null = $seen.Add("$desc. Not counted: Date Back is not after $(Format-PsaDate $Now)."); continue }
        $null = $seen.Add("$desc. Counted as out.")
        $label = if ($type) { $type } else { 'Out' }
        $info = [string](Get-PsaProp $b 'additionalInfo')
        $null = $reasons.Add("In/Out Board: $label until $(Format-OooTime $db $TimeZone)$(if ($info) { " ($info)" })")
        $null = $items.Add([ordered]@{ what = "$label$(if ($info) { ": $info" })"; where = 'In/Out Board'; until = (Format-OooTime $db $TimeZone -Short) })
        if ($null -eq $back -or $db -gt $back) { $back = $db }
    }

    # 2. Schedule entries that cover right now
    $nowLit = Format-OooCwDate $Now
    $schedQ = ConvertTo-PsaQuery "$who and dateStart<=$nowLit and dateEnd>$nowLit"
    $entries = @(Invoke-Psa GET "/schedule/entries?conditions=$schedQ&pageSize=100" | Where-Object { $null -ne $_ })
    foreach ($e in $entries) {
        $type = [string](Get-PsaFirst $e @('type.name', 'type.identifier'))
        $name = [string](Get-PsaProp $e 'name')
        # An Activity booked on a member's calendar becomes a schedule entry of type 'C' named after the activity's
        # summary. Its activity type (for example a Partner's own "Out of Office" type) is read too when the API
        # member may read Activities; without that permission the summary alone is matched.
        $actType = ''
        if ([string](Get-PsaPath $e 'type.identifier') -eq 'C' -and -not (Test-PsaBlank (Get-PsaProp $e 'objectId'))) {
            try { $actType = [string](Get-PsaPath (Invoke-Psa GET "/sales/activities/$(Get-PsaProp $e 'objectId')") 'type.name') } catch { $actType = '' }
            if ($actType) { $type = "Activity: $actType" }
        }
        $hay = "$type`n$name".ToLowerInvariant()
        $hit = $null
        foreach ($t in $ScheduleTypes) { if ($hay.Contains($t)) { $hit = $t; break } }
        if (-not $hit) { $null = $seen.Add("Schedule entry $(Get-PsaProp $e 'id'): type '$type', name '$name'. Not counted: not an out-of-office type."); continue }
        $null = $seen.Add("Schedule entry $(Get-PsaProp $e 'id'): type '$type', name '$name'. Counted as out.")
        $end = ConvertTo-PsaDate (Get-PsaProp $e 'dateEnd')
        $label = if ($type) { $type } else { $name }
        $null = $reasons.Add("Schedule: $label$(if ($name -and $name -ne $label) { " '$name'" }) until $(Format-OooTime $end $TimeZone)")
        $kind = ([string]$type) -replace '^Activity: ', ''
        $null = $items.Add([ordered]@{ what = $(if ($name) { $name } else { $label }); where = $(if ($kind -and $kind -ne $name) { "Schedule, $kind" } else { 'Schedule' }); until = (Format-OooTime $end $TimeZone -Short) })
        if ($null -ne $end -and ($null -eq $back -or $end -gt $back)) { $back = $end }
    }
    if (-not $board.Count) { $null = $seen.Add('In/Out Board: no records for this member.') }
    if (-not $entries.Count) {
        $null = $seen.Add('Schedule: no entries covering now.')
        # Diagnostics only (never counted): what the member has within 24 hours either side, as schedule entries
        # and as calendar activities, so a near miss or the wrong entry kind shows up in the run output.
        $from = Format-OooCwDate $Now.AddHours(-24); $to = Format-OooCwDate $Now.AddHours(24)
        try {
            $near = @(Invoke-Psa GET "/schedule/entries?conditions=$(ConvertTo-PsaQuery "$who and dateStart<$to and dateEnd>$from")&pageSize=25" | Where-Object { $null -ne $_ })
            foreach ($e in $near) { $null = $seen.Add("Nearby schedule entry $(Get-PsaProp $e 'id') (not covering now): type '$(Get-PsaFirst $e @('type.name', 'type.identifier'))', name '$(Get-PsaProp $e 'name')', $(Format-PsaDate (Get-PsaProp $e 'dateStart')) to $(Format-PsaDate (Get-PsaProp $e 'dateEnd')).") }
            if (-not $near.Count) { $null = $seen.Add('Schedule: no entries within 24 hours of now either.') }
        } catch { $null = $seen.Add("Schedule: the nearby check failed: $($_.Exception.Message)") }
        try {
            $actWho = 'assignTo/identifier="' + $Identifier.Replace('"', '') + '"'
            $acts = @(Invoke-Psa GET "/sales/activities?conditions=$(ConvertTo-PsaQuery "$actWho and dateStart<$to and dateEnd>$from")&pageSize=25" | Where-Object { $null -ne $_ })
            foreach ($x in $acts) { $null = $seen.Add("Activity $(Get-PsaProp $x 'id') (activities are not checked): type '$(Get-PsaPath $x 'type.name')', name '$(Get-PsaProp $x 'name')', $(Format-PsaDate (Get-PsaProp $x 'dateStart')) to $(Format-PsaDate (Get-PsaProp $x 'dateEnd')).") }
        } catch { $null = $seen.Add("Activities: the check failed: $($_.Exception.Message)") }
    }
    return @{ identifier = $Identifier; out = ($reasons.Count -gt 0); reasons = @($reasons); items = @($items); back = (Format-PsaDate $back); evidence = @($seen) }
}

# The technician to hand the ticket to: an active member who is in, picked by $PickBy:
#   fewest-open   fewest open tickets (default)
#   least-recent  the one whose newest assigned ticket is oldest, so tickets rotate round the team
#   list-order    the first one in the list (OOO-BackupPool order, else the team's order)
# Candidates come from $Pool (identifiers or Member #s, in order) when it has any, else from the ticket's team on
# its board, else from every team on the board. Members in $Exclude (the ones who are out) are skipped.
# Returns @{ identifier; open; source; how; considered } or @{ identifier = ''; source; considered } when nobody fits.
# Unverified on a live ConnectWise: GET /service/boards/{id}/teams/{id} and its members list of member record ids.
function Find-OooReplacement {
    param([string]$PickBy = 'fewest-open', [string[]]$Pool = @(), [string]$PoolLabel = 'the backup list', [string]$BoardId = '', [string]$TeamId = '', [string[]]$Exclude = @(), [datetime]$Now, [string[]]$InTypes, [string[]]$ScheduleTypes, [int]$Max = 25)
    $considered = New-Object System.Collections.ArrayList
    $skip = @{}; foreach ($x in @($Exclude)) { if ($x) { $skip[([string]$x).ToLowerInvariant()] = $true } }
    $cands = New-Object System.Collections.ArrayList   # @{ identifier; order }
    $seen = @{}
    $add = { param($rec, [string]$label) if ($null -eq $rec) { $null = $considered.Add("$label isn't a ConnectWise member."); return }; $i = [string](Get-PsaProp $rec 'identifier'); if (-not $i) { return }; $k = $i.ToLowerInvariant(); if ($seen.ContainsKey($k)) { return }; $seen[$k] = $true; if ($skip.ContainsKey($k)) { return }; if ((Get-PsaProp $rec 'inactiveFlag') -eq $true) { $null = $considered.Add("${i}: inactive."); return }; $null = $cands.Add(@{ identifier = $i; order = $cands.Count }) }
    $source = ''
    $poolList = @($Pool | Where-Object { $_ })
    if ($poolList.Count) {
        $source = $PoolLabel
        foreach ($p in $poolList) { & $add (Get-OooMember ([string]$p)) "'$p'" }
    }
    elseif ($BoardId) {
        $ids = @()
        try {
            if ($TeamId) { $source = 'the ticket''s team'; $ids = @(Get-PsaProp (Invoke-Psa GET "/service/boards/$BoardId/teams/$TeamId") 'members') }
            else { $source = 'the board''s teams'; foreach ($t in @(Invoke-Psa GET "/service/boards/$BoardId/teams?pageSize=100" | Where-Object { $null -ne $_ })) { $ids += @(Get-PsaProp $t 'members') } }
        }
        catch {
            if ([string]$_.Exception.Message -notmatch '\(HTTP 40[134]\)') { throw }
            $null = $considered.Add("ConnectWise wouldn't list $source ($([string]$_.Exception.Message)). Give the API member Inquire access to service board teams (System > Table Setup), or set OOO-BackupPool.")
            $ids = @()
        }
        $ids = @($ids | Where-Object { -not (Test-PsaBlank $_) } | ForEach-Object { [string]$_ } | Select-Object -Unique)
        if ($ids.Count) {
            $q = ConvertTo-PsaQuery "id in ($($ids -join ','))"
            $recs = @(Invoke-Psa GET "/system/members?conditions=$q&fields=id,identifier,inactiveFlag&pageSize=200" | Where-Object { $null -ne $_ })
            foreach ($id in $ids) { $r = @($recs | Where-Object { [string](Get-PsaProp $_ 'id') -eq $id }) | Select-Object -First 1; & $add $r "Member #$id" }
        }
        elseif (-not $considered.Count) { $null = $considered.Add("$source has no members.") }
    }
    else { $source = 'nowhere'; $null = $considered.Add('The ticket has no board and no OOO-BackupPool is set.') }
    if ($cands.Count -gt $Max) { $null = $considered.Add("Only the first $Max of $($cands.Count) candidates were checked."); $cands = @($cands[0..($Max - 1)]) }
    $PickBy = ([string]$PickBy).Trim().ToLowerInvariant(); if (-not $PickBy) { $PickBy = 'fewest-open' }
    $unknown = [int]::MaxValue
    # Each candidate gets a rank: open-ticket count, the date of their newest assigned ticket, or the list position.
    foreach ($c in $cands) {
        $c.open = $unknown; $c.last = $null
        if ($PickBy -eq 'fewest-open') { $n = $null; try { $n = Get-PsaOpenCount $c.identifier } catch { $n = $null }; if ($null -ne $n) { $c.open = [int]$n } }
        elseif ($PickBy -eq 'least-recent') { try { $c.last = Get-PsaLastAssigned $c.identifier } catch { $c.last = $null } }
    }
    $rankText = {
        param($c)
        if ($PickBy -eq 'fewest-open') { if ($c.open -eq $unknown) { 'open tickets unknown' } elseif ($c.open -eq 1) { '1 open ticket' } else { "$($c.open) open tickets" } }
        elseif ($PickBy -eq 'least-recent') { if ($null -eq $c.last) { 'last assignment unknown' } elseif ($c.last -eq [datetime]::MinValue) { 'no tickets assigned' } else { "newest ticket $(Format-PsaDate $c.last)" } }
        else { "#$($c.order + 1) in the list" }
    }
    $sorted = @(switch ($PickBy) {
        'least-recent' { @($cands | Sort-Object @{ e = { if ($null -eq $_.last) { [datetime]::MaxValue } else { $_.last } } }, @{ e = { $_.order } }) }
        'list-order' { @($cands | Sort-Object @{ e = { $_.order } }) }
        default { @($cands | Sort-Object @{ e = { $_.open } }, @{ e = { $_.order } }) }
    })
    $how = switch ($PickBy) { 'least-recent' { 'longest since their last ticket' } 'list-order' { 'first available in the list' } default { 'fewest open tickets' } }
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $c = $sorted[$i]
        $s = Get-OooMemberStatus -Identifier $c.identifier -Now $Now -InTypes $InTypes -ScheduleTypes $ScheduleTypes
        if ($s.out) { $null = $considered.Add("$($c.identifier) ($(& $rankText $c)): out ($($s.reasons -join '; '))."); continue }
        $null = $considered.Add("$($c.identifier) ($(& $rankText $c)): in. Picked.")
        # Everyone after the pick, with their rank, so the run shows why they lost. Their availability isn't read.
        for ($j = $i + 1; $j -lt $sorted.Count; $j++) {
            $o = $sorted[$j]
            $why = switch ($PickBy) {
                'least-recent' { "$($c.identifier) has gone longer without a ticket" }
                'list-order' { "$($c.identifier) is earlier in the list" }
                default { if ($o.open -eq $c.open) { "same count as $($c.identifier), later in the list" } else { "more open tickets than $($c.identifier)" } }
            }
            $null = $considered.Add("$($o.identifier) ($(& $rankText $o)): not picked, $why.")
        }
        $howFull = if ($PickBy -eq 'fewest-open' -and $c.open -ne $unknown) { "fewest open tickets ($($c.open))" } else { $how }
        return @{ identifier = $c.identifier; open = $c.open; source = $source; how = $howFull; considered = @($considered) }
    }
    return @{ identifier = ''; open = $null; source = $source; considered = @($considered) }
}

# The coverage table: a ConnectWise Knowledge Base article (title or id) listing who covers for whom, in order.
# One row per line, "who: first, second, ...", or a two-column table. "who" is a member (identifier or Member #),
# "Board <board name>", or "*" for everyone else. Lines starting with # are notes.
# Returns @{ rows = @{ key = @(members) }; title; error }. Keys: member identifier or number lowercased,
# "board:<name>" lowercased, or "*".
function Get-OooCoverage {
    param([string]$Article)
    $res = @{ rows = @{}; title = ''; error = '' }
    $a = $null
    try {
        if ($Article -match '^\d+$') { $a = Invoke-Psa GET "/service/knowledgeBaseArticles/$Article" }
        else {
            $q = ConvertTo-PsaQuery ('title="' + $Article.Replace('\', '\\').Replace('"', '\"') + '"')
            $a = @(Invoke-Psa GET "/service/knowledgeBaseArticles?conditions=$q&pageSize=5" | Where-Object { $null -ne $_ }) | Select-Object -First 1
        }
    }
    catch {
        $m = [string]$_.Exception.Message
        $res.error = if ($m -match '\(HTTP 40[13]\)') { "ConnectWise wouldn't read the coverage article '$Article' ($m). Give the API member Inquire access to the Knowledge Base." } elseif ($m -match '\(HTTP 404\)') { "There is no Knowledge Base article '$Article'." } else { "The coverage article '$Article' couldn't be read: $m" }
        return $res
    }
    if ($null -eq $a) { $res.error = "There is no Knowledge Base article titled '$Article'. Check OOO-CoverageArticle."; return $res }
    $res.title = [string](Get-PsaProp $a 'title')
    # Unverified on a live ConnectWise: which article fields hold the body (issue and resolution are read).
    $body = (@('issue', 'resolution', 'description', 'text') | ForEach-Object { [string](Get-PsaProp $a $_) } | Where-Object { $_ }) -join "`n"
    # HTML to lines: rows and paragraphs end a line, table cells become a separator.
    # Table rows first, cell by cell, so a <p> or <br> inside a cell (as the ConnectWise editor writes) can't split it.
    $body = [regex]::Replace($body, '(?is)<tr[^>]*>(.*?)</tr>', { param($m) $cells = @([regex]::Matches($m.Groups[1].Value, '(?is)<t[dh][^>]*>(.*?)</t[dh]>') | ForEach-Object { (($_.Groups[1].Value -replace '(?i)<br\s*/?>|</p>', ' ') -replace '<[^>]+>', '').Trim() }); "`n" + ($cells -join ' | ') + "`n" })
    $body = $body -replace '(?i)</(p|div|li|h\d)>|<br\s*/?>', "`n" -replace '<[^>]+>', ''
    $body = [System.Net.WebUtility]::HtmlDecode($body)
    foreach ($line in ($body -split "`r?`n")) {
        $l = $line.Trim().Trim('|').Trim()
        if (-not $l -or $l.StartsWith('#') -or $l -match '^[-:| ]+$') { continue }
        $parts = $l -split '\s*[:|]\s*', 2
        if ($parts.Count -lt 2) { continue }
        $who = $parts[0].Trim(); $list = @(($parts[1] -split '[,;|]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if (-not $who -or -not $list.Count) { continue }
        if ($who -match '^(?i)(who is out|out|technician|tech|member)$') { continue }   # a table header row
        $key = if ($who -eq '*') { '*' } elseif ($who -match '^(?i)board\s+(.+)$') { 'board:' + $Matches[1].Trim().ToLowerInvariant() } else { $who.ToLowerInvariant() }
        $res.rows[$key] = $list
    }
    if (-not $res.rows.Count) { $res.error = "The coverage article '$($res.title)' has no rows in the form 'who: first, second'." }
    return $res
}

# The row that covers an out technician on a board: their own row (by identifier or Member #), then the board's,
# then "*". Returns @{ list; label } or $null.
function Select-OooCoverageRow {
    param($Coverage, [string]$Identifier, [string]$MemberId = '', [string]$Board = '')
    $rows = $Coverage.rows
    $tries = @(, @($Identifier.ToLowerInvariant(), "the $Identifier row"))
    if ($MemberId) { $tries += , @($MemberId, "the $Identifier row") }
    if ($Board) { $tries += , @(('board:' + $Board.ToLowerInvariant()), "the $Board board row") }
    $tries += , @('*', 'the * row')
    foreach ($t in $tries) { if ($rows.ContainsKey($t[0])) { return @{ list = @($rows[$t[0]]); label = $t[1] } } }
    return $null
}

# The ticket's schedule entries (type S) for one member: what puts the ticket on their calendar and resources list.
function Get-OooTicketEntries {
    param([string]$TicketId, [string]$Identifier)
    $q = ConvertTo-PsaQuery ("objectId=$TicketId and type/identifier=""S"" and member/identifier=""" + $Identifier.Replace('"', '') + '"')
    return @(Invoke-Psa GET "/schedule/entries?conditions=$q&pageSize=50" | Where-Object { $null -ne $_ })
}

# A member record by identifier, or $null. Used to check the backup technician exists and is active.
function Get-OooMember {
    param([string]$Identifier)
    if ($Identifier -match '^\d+$') { try { return (Invoke-Psa GET "/system/members/$Identifier") } catch { return $null } }
    $q = ConvertTo-PsaQuery ('identifier="' + $Identifier.Replace('"', '') + '"')
    $m = @(Invoke-Psa GET "/system/members?conditions=$q&pageSize=1" | Where-Object { $null -ne $_ })
    if ($m.Count) { return $m[0] }
    return $null
}
# ---------- end src/availability.ps1 ----------
